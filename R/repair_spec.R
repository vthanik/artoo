# repair_spec.R — repair_spec(), auto-apply dataType fixes from findings.
#
# Built on set_type(): turns the integer_fraction / integer_overflow
# findings that check_spec() / check_study() report into a corrected spec in
# one call, so "open the workbook, find the row, retype, re-export" (per
# offending variable, per dataset) becomes one line.

#' Repair a spec from its conformance findings
#'
#' Take the `integer_fraction` and `integer_overflow` findings a
#' [check_spec()] or [check_study()] run reports and return a new spec with
#' every offending variable retyped to `"float"`, so a frame that the
#' original spec would refuse to coerce now conforms. This closes the loop on
#' the spec-side fix: inspect the findings, then apply them all at once
#' instead of editing the source workbook variable by variable. Persist the
#' result with [write_spec()].
#'
#' @details
#' **Scope.** Only the two lossy-integer findings are repaired
#' (`integer_fraction`, `integer_overflow`) — both mean "the spec says
#' `integer` but the data is not", and `"float"` is the loss-free fix. Other
#' findings are ignored; this is not a general spec rewriter. When no
#' repairable finding is present the spec is returned unchanged, with a note.
#'
#' **Built on [set_type()].** Each `(dataset, variable)` pair is applied
#' through the same validated override [set_type()] uses, so the result is a
#' fully re-validated `artoo_spec`, never a hand-edited internal.
#'
#' @param spec *The specification to repair.* `<artoo_spec>: required`.
#' @param findings *A findings data frame.* `<data.frame>: required`. The
#'   result of [check_spec()] or [check_study()]; must carry the `check`,
#'   `dataset`, and `variable` columns.
#'
#' @return *A new `<artoo_spec>`* with the flagged variables retyped to
#'   `"float"`, or `spec` unchanged when there is nothing to repair. The input
#'   is never mutated.
#'
#' @examples
#' # ---- Example 1: auto-repair an integer/fractional mismatch ----
#' #
#' # adam_spec types ADSL.AGE as integer. Give it fractional ages and
#' # check_spec() raises an integer_fraction error; repair_spec() flips AGE
#' # (and only AGE) to float, and the corrected spec then applies cleanly.
#' dat <- cdisc_adsl
#' dat$AGE <- dat$AGE + 0.5
#' findings <- check_spec(dat, adam_spec, "ADSL")
#' fixed <- repair_spec(adam_spec, findings)
#' spec_variables(fixed, "ADSL")$data_type[
#'   spec_variables(fixed, "ADSL")$variable == "AGE"
#' ]
#'
#' # ---- Example 2: nothing to repair is a no-op ----
#' #
#' # The bundled data conforms, so its findings carry no integer_fraction or
#' # integer_overflow rows and the spec is returned unchanged.
#' clean <- check_spec(cdisc_adsl, adam_spec, "ADSL")
#' identical(repair_spec(adam_spec, clean), adam_spec)
#'
#' @seealso
#' **Primitive:** [set_type()] to retype a chosen variable directly.
#'
#' **Findings:** [check_spec()] for one dataset, [check_study()] across a
#' study. **Persist:** [write_spec()].
#' @export
repair_spec <- function(spec, findings) {
  call <- rlang::caller_env()
  .check_spec_arg(spec, call = call)

  need <- c("check", "dataset", "variable")
  if (!is.data.frame(findings) || !all(need %in% names(findings))) {
    .artoo_abort(
      c(
        "{.arg findings} must be a findings data frame.",
        "x" = if (!is.data.frame(findings)) {
          "You supplied {.obj_type_friendly {findings}}."
        } else {
          "It is missing column{?s}: {.val {setdiff(need, names(findings))}}."
        },
        "i" = "Pass the result of {.fn check_spec} or {.fn check_study}."
      ),
      kind = "input",
      call = call
    )
  }

  repairable <- c("integer_fraction", "integer_overflow")
  hit <- !is.na(findings$check) &
    findings$check %in% repairable &
    !is.na(findings$dataset) &
    !is.na(findings$variable)
  pairs <- unique(findings[hit, c("dataset", "variable"), drop = FALSE])
  if (!nrow(pairs)) {
    .artoo_inform(
      c(
        "No {.val integer_fraction} or {.val integer_overflow} findings to repair.",
        "i" = "The spec is returned unchanged."
      ),
      kind = "spec"
    )
    return(spec)
  }

  # One set_type() per dataset (each re-validates); float is the loss-free
  # fix for an integer dataType the data does not satisfy.
  for (ds in unique(pairs$dataset)) {
    vars <- unique(pairs$variable[pairs$dataset == ds])
    types <- stats::setNames(as.list(rep("float", length(vars))), vars)
    spec <- do.call(set_type, c(list(spec, ds), types))
  }
  spec
}
