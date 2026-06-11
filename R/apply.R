# apply.R -- apply_spec(), the transactional conform pipeline.
#
# Runs the ordered internal steps (apply_steps.R) over a raw data frame to
# produce one conformed to its spec and carrying artoo_meta, then optionally
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
    .artoo_abort(
      c(
        "{.arg steps} must be a character vector of step names.",
        "i" = "Available: {.val {available}}."
      ),
      kind = "input",
      call = call
    )
  }
  bad <- setdiff(steps, available)
  if (length(bad)) {
    .artoo_abort(
      c(
        "Unknown {.arg steps} value{?s}: {.val {bad}}.",
        "i" = "Available: {.val {available}}."
      ),
      kind = "input",
      call = call
    )
  }
  # Keep canonical order regardless of how the user listed them.
  .apply_step_ids[.apply_step_ids %in% steps]
}

#' Conform a data frame to its spec
#'
#' Run the ordered, transactional artoo pipeline that turns a raw analysis
#' data frame into one conformed to its specification and carrying
#' `artoo_meta`. This is the middle of the workflow (spec -> apply_spec ->
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
#' @param spec *The specification to conform to.* `<artoo_spec>: required`.
#' @param dataset *The dataset whose rules apply.* `<character(1)>:
#'   required`. Must name a dataset in `spec`.
#' @param conformance *What to do with conformance findings.*
#'   `<character(1)>`. One of:
#'   * `"warn"` (default) run [check_spec()], attach the findings (read
#'     them with [conformance()]), warn on any error-severity finding.
#'   * `"abort"` abort with `artoo_error_conformance` on any error-severity
#'     finding.
#'   * `"off"` skip the check entirely.
#'
#'   **Note:** this governs only the *findings* disposition; pipeline
#'   errors (an unknown dataset, lossy coercion under `on_lossy =
#'   "error"`) abort regardless.
#' @param decode *Codelist translation direction.* `<character(1)>`. One of
#'   `"none"` (default, no transform), `"to_decode"` (code -> decode), or
#'   `"to_code"` (decode -> code).
#' @param no_match *Policy for values absent from a codelist when decoding.*
#'   `<character(1)>`. One of `"error"` (default), `"keep"`, or `"na"`. Has
#'   no effect when `decode = "none"`.
#' @param on_lossy *Policy when coercion would damage values.*
#'   `<character(1)>`. One of:
#'   * `"error"` (default) abort before any value is damaged: an `integer`
#'     dataType truncating fractional values (a height losing its decimals)
#'     or overflowing R's 32-bit range (values becoming `NA`) is a
#'     data-integrity event, not a nuisance.
#'   * `"warn"` apply the lossy coercion and warn
#'     (`artoo_warning_coercion`).
#'
#'   **Tip:** [check_spec()] flags the same conditions before any coercion
#'   runs (`integer_fraction`, `integer_overflow`), so a pre-flight check
#'   catches them without touching the data.
#' @param trim *Match codelist values after trimming whitespace.*
#'   `<logical(1)>: default TRUE`. Real data carries trailing blanks; a value
#'   that matches only after trimming still decodes, with a
#'   `artoo_warning_codelist` naming the variants. Membership *checking*
#'   ([check_spec()]) always compares exactly. Has no effect when
#'   `decode = "none"`.
#' @param ignore_case *Match codelist values case-insensitively.*
#'   `<logical(1)>: default FALSE`. Case differences are usually genuine CT
#'   violations, so this is opt-in; a case-only match warns like `trim`. Has
#'   no effect when `decode = "none"`.
#' @param na_position *Where missing key values sort.* `<character(1)>`. One
#'   of `"first"` (default) or `"last"`. `"first"` matches SAS `PROC SORT`
#'   (and the FDA submission convention) by ordering missings before present
#'   values; `"last"` matches R's `order()` and the pandas/Polars default.
#'   Affects only the `"sort"` step.
#' @param steps *Run only a subset of the pipeline.* `<character> | NULL`.
#'   When `NULL` (default) every step runs; otherwise any of
#'   `"scaffold"`, `"drop"`, `"coerce"`, `"decode"`, `"order"`, `"sort"`,
#'   `"stamp"`, applied in their canonical order.
#'
#'   **Tip:** omit `"stamp"` to conform without attaching metadata.
#'   **Interaction:** mutually exclusive with `profile`.
#' @param profile *A named preset of pipeline steps.* `<character(1)> |
#'   NULL`. `NULL` (default) runs the full pipeline. `"xportr"` reproduces
#'   the legacy metacore + metatools + xportr shape -- drop, order, sort,
#'   stamp; no scaffolding, no type coercion, no decode -- for teams
#'   matching an existing pipeline's output during migration.
#'
#'   **Interaction:** mutually exclusive with `steps` (a profile *is* a
#'   steps preset; supplying both aborts).
#' @param checks *Which conformance dimensions to evaluate.* `<artoo_checks>
#'   | NULL`. When `NULL` (default) every dimension runs; pass a
#'   [artoo_checks()] control to disable some. Has no effect when
#'   `conformance = "off"`.
#'
#' @return *A conformed `<data.frame>`* carrying `artoo_meta` (read it with
#'   [get_meta()]) and, unless `conformance = "off"`, the findings frame
#'   [conformance()] reads back. Hand it to any `write_*()` codec.
#'
#' @examples
#' spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
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
  conformance = c("warn", "abort", "off"),
  decode = c("none", "to_decode", "to_code"),
  no_match = c("error", "keep", "na"),
  on_lossy = c("error", "warn"),
  trim = TRUE,
  ignore_case = FALSE,
  na_position = c("first", "last"),
  steps = NULL,
  profile = NULL,
  checks = NULL
) {
  call <- rlang::caller_env()
  conformance <- match.arg(conformance)
  decode <- match.arg(decode)
  no_match <- match.arg(no_match)
  on_lossy <- match.arg(on_lossy)
  na_position <- match.arg(na_position)
  if (!is.null(profile)) {
    if (!is.null(steps)) {
      .artoo_abort(
        c(
          "{.arg profile} and {.arg steps} are mutually exclusive.",
          "i" = "A profile is a steps preset; pick one."
        ),
        kind = "input",
        call = call
      )
    }
    if (
      !is.character(profile) || length(profile) != 1L || !profile %in% "xportr"
    ) {
      .artoo_abort(
        c(
          "{.arg profile} must be {.val xportr} or NULL.",
          "x" = "You supplied {.obj_type_friendly {profile}}."
        ),
        kind = "input",
        call = call
      )
    }
    steps <- switch(profile, xportr = c("drop", "order", "sort", "stamp"))
  }
  for (flag in c("trim", "ignore_case")) {
    fv <- get(flag)
    if (!is.logical(fv) || length(fv) != 1L || is.na(fv)) {
      .artoo_abort(
        c(
          "{.arg {flag}} must be a single TRUE or FALSE.",
          "x" = "You supplied {.obj_type_friendly {fv}}."
        ),
        kind = "input",
        call = call
      )
    }
  }

  if (!is.data.frame(x)) {
    .artoo_abort(
      c(
        "{.arg x} must be a data frame.",
        "x" = "You supplied {.obj_type_friendly {x}}."
      ),
      kind = "input",
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
    out <- .coerce_types(out, info, on_lossy, call)
  }
  if ("decode" %in% run) {
    out <- .decode_codelists(
      out,
      info,
      spec,
      decode,
      no_match,
      trim,
      ignore_case,
      call
    )
  }
  if ("order" %in% run) {
    out <- .order_cols(out, info, call)
  }
  if ("sort" %in% run) {
    out <- .sort_keys(out, info, na_position, call)
  }
  if ("stamp" %in% run) {
    out <- .stamp_meta(out, info, spec, dataset, call)
  }

  if (conformance != "off") {
    findings <- check_spec(out, spec, dataset, decode = decode, checks = checks)
    attr(out, "artoo.conformance") <- findings
    errs <- findings[findings$severity == "error", , drop = FALSE]
    if (nrow(errs)) {
      # Finding messages embed raw data values; escape so a "{" in the data
      # renders literally instead of crashing cli interpolation. Cap the
      # bullets at 3 so a wide failure does not flood the console.
      shown <- utils::head(errs$message, 3L)
      msg <- c(
        "Data does not conform to the spec for {.val {dataset}}.",
        stats::setNames(.cli_escape(shown), rep("x", length(shown)))
      )
      if (conformance == "abort") {
        .artoo_abort(msg, kind = "conformance", call = call)
      } else {
        .artoo_warn(
          c(
            "{nrow(errs)} conformance error{?s} for {.val {dataset}}.",
            "i" = "Run {.code conformance(x)} on the returned frame to see every finding."
          ),
          kind = "conformance",
          call = call
        )
      }
    }
  }
  out
}
