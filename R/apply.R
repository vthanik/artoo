# apply.R -- apply_spec(), the transactional conform pipeline.
#
# Runs the ordered internal steps (apply_steps.R) over a raw data frame to
# produce one conformed to its spec and carrying vport_meta, then optionally
# runs check_spec(). The original input is never mutated; any step aborting
# leaves it untouched.

# The full ordered pipeline. `steps =` selects a subset of these.
.apply_step_ids <- c(
  "scaffold",
  "drop",
  "coerce",
  "decode",
  "order",
  "sort",
  "stamp"
)

# Validate a user-supplied `steps` subset against the pipeline.
#' @noRd
.check_steps <- function(steps, call = rlang::caller_env()) {
  available <- .apply_step_ids
  if (!is.character(steps) || anyNA(steps) || !length(steps)) {
    cli::cli_abort(
      c(
        "{.arg steps} must be a character vector of step names.",
        "i" = "Available: {.val {available}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  bad <- setdiff(steps, available)
  if (length(bad)) {
    cli::cli_abort(
      c(
        "Unknown {.arg steps} value{?s}: {.val {bad}}.",
        "i" = "Available: {.val {available}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  # Keep canonical order regardless of how the user listed them.
  .apply_step_ids[.apply_step_ids %in% steps]
}

#' Conform a data frame to its spec
#'
#' Run the ordered, transactional vport pipeline that turns a raw analysis
#' data frame into one conformed to its specification and carrying
#' `vport_meta`. This is the middle of the workflow (spec -> apply_spec ->
#' read_/write_): the conformed frame is ready for any `write_*()` codec, and
#' the metadata it now carries makes that write lossless. The input is never
#' mutated; if any step aborts, the call leaves your data untouched.
#'
#' @details
#' **Ordered pipeline.** The steps run in a fixed order: scaffold missing
#' variables (typed NA), drop columns the spec does not declare, coerce each
#' column to its CDISC dataType, optionally decode codelists (see `decode`),
#' reorder columns to the spec, sort rows by the dataset keys, then stamp the
#' metadata. Use `steps` to run a subset for surgical work.
#'
#' **Decode is off by default.** Coded variables keep their submission values
#' (e.g. `SEX` stays `"M"`); membership is reported by [check_spec()], not
#' enforced by mutation. Opt in with `decode = "to_decode"` or `"to_code"`.
#'
#' @param x *The raw data frame to conform.* `<data.frame>: required`.
#' @param spec *The specification to conform to.* `<vport_spec>: required`.
#' @param dataset *The dataset whose rules apply.* `<character(1)>:
#'   required`. Must name a dataset in `spec`.
#' @param check *What to do with conformance findings.* `<character(1)>`.
#'   One of:
#'   * `"warn"` (default) run [check_spec()], attach the findings, warn on
#'     any error-severity finding.
#'   * `"strict"` abort with `vport_error_conformance` on any error-severity
#'     finding.
#'   * `"off"` skip the check entirely.
#' @param decode *Codelist translation direction.* `<character(1)>`. One of
#'   `"none"` (default, no transform), `"to_decode"` (code -> decode), or
#'   `"to_code"` (decode -> code).
#' @param no_match *Policy for values absent from a codelist when decoding.*
#'   `<character(1)>`. One of `"error"` (default), `"keep"`, or `"na"`. Has
#'   no effect when `decode = "none"`.
#' @param steps *Run only a subset of the pipeline.* `<character> | NULL`.
#'   When `NULL` (default) every step runs; otherwise any of
#'   `"scaffold"`, `"drop"`, `"coerce"`, `"decode"`, `"order"`, `"sort"`,
#'   `"stamp"`, applied in their canonical order.
#'
#'   **Tip:** omit `"stamp"` to conform without attaching metadata.
#'
#' @return *A conformed `<data.frame>`* carrying `vport_meta` (read it with
#'   [get_meta()]) and a `vport.conformance` attribute when `check` ran.
#'   Hand it to any `write_*()` codec.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: conform ADSL, then read its metadata ----
#' #
#' # The raw frame is scaffolded, coerced, ordered, sorted, and stamped; the
#' # result carries the CDISC metadata get_meta() reads back.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL")
#' get_meta(adsl)@dataset$records
#'
#' # ---- Example 2: a surgical subset of the pipeline ----
#' #
#' # Run only coercion and column ordering, skipping the metadata stamp, when
#' # you just want the columns typed and in spec order.
#' typed <- apply_spec(cdisc_dm, spec, "DM", steps = c("coerce", "order"))
#' names(typed)[1:3]
#'
#' @seealso [check_spec()] for the conformance findings; [get_meta()] /
#'   [set_meta()] for the metadata it stamps.
#' @export
apply_spec <- function(
  x,
  spec,
  dataset,
  check = c("warn", "strict", "off"),
  decode = c("none", "to_decode", "to_code"),
  no_match = c("error", "keep", "na"),
  steps = NULL
) {
  call <- rlang::caller_env()
  check <- match.arg(check)
  decode <- match.arg(decode)
  no_match <- match.arg(no_match)

  if (!is.data.frame(x)) {
    cli::cli_abort(
      c(
        "{.arg x} must be a data frame.",
        "x" = "You supplied {.obj_type_friendly {x}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  .check_spec_arg(spec, call = call)
  .check_dataset_arg(spec, dataset, call = call)
  run <- if (is.null(steps)) .apply_step_ids else .check_steps(steps, call)

  info <- .apply_info(spec, dataset, call = call)
  out <- x
  if ("scaffold" %in% run) {
    out <- .scaffold_vars(out, info, call)
  }
  if ("drop" %in% run) {
    out <- .drop_unspec(out, info, call)
  }
  if ("coerce" %in% run) {
    out <- .coerce_types(out, info, call)
  }
  if ("decode" %in% run) {
    out <- .decode_codelists(out, info, spec, decode, no_match, call)
  }
  if ("order" %in% run) {
    out <- .order_cols(out, info, call)
  }
  if ("sort" %in% run) {
    out <- .sort_keys(out, info, call)
  }
  if ("stamp" %in% run) {
    out <- .stamp_meta(out, info, spec, dataset, call)
  }

  if (check != "off") {
    findings <- check_spec(out, spec, dataset)
    attr(out, "vport.conformance") <- findings
    errs <- findings[findings$severity == "error", , drop = FALSE]
    if (nrow(errs)) {
      msg <- c(
        "Data does not conform to the spec for {.val {dataset}}.",
        stats::setNames(errs$message, rep("x", nrow(errs)))
      )
      if (check == "strict") {
        cli::cli_abort(msg, class = "vport_error_conformance", call = call)
      } else {
        cli::cli_warn(
          c(
            "{nrow(errs)} conformance error{?s} for {.val {dataset}}.",
            "i" = "See {.code attr(x, \"vport.conformance\")} for details."
          ),
          class = "vport_warning_conformance",
          call = call
        )
      }
    }
  }
  out
}
