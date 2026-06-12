# type_vocab.R — the single source of truth for variable types.
#
# Maps any spec/SAS type token to the closed CDISC Dataset-JSON v1.1
# `dataType` vocabulary (`.cdisc_datatypes`), and from a `dataType` to the
# R storage mode artoo uses to hold and coerce that column. Every codec
# and apply step routes type questions through here.

# Aliases -> canonical CDISC dataType. Keys are lowercased; values are
# members of `.cdisc_datatypes`.
.type_aliases <- c(
  text = "string",
  char = "string",
  character = "string",
  string = "string",
  `$` = "string",
  int = "integer",
  integer = "integer",
  decimal = "decimal",
  float = "float",
  num = "float",
  numeric = "float",
  real = "float",
  double = "double",
  bool = "boolean",
  logical = "boolean",
  boolean = "boolean",
  date = "date",
  datetime = "datetime",
  time = "time",
  # Define-XML date subtypes. Dataset-JSON v1.1 has no "partial*" /
  # "incomplete*" dataType — a partial date IS dataType "date" with a
  # partial ISO value (the partialness lives in the value/displayFormat).
  # ISO 8601 duration / interval have no dedicated dataType -> string.
  partialdate = "date",
  partialtime = "time",
  partialdatetime = "datetime",
  incompletedate = "date",
  incompletetime = "time",
  incompletedatetime = "datetime",
  durationdatetime = "string",
  intervaldatetime = "string",
  uri = "URI",
  url = "URI"
)

#' Canonicalize a raw type token to a CDISC dataType
#'
#' @param raw A length-1 character type token (e.g. `"text"`, `"integer (8)"`,
#'   `"Char"`, `"float"`). Length-in-parens and surrounding whitespace are
#'   stripped before lookup.
#' @param variable Optional variable name, for a friendlier error.
#' @return One of `.cdisc_datatypes`.
#' @noRd
.parse_type <- function(raw, variable = NULL, call = rlang::caller_env()) {
  where <- if (!is.null(variable)) paste0(" for ", variable) else ""
  if (length(raw) != 1L || is.na(raw) || !nzchar(trimws(raw))) {
    .artoo_abort(
      c(
        "Missing variable type{where}.",
        "x" = "A type is required and must be a non-empty string."
      ),
      kind = "type",
      call = call
    )
  }
  # Strip a trailing length in parens, e.g. "integer (8)" -> "integer".
  key <- tolower(trimws(sub("\\s*\\(.*\\)\\s*$", "", raw)))
  # Accept an already-canonical value (case-insensitive; URI is uppercase).
  canon_lower <- tolower(.cdisc_datatypes)
  if (key %in% canon_lower) {
    return(.cdisc_datatypes[match(key, canon_lower)])
  }
  hit <- .type_aliases[key]
  if (!is.na(hit)) {
    return(unname(hit))
  }
  types <- .cdisc_datatypes
  .artoo_abort(
    c(
      "Unknown variable type {.val {raw}}{where}.",
      "x" = "artoo maps types to the closed CDISC set: {.val {types}}.",
      "i" = "Edit the spec's {.field type} column, or file an issue if {.val {raw}} is a standard token."
    ),
    kind = "type",
    call = call
  )
}

# Canonical CDISC dataType -> the Define-XML / ODM DataType vocabulary that a
# Pinnacle 21 workbook (and a future Define-XML writer) expects on the write
# side. This is the inverse of .parse_type for the WRITE direction. The map is
# deliberately NOT injective: ODM has no "string"/"decimal"/"double" spelling,
# so a character variable becomes "text" and an exact/IEEE numeric becomes
# "float". That collapse is acceptable because the P21 xlsx is the interchange
# surface, not the lossless one (native JSON keeps the canonical spelling); a
# read folds "text" back to "string" and "float" to "float".
.define_datatypes <- c(
  string = "text",
  boolean = "text",
  URI = "text",
  decimal = "float",
  double = "float",
  integer = "integer",
  float = "float",
  date = "date",
  datetime = "datetime",
  time = "time"
)

#' Encode a canonical CDISC dataType in the Define-XML / ODM vocabulary
#'
#' Vectorized. An NA, or a value already in the Define vocabulary, passes
#' through verbatim (every canonical artoo dataType is a key, so in practice
#' only NA falls through).
#' @noRd
.to_define_datatype <- function(x) {
  hit <- .define_datatypes[as.character(x)]
  # ifelse() inherits names from the condition, so unname the result.
  unname(ifelse(is.na(hit), as.character(x), hit))
}

# R storage mode used to hold a column of a given CDISC dataType. Dates,
# datetimes, and times are held as numeric (SAS-style; the displayFormat
# carries the SAS format) — the codec layer realises the ISO-string vs
# numeric storage per format.
#' @noRd
.type_storage <- function(data_type) {
  switch(
    data_type,
    string = "character",
    URI = "character",
    integer = "integer",
    decimal = "character", # exchanged as string to preserve exact precision
    float = "double",
    double = "double",
    boolean = "logical",
    date = "double",
    datetime = "double",
    time = "double",
    "character"
  )
}

#' Per-value lossy-integer predicates
#'
#' The single definition of "an integer dataType the data does not satisfy",
#' shared by `check_spec()` (the integer_fraction / integer_overflow rules),
#' the `apply_spec()` coercion gate, and `.coerce_to_type()`'s truncation
#' tally. `.is_integer_fractional()` flags finite values with a fractional
#' part; `.is_integer_overflowed()` flags values beyond R's 32-bit integer
#' range. Both read values through `as.numeric()`, so a factor must be
#' de-factored to its labels before they see it.
#' @noRd
.is_integer_fractional <- function(x) {
  nv <- suppressWarnings(as.numeric(x))
  !is.na(nv) & is.finite(nv) & nv != trunc(nv)
}

#' @noRd
.is_integer_overflowed <- function(x) {
  nv <- suppressWarnings(as.numeric(x))
  !is.na(nv) & abs(nv) > .Machine$integer.max
}

#' Coerce a vector to the storage of a CDISC dataType
#'
#' Returns a list with `value` (the coerced vector), `n_na_introduced`
#' (count of values that became NA but were not NA before), and `n_lossy`
#' (count of fractional values truncated by an integer coercion) so callers
#' can warn on lossy coercion.
#' @noRd
.coerce_to_type <- function(x, data_type) {
  # Factor through labels, not level codes (see .coerce_mode); this also
  # makes the lossy check below compare authored values, not codes -- without
  # it, as.numeric(<factor>) and as.numeric(value) are the same codes and the
  # guard silently agrees with itself.
  if (is.factor(x)) {
    x <- as.character(x)
  }
  mode <- .type_storage(data_type)
  before_na <- is.na(x)
  value <- .coerce_mode(x, mode)
  after_na <- is.na(value)
  n_lossy <- 0L
  if (mode == "integer") {
    # The same "fractional" definition the integer_fraction check uses; the
    # !after_na guard keeps an overflow (already counted as an NA introduction)
    # out of the truncation tally.
    n_lossy <- sum(.is_integer_fractional(x) & !after_na)
  }
  list(
    value = value,
    n_na_introduced = sum(after_na & !before_na),
    n_lossy = n_lossy
  )
}
