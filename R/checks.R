# checks.R -- vport_checks(), the conformance-dimension control.
#
# A small validated record toggling which dimensions check_spec() (and
# therefore apply_spec(check=)) evaluates. One object can be built per study
# SAP and threaded through every apply_spec()/check_spec() call. A bad toggle
# name or type errors early (vport_error_input), rather than being silently
# swallowed the way a loose `...` would.

# The conformance dimensions check_spec() can emit, in report order.
.vport_check_dims <- c(
  "missing_variable",
  "missing_permissible",
  "extra_variable",
  "type_mismatch",
  "length_overflow",
  "char_length_limit",
  "codelist_membership",
  "label_match",
  "key_uniqueness",
  "display_format"
)

#' Control which conformance checks run
#'
#' Build a reusable control that selects which dimensions [check_spec()]
#' evaluates, and therefore which findings [apply_spec()] produces. Construct
#' one per study and thread it through every conform call so the conformance
#' surface is consistent. Each toggle is validated at construction, so a
#' mistyped name or value aborts early rather than being silently ignored.
#'
#' @details
#' **Selection, not severity.** This control decides which findings are
#' *produced*; [apply_spec()]'s `check` argument (warn, strict, off) decides
#' what to *do* with them. A disabled dimension is skipped entirely, so the
#' findings frame stays clean.
#'
#' @param missing_variable *Flag mandatory spec variables absent from the
#'   data.* `<logical(1)>: default TRUE`.
#' @param missing_permissible *Flag permissible (non-mandatory) spec variables
#'   absent from the data.* `<logical(1)>: default TRUE`.
#' @param extra_variable *Flag data columns the spec does not declare.*
#'   `<logical(1)>: default TRUE`.
#' @param type_mismatch *Flag columns whose storage differs from the spec
#'   dataType.* `<logical(1)>: default TRUE`.
#' @param length_overflow *Flag character values longer than the spec length.*
#'   `<logical(1)>: default TRUE`.
#' @param char_length_limit *Flag character values longer than the SAS XPORT
#'   v5 / FDA 200-byte limit.* `<logical(1)>: default TRUE`.
#' @param codelist_membership *Flag values outside their codelist.*
#'   `<logical(1)>: default TRUE`.
#' @param label_match *Flag a column whose label attribute differs from the
#'   spec label.* `<logical(1)>: default TRUE`.
#' @param key_uniqueness *Flag a dataset whose spec key variables do not
#'   uniquely identify its rows.* `<logical(1)>: default TRUE`.
#' @param display_format *Flag a date/datetime/time variable whose
#'   displayFormat is not a recognized SAS format of that family.*
#'   `<logical(1)>: default TRUE`.
#'
#' @return *A `<vport_checks>` control object*. Pass it as the `checks`
#'   argument to [check_spec()] or [apply_spec()].
#'
#' @examples
#' # ---- Example 1: the default runs every conformance dimension ----
#' #
#' # With no arguments, every conformance dimension is enabled.
#' vport_checks()
#'
#' # ---- Example 2: silence one dimension for a whole study ----
#' #
#' # Turn off the length check (e.g. while a spec's lengths are provisional)
#' # and reuse the control across every dataset.
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' ck <- vport_checks(length_overflow = FALSE)
#' nrow(check_spec(cdisc_dm, spec, "DM", checks = ck))
#'
#' @seealso [check_spec()] and [apply_spec()] which consume it.
#' @export
vport_checks <- function(
  missing_variable = TRUE,
  missing_permissible = TRUE,
  extra_variable = TRUE,
  type_mismatch = TRUE,
  length_overflow = TRUE,
  char_length_limit = TRUE,
  codelist_membership = TRUE,
  label_match = TRUE,
  key_uniqueness = TRUE,
  display_format = TRUE
) {
  call <- rlang::caller_env()
  toggles <- list(
    missing_variable = missing_variable,
    missing_permissible = missing_permissible,
    extra_variable = extra_variable,
    type_mismatch = type_mismatch,
    length_overflow = length_overflow,
    char_length_limit = char_length_limit,
    codelist_membership = codelist_membership,
    label_match = label_match,
    key_uniqueness = key_uniqueness,
    display_format = display_format
  )
  for (nm in names(toggles)) {
    v <- toggles[[nm]]
    if (!is.logical(v) || length(v) != 1L || is.na(v)) {
      cli::cli_abort(
        c(
          "{.arg {nm}} must be a single TRUE or FALSE.",
          "x" = "You supplied {.obj_type_friendly {v}}."
        ),
        class = "vport_error_input",
        call = call
      )
    }
  }
  structure(toggles, class = "vport_checks")
}

#' Test for a vport_checks control
#'
#' Report whether an object is a `vport_checks` control built by
#' [vport_checks()]. Use it to guard a `checks` argument before threading it
#' into [check_spec()] or [apply_spec()].
#'
#' @param x *Object to test.* `<any>`.
#'
#' @return *A `<logical(1)>`*: `TRUE` when `x` is a `vport_checks`.
#'
#' @examples
#' # ---- Example 1: confirm a control before reusing it ----
#' #
#' # is_vport_checks() distinguishes a real control from a bare list of flags.
#' is_vport_checks(vport_checks())
#' is_vport_checks(list(missing_variable = TRUE))
#'
#' @seealso [vport_checks()] to build one.
#' @export
is_vport_checks <- function(x) {
  inherits(x, "vport_checks")
}

#' @export
print.vport_checks <- function(x, ...) {
  cat("<vport_checks>\n")
  for (d in .vport_check_dims) {
    cat(sprintf("  [%s] %s\n", if (x[[d]]) "x" else " ", d))
  }
  invisible(x)
}

# Validate a `checks` argument, accepting the default sentinel NULL.
#' @noRd
.check_checks_arg <- function(checks, call = rlang::caller_env()) {
  if (is.null(checks)) {
    return(vport_checks())
  }
  if (!is_vport_checks(checks)) {
    cli::cli_abort(
      c(
        "{.arg checks} must be a {.cls vport_checks} control or NULL.",
        "x" = "You supplied {.obj_type_friendly {checks}}.",
        "i" = "Build one with {.fn vport_checks}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  checks
}
