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
#' **Ordered pipeline.** Four fixed steps run in order: coerce each column
#' to its CDISC dataType, reorder columns to the spec, sort rows by the
#' dataset keys, then stamp the metadata. A spec variable the data lacks is
#' never fabricated as an empty column: artoo is a lossless carrier, not a
#' deriver. It is reported instead, an informational heads-up at apply time
#' plus a `missing_variable` finding (when mandatory) or `missing_permissible`
#' (when not), and left absent, so the conformed frame carries only the
#' columns the data actually had.
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
#' exactly the spec's columns): the undeclared columns are removed *before*
#' the check, so the findings describe exactly the returned frame (a dropped
#' column is never reported as `extra_variable`), and the drop itself is
#' always announced (`artoo_message_apply`) as the audit trail of what was
#' removed — even under `conformance = "off"`.
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
#'     the drop is announced (`artoo_message_apply`), and that message is
#'     the audit trail of what was removed.
#'
#'   **Interaction:** the drop runs *before* the check, so [conformance()]
#'   reports only the columns the returned frame keeps. Under
#'   `conformance = "abort"` an error-severity finding still aborts (those
#'   findings arise only on spec-declared columns, which the drop never
#'   touches) and the input is never mutated, so the trim cannot mask a
#'   failure.
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
#' # The bundled adam_spec describes ADSL; the raw frame is coerced,
#' # ordered, sorted, and stamped with the CDISC metadata get_meta() reads
#' # back. Variables the spec declares but this extract never derived are
#' # reported (not added), readable via conformance().
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
  out <- .coerce_types(x, info, call)
  out <- .order_cols(out, info, call)
  out <- .sort_keys(out, info, na_position, call)
  out <- .stamp_meta(out, info, spec, dataset, call)

  # A spec variable the data lacks is never fabricated: artoo is a lossless
  # carrier, not a deriver, so an absent declared variable is reported, not
  # filled with an empty column. Announce it here and let check_spec() raise
  # the structured missing_variable / missing_permissible finding. The
  # heads-up fires under every conformance mode so the signal survives
  # conformance = "off"; the conformance() hint appears only when findings
  # are actually attached.
  missing <- setdiff(info$spec_vars, names(out))
  if (length(missing)) {
    .artoo_inform(
      c(
        "{length(missing)} variable{?s} the spec declares {?is/are} absent from the data (not added): {.var {missing}}.",
        if (conformance != "off") {
          c("i" = "See {.code conformance(x)} for the findings.")
        }
      ),
      kind = "apply"
    )
  }

  # Trim-to-spec runs BEFORE the check so the findings describe exactly the
  # columns the returned frame carries: a dropped column is never reported as
  # extra_variable / variable_name. The drop is its own audit trail via the
  # unconditional inform below, which fires even under conformance = "off"
  # (where no finding is computed at all). Removal via [[<- NULL keeps the
  # frame attributes (metadata_json, artoo.sort) that a [cols] subset would
  # strip; set_meta then trims the column metadata to match.
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
  out
}
