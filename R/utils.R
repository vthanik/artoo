# utils.R -- small base-R helpers shared across the package.
# `%||%` is imported from rlang (see artoo-package.R); do not redefine.

# Coerce a vector to a target storage mode, preserving NA. Returns the bare
# coerced vector; lossy-coercion accounting (NA introduction, fractional
# truncation) lives in .coerce_to_type().
#' @noRd
.coerce_mode <- function(x, mode) {
  switch(
    mode,
    character = as.character(x),
    integer = suppressWarnings(as.integer(x)),
    numeric = ,
    double = suppressWarnings(as.numeric(x)),
    logical = .as_logical(x),
    x
  )
}

# Escape cli/glue interpolation braces in data-derived text (data values,
# finding messages) so a literal "{" renders as-is instead of being parsed
# as an inline-markup format string.
#' @noRd
.cli_escape <- function(x) {
  gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
}

# A foreign error's message can quote raw file bytes (jsonlite echoes the
# offending input), so it may not be valid UTF-8 -- and cli's own message
# rendering would then error INSIDE the abort handler, leaking an unclassed
# condition. Substitute invalid bytes (<hh> escapes) so the message is
# always safe to interpolate.
#' @noRd
.safe_msg <- function(e) {
  msg <- conditionMessage(e)
  out <- iconv(msg, "UTF-8", "UTF-8", sub = "byte")
  ifelse(is.na(out), "(unprintable message)", out)
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

# Thin wrapper over base file.rename so the move-into-place fallback below is
# unit-testable: tests mock this artoo-namespace binding (base functions
# called unqualified cannot be mocked by testthat).
#' @noRd
.rename_file <- function(from, to) {
  file.rename(from, to)
}

# Move a freshly written temp file into its final place. A same-directory
# rename is atomic, so a crash mid-write never corrupts a prior good file; the
# copy path is a fallback for the rare filesystem that refuses the rename. A
# failed copy aborts (never leaves the caller thinking it wrote a file).
# Codecs build in `tempfile(tmpdir = dirname(path))` then call this.
#' @noRd
.move_into_place <- function(tmp, path, call = rlang::caller_env()) {
  if (!.rename_file(tmp, path)) {
    if (!file.copy(tmp, path, overwrite = TRUE)) {
      unlink(tmp)
      cli::cli_abort(
        c(
          "Could not move the temporary file into place.",
          "x" = "Failed to write {.path {path}}."
        ),
        class = "artoo_error_codec",
        call = call
      )
    }
    unlink(tmp)
  }
  invisible(path)
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
      class = "artoo_error_input",
      call = call
    )
  }
  path
}
