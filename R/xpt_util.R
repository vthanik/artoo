# xpt_util.R -- byte-level helpers for the xpt codec.
#
# Ported from the herald archive (herald, not v0 -- diff confirmed it the
# strict superset). vport changes: drop the vctrs dependency (base coercion),
# dot-prefix internals, and `.sas_datetime_str()` takes an explicit `time` so
# writes are byte-stable (the codec injects a frozen `created=`, never an
# inline Sys.time()).

# Pad or truncate each string to exactly `width` chars (right-fill `fill`).
#' @noRd
.pad_to <- function(x, width, fill = " ") {
  x <- as.character(x)
  n <- nchar(x)
  ifelse(
    n > width,
    substr(x, 1L, width),
    paste0(x, strrep(fill, pmax(0L, width - n)))
  )
}

# Pad a raw vector up to the next multiple of `boundary` with ASCII spaces
# (XPORT records are blocked to 80 bytes).
#' @noRd
.pad_record <- function(raw_vec, boundary = 80L) {
  remainder <- length(raw_vec) %% boundary
  if (remainder == 0L) {
    return(raw_vec)
  }
  c(raw_vec, rep(as.raw(0x20), boundary - remainder))
}

# One string to a raw vector of exact `width`, right-padded with ASCII spaces.
#' @noRd
.str_to_raw <- function(x, width) {
  charToRaw(.pad_to(as.character(x), width))
}

# One string to a raw vector of exactly `width` BYTES, right-padded with ASCII
# spaces. Unlike .str_to_raw (which measures characters via .pad_to), this
# packs by byte so a multibyte (UTF-8 target) value fills a fixed-width OBS
# field correctly. charToRaw returns the stored bytes regardless of the
# Encoding mark, so a value transcoded by .to_target lands as its target
# bytes. The xpt OBS writer sizes `width` as the max byte length (F1), so
# truncation never fires on real data; the floor guard is defensive only.
#' @noRd
.str_to_raw_bytes <- function(x, width) {
  b <- charToRaw(x)
  n <- length(b)
  if (n >= width) {
    b[seq_len(width)]
  } else {
    c(b, rep(as.raw(0x20), width - n))
  }
}

# Integer <-> big-endian raw (S370FPIB), used for var counts / lengths / npos.
#' @noRd
.int_to_pib2 <- function(x) {
  writeBin(as.integer(x), raw(), size = 2L, endian = "big")
}
#' @noRd
.int_to_pib4 <- function(x) {
  writeBin(as.integer(x), raw(), size = 4L, endian = "big")
}
#' @noRd
.pib2_to_int <- function(raw2) {
  readBin(raw2, what = integer(), size = 2L, n = 1L, endian = "big")
}
#' @noRd
.pib4_to_int <- function(raw4) {
  readBin(raw4, what = integer(), size = 4L, n = 1L, endian = "big")
}

# Raw header bytes to a trimmed byte-passthrough string (drop NULs and
# trailing spaces). useBytes keeps the trim byte-level: label fields may hold
# any source-charset bytes (transcoded later, once the encoding is resolved),
# and a character-level regex would error on non-UTF-8 input.
#' @noRd
.raw_to_str <- function(raw_vec) {
  raw_vec <- raw_vec[raw_vec != as.raw(0x00)]
  if (length(raw_vec) == 0L) {
    return("")
  }
  sub(" +$", "", rawToChar(raw_vec), useBytes = TRUE)
}

# Vectorised raw matrix (var_len x nobs) -> character vector. With an
# `encoding`, mark the flat bytes latin1 so substring uses byte offsets, then
# iconv to UTF-8 at C level; without, pass bytes through per observation.
#' @noRd
.raw_mat_to_strvec <- function(raw_mat, encoding = NULL) {
  var_len <- nrow(raw_mat)
  nobs <- ncol(raw_mat)
  if (nobs == 0L) {
    return(character(0L))
  }
  raw_mat[raw_mat == as.raw(0x00)] <- as.raw(0x20)

  if (!is.null(encoding) && nzchar(encoding)) {
    flat <- rawToChar(as.raw(raw_mat))
    Encoding(flat) <- "latin1"
    starts <- (seq_len(nobs) - 1L) * var_len + 1L
    out <- substring(flat, starts, starts + var_len - 1L)
    out <- iconv(out, from = encoding, to = "UTF-8", sub = "byte")
    sub(" +$", "", out)
  } else {
    out <- apply(raw_mat, 2L, rawToChar)
    sub(" +$", "", out, useBytes = TRUE)
  }
}

# Format a POSIXct as the 16-char SAS header datetime (ddMMMyy:hh:mm:ss, UTC).
# `time` is required by callers that need byte-stable output. The month token
# table is hardcoded: format(%b) follows LC_TIME, and a non-English locale
# (e.g. "JANV.") would widen the field and shift every header field after it.
.sas_month_tokens <- c(
  "JAN",
  "FEB",
  "MAR",
  "APR",
  "MAY",
  "JUN",
  "JUL",
  "AUG",
  "SEP",
  "OCT",
  "NOV",
  "DEC"
)

#' @noRd
.sas_datetime_str <- function(time) {
  lt <- as.POSIXlt(time, tz = "UTC")
  sprintf(
    "%02d%s%02d:%02d:%02d:%02d",
    lt$mday,
    .sas_month_tokens[lt$mon + 1L],
    lt$year %% 100L,
    lt$hour,
    lt$min,
    as.integer(lt$sec)
  )
}

# Read exactly `n` bytes from a connection, or abort on a short read.
#' @noRd
.read_bytes <- function(con, n, call = rlang::caller_env()) {
  raw_vec <- readBin(con, what = "raw", n = n)
  if (length(raw_vec) < n) {
    cli::cli_abort(
      c(
        "Unexpected end of XPORT file.",
        "x" = "Expected {n} byte{?s}, got {length(raw_vec)}."
      ),
      class = "vport_error_codec",
      call = call
    )
  }
  raw_vec
}
