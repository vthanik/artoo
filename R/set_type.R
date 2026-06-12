# set_type.R — set_type(), the declarative spec dataType override.
#
# The in-R way to correct a spec's variable dataType when the data
# disagrees with it, so a user never has to reach into the S7 object with
# set_props(). Pairs with repair_spec() (auto-apply from findings) and the
# apply_spec() coercion gate.

#' Override a variable's dataType in a spec
#'
#' Return a new `artoo_spec` with one or more variables retyped. This is the
#' supported, in-R way to correct a spec when the data disagrees with its
#' declared `dataType` (e.g. a variable typed `integer` whose extract holds
#' fractional values): fix it here rather than editing the source workbook,
#' then drive [apply_spec()] with the corrected spec. The spec is immutable,
#' so the original is never changed.
#'
#' @details
#' **Per-dataset scope.** A type is set only on the named `dataset`'s row.
#' A variable that appears in several datasets keeps its other rows' types;
#' call `set_type()` once per dataset to change them all. Spec-wide
#' consequences (a variable typed inconsistently across datasets) are a
#' [validate_spec()] concern, not a construction error here.
#'
#' **Canonicalised, then validated.** Each supplied type is mapped through
#' the closed CDISC `dataType` vocabulary, so `"Float"`, `"decimal"`, and
#' `"text"` all resolve; an unrecognised token aborts with
#' `artoo_error_type`. The rebuilt spec is re-validated, so an override that
#' would break the spec aborts with `artoo_error_spec`.
#'
#' @param spec *The specification to amend.* `<artoo_spec>: required`.
#' @param dataset *The dataset whose variables to retype.* `<character(1)>:
#'   required`. Must name a dataset in `spec`.
#' @param ... *Named `variable = type` pairs.* Each name is a variable in
#'   `dataset`; each value is a CDISC `dataType` (`"string"`, `"integer"`,
#'   `"decimal"`, `"float"`, `"double"`, `"boolean"`, `"date"`, `"datetime"`,
#'   `"time"`, `"URI"`) or a recognised spelling of one. At least one pair is
#'   required and every argument must be named.
#'
#'   **Tip:** to undo an `integer` dataType that the data does not satisfy,
#'   set `"float"` (IEEE double) or `"decimal"` (exact, exchanged as text).
#'
#' @return *A new `<artoo_spec>`* with the named variables retyped, ready for
#'   [apply_spec()] or [write_spec()]. The input `spec` is unchanged.
#'
#' @examples
#' # ---- Example 1: retype one variable the data disagrees with ----
#' #
#' # The bundled adam_spec types ADSL.AGE as integer. If an extract stored it
#' # with fractional values, retype it to float so apply_spec() coerces
#' # without loss. set_type() returns a new spec; the original is untouched.
#' fixed <- set_type(adam_spec, "ADSL", AGE = "float")
#' v <- spec_variables(fixed, "ADSL")
#' v[v$variable == "AGE", c("variable", "data_type")]
#'
#' # ---- Example 2: retype several at once, original left intact ----
#' #
#' # Pass any number of variable = type pairs; canonical dataTypes and common
#' # spellings both resolve. The source spec is immutable, so adam_spec still
#' # reports AGE as its original type.
#' patched <- set_type(adam_spec, "ADSL", AGE = "decimal", TRTSDT = "date")
#' spec_variables(adam_spec, "ADSL")$data_type[
#'   spec_variables(adam_spec, "ADSL")$variable == "AGE"
#' ]
#'
#' @seealso
#' **Auto-repair:** [repair_spec()] to apply every `integer_fraction` /
#' `integer_overflow` fix from a findings frame at once.
#'
#' **Workflow:** [apply_spec()] to conform with the corrected spec;
#' [write_spec()] to persist it; [check_spec()] to find the mismatches.
#' @export
set_type <- function(spec, dataset, ...) {
  call <- rlang::caller_env()
  .check_spec_arg(spec, call = call)
  .check_dataset_arg(spec, dataset, call = call)

  dots <- list(...)
  nms <- names(dots)
  if (!length(dots)) {
    .artoo_abort(
      c(
        "{.fn set_type} needs at least one {.code variable = type} pair.",
        "i" = "For example {.code set_type(spec, \"ADSL\", AGE = \"float\")}."
      ),
      kind = "input",
      call = call
    )
  }
  if (is.null(nms) || any(!nzchar(nms))) {
    unnamed <- if (is.null(nms)) seq_along(dots) else which(!nzchar(nms))
    .artoo_abort(
      c(
        "Every type override must be a named {.code variable = type} pair.",
        "x" = "{cli::qty(unnamed)} Argument{?s} in position {.val {unnamed}} {?is/are} unnamed.",
        "i" = "For example {.code set_type(spec, \"ADSL\", AGE = \"float\")}."
      ),
      kind = "input",
      call = call
    )
  }

  known <- spec_variables(spec, dataset)$variable
  unknown <- setdiff(nms, known)
  if (length(unknown)) {
    .artoo_abort(
      c(
        "{cli::qty(unknown)} Variable{?s} {.val {unknown}} {?is/are} not in dataset {.val {dataset}}.",
        "i" = "Variables in {.val {dataset}}: {.val {known}}."
      ),
      kind = "input",
      call = call
    )
  }

  # Canonicalise each requested type through the one type vocabulary (so
  # "Float"/"decimal"/"text" resolve and an unknown token aborts the friendly
  # way), then set it on the matching (dataset, variable) row and re-validate
  # via set_props. set_props re-runs the S7 validator, which re-checks the
  # data_type vocabulary as a last line of defence.
  v <- spec@variables
  for (nm in nms) {
    dt <- .parse_type(dots[[nm]], variable = nm, call = call)
    rows <- !is.na(v$dataset) &
      v$dataset == dataset &
      !is.na(v$variable) &
      v$variable == nm
    v$data_type[rows] <- dt
  }
  S7::set_props(spec, variables = v)
}
