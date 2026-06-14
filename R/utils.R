# utils.R — small base-R helpers shared across the package.
# `%||%` is imported from rlang (see artoo-package.R); do not redefine.

# Condition family helpers — every condition artoo raises flows through one
# of these, so each carries a three-level class chain and is catchable at any
# altitude: the specific kind ("artoo_error_input"), the severity
# ("artoo_error" / "artoo_warning" / "artoo_message"), and the package root
# ("artoo_condition"). `.envir` is threaded through so glue interpolation in
# the message resolves in the RAISING function's frame, not the helper's.
#' @noRd
.artoo_abort <- function(
  message,
  kind,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  cli::cli_abort(
    message,
    class = c(paste0("artoo_error_", kind), "artoo_error", "artoo_condition"),
    ...,
    call = call,
    .envir = .envir
  )
}

#' @noRd
.artoo_warn <- function(
  message,
  kind,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  cli::cli_warn(
    message,
    class = c(
      paste0("artoo_warning_", kind),
      "artoo_warning",
      "artoo_condition"
    ),
    ...,
    call = call,
    .envir = .envir
  )
}

#' @noRd
.artoo_inform <- function(message, kind, ..., .envir = parent.frame()) {
  cli::cli_inform(
    message,
    class = c(
      paste0("artoo_message_", kind),
      "artoo_message",
      "artoo_condition"
    ),
    ...,
    .envir = .envir
  )
}

# Coerce a vector to a target storage mode, preserving NA. Returns the bare
# coerced vector; lossy-coercion accounting (NA introduction, fractional
# truncation) lives in .coerce_to_type().
#' @noRd
.coerce_mode <- function(x, mode) {
  # A factor coerces through its LABELS, never its integer level codes:
  # as.integer(factor("10")) is the code (1L), not the value (10L). Convert
  # to labels first so every mode sees the data the user authored. The
  # boolean and string paths were already safe; integer/double were not.
  if (is.factor(x)) {
    x <- as.character(x)
  }
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
# offending input), so it may not be valid UTF-8 — and cli's own message
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

# Format a double vector as the shortest decimal string that parses back to
# the IDENTICAL double (round-trip exact). This is how artoo holds a `decimal`
# dataType in memory and writes it to JSON: a plain as.character() uses R's
# 15-digit default and drops the last ulp (0.1 + 0.2 came back 0.3), the exact
# loss the JSON number formatter avoids with digits = 17. 15 digits keep clean
# values clean; the rare value that needs more falls through to 17 (17 decimal
# digits uniquely identify any IEEE double). Character and NA pass through
# unchanged, so a decimal already carried as an exact string is never reformatted.
#' @noRd
.double_to_string <- function(x) {
  if (is.character(x)) {
    return(x)
  }
  x <- as.double(x)
  out <- rep(NA_character_, length(x))
  # is.finite() also screens NaN/Inf to NA, so a non-finite value never
  # formats to the literal "Inf"/"NaN"; for a `decimal` that NA is then caught
  # by the conform coercion-loss gate.
  ok <- is.finite(x)
  if (!any(ok)) {
    return(out)
  }
  v <- x[ok]
  s <- formatC(v, format = "g", digits = 15L, width = -1L)
  need <- as.double(s) != v
  if (any(need)) {
    s[need] <- formatC(v[need], format = "g", digits = 17L, width = -1L)
  }
  out[ok] <- s
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
      .artoo_abort(
        c(
          "Could not move the temporary file into place.",
          "x" = "Failed to write {.path {path}}."
        ),
        kind = "codec",
        call = call
      )
    }
    unlink(tmp)
  }
  invisible(path)
}

# Write to `path` atomically. `write_fn` receives the sibling temp path and
# does the writing (a connection-based codec opens and on.exit-closes its own
# connection inside write_fn). On any error the temp file is removed and the
# prior good file is left untouched (the error propagates, skipping the move);
# on success the temp file is renamed over the target. One home for the
# tempfile + cleanup + rename dance the four codecs used to each repeat.
#' @noRd
.with_atomic_write <- function(
  path,
  fileext,
  write_fn,
  call = rlang::caller_env()
) {
  tmp <- tempfile(tmpdir = dirname(path), fileext = fileext)
  ok <- FALSE
  tryCatch(
    {
      write_fn(tmp)
      ok <- TRUE
    },
    finally = if (!ok && file.exists(tmp)) {
      unlink(tmp)
    }
  )
  .move_into_place(tmp, path, call)
  invisible(path)
}

# Validate that `path` is a single, non-NA, non-empty string.
#' @noRd
.check_path <- function(path, call = rlang::caller_env()) {
  if (
    !is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)
  ) {
    .artoo_abort(
      c(
        "{.arg path} must be a single non-empty string.",
        "x" = "You supplied {.obj_type_friendly {path}}."
      ),
      kind = "input",
      call = call
    )
  }
  path
}
