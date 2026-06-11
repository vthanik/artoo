# checks.R -- artoo_checks(), the conformance-dimension control.
#
# A small validated record toggling which dimensions check_spec() (and
# therefore apply_spec(check=)) evaluates. One object can be built per study
# SAP and threaded through every apply_spec()/check_spec() call. A bad toggle
# name or type errors early (artoo_error_input), rather than being silently
# swallowed the way a loose `...` would.

# The conformance dimensions check_spec() can emit, in report order.
.artoo_check_dims <- c(
  "missing_variable",
  "missing_permissible",
  "extra_variable",
  "type_mismatch",
  "length_overflow",
  "char_length_limit",
  "codelist_membership",
  "codelist_membership_extensible",
  "label_match",
  "key_uniqueness",
  "display_format",
  "variable_name",
  "dataset_name",
  "label_length",
  "integer_overflow",
  "integer_fraction",
  "iso8601_format"
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
#' @param codelist_membership *Flag values outside their closed codelist.*
#'   `<logical(1)>: default TRUE`.
#' @param codelist_membership_extensible *Flag values outside an extensible
#'   codelist's enumerated terms.* `<logical(1)>: default TRUE`. A codelist
#'   whose `extended` flag is `TRUE` allows sponsor terms, so a non-member is
#'   a note, never an error; this toggle silences those notes independently
#'   of `codelist_membership`.
#' @param label_match *Flag a column whose label attribute differs from the
#'   spec label.* `<logical(1)>: default TRUE`.
#' @param key_uniqueness *Flag a dataset whose spec key variables do not
#'   uniquely identify its rows.* `<logical(1)>: default TRUE`.
#' @param display_format *Flag a date/datetime/time variable whose
#'   displayFormat is not a recognized SAS format of that family.*
#'   `<logical(1)>: default TRUE`.
#' @param variable_name *Flag a data column name that violates the XPORT
#'   naming rules.* `<logical(1)>: default TRUE`. Over 8 characters (the v5
#'   limit), over 32 (the v8 limit), or containing anything but ASCII
#'   letters, digits, and underscore.
#' @param dataset_name *Flag a dataset name that violates the XPORT naming
#'   rules.* `<logical(1)>: default TRUE`. Same limits as `variable_name`.
#' @param label_length *Flag a column label attribute over the 40-byte XPORT
#'   v5 / FDA limit.* `<logical(1)>: default TRUE`.
#' @param integer_overflow *Flag an integer-typed variable holding values
#'   beyond R's 32-bit integer range.* `<logical(1)>: default TRUE`. Such
#'   values become `NA` under coercion, so this is an error, not a warning.
#' @param integer_fraction *Flag an integer-typed variable holding fractional
#'   values.* `<logical(1)>: default TRUE`. Coercion would truncate them
#'   (162.6 becomes 162) -- a data-integrity event; fix the spec dataType
#'   (`float` / `decimal`) or the data before conforming.
#' @param iso8601_format *Flag a character date/datetime/time variable whose
#'   values are not valid ISO 8601 text.* `<logical(1)>: default TRUE`. A
#'   character column under a temporal dataType is the CDISC `--DTC` form;
#'   complete values, right-truncated partials (`"1951"`, `"1951-12"`), and
#'   SDTMIG hyphen placeholders (`"2003---15"`) all pass, while
#'   `"12NOV2019"` or an impossible calendar date is flagged.
#'
#' @return *A `<artoo_checks>` control object*. Pass it as the `checks`
#'   argument to [check_spec()] or [apply_spec()].
#'
#' @examples
#' # ---- Example 1: the default runs every conformance dimension ----
#' #
#' # With no arguments, every conformance dimension is enabled.
#' artoo_checks()
#'
#' # ---- Example 2: silence one dimension for a whole study ----
#' #
#' # Turn off the length check (e.g. while a spec's lengths are provisional)
#' # and reuse the control across every dataset.
#' spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' ck <- artoo_checks(length_overflow = FALSE)
#' nrow(check_spec(cdisc_dm, spec, "DM", checks = ck))
#'
#' @seealso [check_spec()] and [apply_spec()] which consume it.
#' @export
artoo_checks <- function(
  missing_variable = TRUE,
  missing_permissible = TRUE,
  extra_variable = TRUE,
  type_mismatch = TRUE,
  length_overflow = TRUE,
  char_length_limit = TRUE,
  codelist_membership = TRUE,
  codelist_membership_extensible = TRUE,
  label_match = TRUE,
  key_uniqueness = TRUE,
  display_format = TRUE,
  variable_name = TRUE,
  dataset_name = TRUE,
  label_length = TRUE,
  integer_overflow = TRUE,
  integer_fraction = TRUE,
  iso8601_format = TRUE
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
    codelist_membership_extensible = codelist_membership_extensible,
    label_match = label_match,
    key_uniqueness = key_uniqueness,
    display_format = display_format,
    variable_name = variable_name,
    dataset_name = dataset_name,
    label_length = label_length,
    integer_overflow = integer_overflow,
    integer_fraction = integer_fraction,
    iso8601_format = iso8601_format
  )
  for (nm in names(toggles)) {
    v <- toggles[[nm]]
    if (!is.logical(v) || length(v) != 1L || is.na(v)) {
      .artoo_abort(
        c(
          "{.arg {nm}} must be a single TRUE or FALSE.",
          "x" = "You supplied {.obj_type_friendly {v}}."
        ),
        kind = "input",
        call = call
      )
    }
  }
  structure(toggles, class = "artoo_checks")
}

#' Test for a artoo_checks control
#'
#' Report whether an object is a `artoo_checks` control built by
#' [artoo_checks()]. Use it to guard a `checks` argument before threading it
#' into [check_spec()] or [apply_spec()].
#'
#' @param x *Object to test.* `<any>`.
#'
#' @return *A `<logical(1)>`*: `TRUE` when `x` is a `artoo_checks`.
#'
#' @examples
#' # ---- Example 1: confirm a control before reusing it ----
#' #
#' # is_artoo_checks() distinguishes a real control from a bare list of flags.
#' is_artoo_checks(artoo_checks())
#' is_artoo_checks(list(missing_variable = TRUE))
#'
#' @seealso [artoo_checks()] to build one.
#' @export
is_artoo_checks <- function(x) {
  inherits(x, "artoo_checks")
}

#' @export
print.artoo_checks <- function(x, ...) {
  cat("<artoo_checks>\n")
  for (d in .artoo_check_dims) {
    cat(sprintf("  [%s] %s\n", if (x[[d]]) "x" else " ", d))
  }
  invisible(x)
}

# Validate a `checks` argument, accepting the default sentinel NULL.
#' @noRd
.check_checks_arg <- function(checks, call = rlang::caller_env()) {
  if (is.null(checks)) {
    return(artoo_checks())
  }
  if (!is_artoo_checks(checks)) {
    .artoo_abort(
      c(
        "{.arg checks} must be a {.cls artoo_checks} control or NULL.",
        "x" = "You supplied {.obj_type_friendly {checks}}.",
        "i" = "Build one with {.fn artoo_checks}."
      ),
      kind = "input",
      call = call
    )
  }
  checks
}
