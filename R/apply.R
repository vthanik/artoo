# apply.R — apply_spec(), the transactional conform pipeline.
#
# Runs the ordered internal steps (apply_steps.R) over a raw data frame to
# produce one conformed to its spec and carrying artoo_meta, then runs
# check_spec(). The original input is never mutated; any step aborting
# leaves it untouched.

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
#' **Ordered pipeline.** Five fixed steps run in order: scaffold missing
#' spec variables (typed `NA`), coerce each column to its CDISC dataType,
#' reorder columns to the spec, sort rows by the dataset keys, then stamp
#' the metadata.
#'
#' **Extras are kept by default.** A column the spec does not declare
#' survives the pipeline (ordered after the declared ones), is *reported*
#' by the `extra_variable` conformance finding, and round-trips through
#' every `write_*()` codec with metadata inferred from its R class —
#' membership reported, never enforced by silent destruction. Keeping is
#' the default because artoo is lossless by construction: a
#' metadata-application step that silently discarded columns would break
#' that contract, so trimming data is always an explicit, announced choice
#' rather than a default side effect.
#' `extra = "drop"` opts in to trim-to-spec (the returned frame carries
#' exactly the spec's columns): the undeclared
#' columns are removed *after* the findings are computed, so the
#' `extra_variable` finding remains the audit trail of what was dropped,
#' and the drop itself is always announced (`artoo_message_apply`) — even
#' under `conformance = "off"`.
#'
#' **Lossless or abort.** A coercion that would damage values — an
#' `integer` dataType truncating fractions or overflowing R's 32-bit range
#' — aborts with `artoo_error_type` before any value is touched. There is
#' no opt-out: fix the spec (dataType `"float"` or `"decimal"` keeps
#' fractions) rather than accept silent damage. The condition carries the
#' offending rows as data: `cnd$variables` is a data frame with columns
#' `variable`, `data_type`, `n`, and `reason` (`"truncated"` /
#' `"overflowed"`), so a pipeline can collect every mismatch in one
#' `tryCatch(..., artoo_error_type = function(cnd) cnd$variables)` pass.
#' The NA-introduction warning (`artoo_warning_coercion`) carries the same
#' frame with `reason = "na_introduced"`, and a `conformance = "abort"`
#' failure carries the complete findings frame as `cnd$findings`.
#'
#' **Values are never translated.** Coded variables keep their submission
#' values (`SEX` stays `"M"`); codelist translation is its own verb,
#' [decode_column()].
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
#'   **Note:** this governs only the *findings* disposition — what is
#'   *reported*. Pipeline errors are a different category and abort under
#'   every setting, including `"off"`: an unknown dataset, and above all
#'   lossy coercion (`artoo_error_type`), which no `conformance` value
#'   bypasses. If the abort names variables whose spec dataType is
#'   `integer` but whose data carries fractions, the fix is the spec
#'   (retype to `"float"`/`"decimal"`), not this argument; the condition's
#'   `$variables` frame lists every offender.
#' @param na_position *Where missing key values sort.* `<character(1)>`. One
#'   of `"first"` (default) or `"last"`. `"first"` matches SAS `PROC SORT`
#'   (and the FDA submission convention) by ordering missings before present
#'   values; `"last"` matches R's `order()` and the pandas/Polars default.
#'   Both are lossless; pick the one your comparison target uses.
#' @param extra *What happens to undeclared columns.* `<character(1)>`.
#'   An "extra" is a column of `x` the spec does not declare — typically a
#'   derivation temporary. One of:
#'   * `"keep"` (default) extras ride along after the declared columns,
#'     reported by the `extra_variable` finding.
#'   * `"drop"` the returned frame carries exactly the spec's columns;
#'     the drop is announced (`artoo_message_apply`) and the
#'     `extra_variable` finding still reports what was removed.
#'
#'   **Interaction:** under `conformance = "abort"` an error-severity
#'   finding aborts *before* any drop — the trim never masks a failure.
#'
#'   **Note:** `"keep"` is the default deliberately. artoo is a lossless
#'   carrier, so the metadata step never silently discards a column;
#'   extras are surfaced every run (the `extra_variable` finding, and a
#'   warning under `conformance = "warn"`), making `"drop"` a conscious opt-in.
#'
#' @return *A conformed `<data.frame>`* carrying `artoo_meta` (read it with
#'   [get_meta()]) and, unless `conformance = "off"`, the findings frame
#'   [conformance()] reads back. Hand it to any `write_*()` codec.
#'
#' @examples
#' # ---- Example 1: conform ADSL, then read its metadata ----
#' #
#' # The bundled adam_spec describes ADSL; the raw frame is scaffolded,
#' # coerced, ordered, sorted, and stamped with the CDISC metadata
#' # get_meta() reads back.
#' adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL")
#' get_meta(adsl)@dataset$records
#'
#' # ---- Example 2: extras are kept and reported, or dropped on request ----
#' #
#' # By default a column outside the spec rides along (reported by the
#' # extra_variable finding) and still writes losslessly; extra = "drop"
#' # trims to the spec, announced and still reported. DM is SDTM, so it
#' # conforms against the bundled sdtm_spec.
#' raw <- cdisc_dm
#' raw$DERIVED <- seq_len(nrow(raw))
#' dm <- apply_spec(raw, sdtm_spec, "DM")
#' findings <- conformance(dm)
#' findings[findings$check == "extra_variable", c("variable", "message")]
#' trimmed <- apply_spec(raw, sdtm_spec, "DM", extra = "drop")
#' "DERIVED" %in% names(trimmed)
#'
#' @seealso
#' **Check:** [check_spec()] for the findings; [conformance()] to read them
#' back.
#'
#' **Translate:** [decode_column()] for codelist value mapping.
#'
#' **Metadata:** [get_meta()] / [set_meta()] for what the stamp attaches.
#' @export
apply_spec <- function(
  x,
  spec,
  dataset,
  conformance = c("warn", "abort", "off"),
  na_position = c("first", "last"),
  extra = c("keep", "drop")
) {
  call <- rlang::caller_env()
  conformance <- match.arg(conformance)
  na_position <- match.arg(na_position)
  extra <- match.arg(extra)

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

  info <- .apply_info(spec, dataset, call = call)
  out <- .scaffold_vars(x, info, call)
  out <- .coerce_types(out, info, call)
  out <- .order_cols(out, info, call)
  out <- .sort_keys(out, info, na_position, call)
  out <- .stamp_meta(out, info, spec, dataset, call)

  if (conformance != "off") {
    findings <- check_spec(out, spec, dataset)
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
        # The warn path returns the frame with the findings attribute; the
        # abort path is the only place the report would otherwise be lost,
        # so the condition carries it whole.
        .artoo_abort(
          msg,
          kind = "conformance",
          findings = findings,
          call = call
        )
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

  # Trim-to-spec runs LAST, after the findings were computed on the full
  # frame: the extra_variable finding is the audit trail of what was
  # dropped, and a conformance abort fires before any drop (transactional).
  # Removal via [[<- NULL keeps the frame attributes (metadata_json,
  # artoo.sort, artoo.conformance) that a [cols] subset would strip; the
  # message is unconditional, so a drop is never silent even under
  # conformance = "off", where no finding is computed at all.
  if (extra == "drop") {
    extras <- setdiff(names(out), info$spec_vars)
    if (length(extras)) {
      for (nm in extras) {
        out[[nm]] <- NULL
      }
      out <- set_meta(out, .meta_select_columns(get_meta(out), names(out)))
      .artoo_inform(
        "Dropped {length(extras)} undeclared variable{?s}: {.var {extras}}",
        kind = "apply"
      )
    }
  }
  out
}
