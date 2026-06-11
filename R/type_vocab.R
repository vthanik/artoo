# type_vocab.R -- the single source of truth for variable types.
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
  # "incomplete*" dataType -- a partial date IS dataType "date" with a
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
    cli::cli_abort(
      c(
        "Missing variable type{where}.",
        "x" = "A type is required and must be a non-empty string."
      ),
      class = "artoo_error_type",
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
  cli::cli_abort(
    c(
      "Unknown variable type {.val {raw}}{where}.",
      "x" = "artoo maps types to the closed CDISC set: {.val {types}}.",
      "i" = "Edit the spec's {.field type} column, or file an issue if {.val {raw}} is a standard token."
    ),
    class = "artoo_error_type",
    call = call
  )
}

# R storage mode used to hold a column of a given CDISC dataType. Dates,
# datetimes, and times are held as numeric (SAS-style; the displayFormat
# carries the SAS format) -- the codec layer realises the ISO-string vs
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

#' A typed NA vector for a CDISC dataType
#' @noRd
.na_for_type <- function(data_type, n = 0L) {
  .na_mode(.type_storage(data_type), n)
}

#' Coerce a vector to the storage of a CDISC dataType
#'
#' Returns a list with `value` (the coerced vector), `n_na_introduced`
#' (count of values that became NA but were not NA before), and `n_lossy`
#' (count of fractional values truncated by an integer coercion) so callers
#' can warn on lossy coercion.
#' @noRd
.coerce_to_type <- function(x, data_type) {
  mode <- .type_storage(data_type)
  before_na <- is.na(x)
  value <- .coerce_mode(x, mode)
  after_na <- is.na(value)
  n_lossy <- 0L
  if (mode == "integer") {
    xn <- suppressWarnings(as.numeric(x))
    n_lossy <- sum(!is.na(xn) & !after_na & xn != as.numeric(value))
  }
  list(
    value = value,
    n_na_introduced = sum(after_na & !before_na),
    n_lossy = n_lossy
  )
}
