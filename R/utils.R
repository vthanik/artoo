# utils.R -- small base-R helpers shared across the package.
# `%||%` is imported from rlang (see vport-package.R); do not redefine.

# Coerce a vector to a target storage mode, preserving NA. Returns the
# coerced vector, or signals via `ok = FALSE` when coercion would change
# values (so callers can warn/abort).
#' @noRd
.coerce_mode <- function(x, mode) {
  switch(
    mode,
    character = as.character(x),
    integer = {
      out <- suppressWarnings(as.integer(x))
      out
    },
    numeric = ,
    double = suppressWarnings(as.numeric(x)),
    logical = .as_logical(x),
    x
  )
}

# Tolerant logical coercion: accepts TRUE/FALSE, "Y"/"N", "Yes"/"No",
# "T"/"F", 1/0. NA stays NA.
#' @noRd
.as_logical <- function(x) {
  if (is.logical(x)) {
    return(x)
  }
  if (is.numeric(x)) {
    return(x != 0)
  }
  ch <- toupper(trimws(as.character(x)))
  out <- rep(NA, length(ch))
  out[ch %in% c("TRUE", "T", "Y", "YES", "1")] <- TRUE
  out[ch %in% c("FALSE", "F", "N", "NO", "0")] <- FALSE
  out
}

# A typed NA of the given storage mode, length `n`.
#' @noRd
.na_mode <- function(mode, n = 0L) {
  switch(
    mode,
    character = rep(NA_character_, n),
    integer = rep(NA_integer_, n),
    numeric = ,
    double = rep(NA_real_, n),
    logical = rep(NA, n),
    rep(NA, n)
  )
}

# Validate that `path` is a single, non-NA, non-empty string.
#' @noRd
.check_path <- function(path, call = rlang::caller_env()) {
  if (
    !is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)
  ) {
    cli::cli_abort(
      c(
        "{.arg path} must be a single non-empty string.",
        "x" = "You supplied {.obj_type_friendly {path}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  path
}
