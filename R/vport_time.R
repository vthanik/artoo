# vport_time.R -- a clock-time-of-day S3 class.
#
# SAS TIME values are seconds since midnight. vport stores them as a bare
# double tagged `vport_time`, with a format method so the RStudio/Positron
# data viewer renders HH:MM:SS instead of raw seconds. Chosen over hms to
# avoid the vctrs dependency hms pulls in. The underlying double is the
# lossless storage: `unclass()` recovers the exact seconds for the codecs.

#' Build a clock-time-of-day value
#'
#' Construct a `vport_time`: vport's class for SAS `TIME` values, held as
#' seconds since midnight and rendered `HH:MM:SS` in the RStudio/Positron
#' data viewer. `read_xpt()` and [apply_spec()] produce these for time
#' variables; build one directly to assemble a time column by hand. Chosen
#' over `hms` to keep vport free of the `vctrs` dependency.
#'
#' @param x *Seconds since midnight.* `<numeric>: default empty`. Coerced to
#'   double. May exceed 86400 (elapsed times past 24h) or be negative; both
#'   round-trip losslessly. `NA` is preserved.
#'
#' @return *A `<vport_time>`* of the same length as `x`.
#'
#' @examples
#' # ---- Example 1: build and render a few clock times ----
#' #
#' # Seconds since midnight become HH:MM:SS in print and in the data viewer.
#' vport_time(c(0, 30600, 86399))
#'
#' # ---- Example 2: a time column inside a data frame ----
#' #
#' # vport_time survives data.frame() as a column and keeps its clock display.
#' data.frame(visit = c("BASELINE", "WEEK 2"), aval_tm = vport_time(c(28800, 50400)))
#'
#' @seealso [is_vport_time()] to test; [apply_spec()] which realizes SAS time
#'   variables to this class.
#' @export
vport_time <- function(x = double()) {
  if (is_vport_time(x)) {
    return(x)
  }
  structure(as.double(x), class = "vport_time")
}

#' Test for a vport_time value
#'
#' Report whether an object is a `vport_time` -- vport's clock-time-of-day
#' class (seconds since midnight, rendered `HH:MM:SS`). SAS `TIME` columns
#' read by `read_xpt()` and conformed by [apply_spec()] arrive as
#' `vport_time`; use this to guard before time-specific handling.
#'
#' @param x *Object to test.* `<any>`.
#'
#' @return *A `<logical(1)>`*: `TRUE` when `x` is a `vport_time`.
#'
#' @examples
#' # ---- Example 1: a time-of-day value is a vport_time ----
#' #
#' # The class SAS time variables arrive as after read_xpt()/apply_spec().
#' is_vport_time(vport_time(c(0, 30600)))
#'
#' # ---- Example 2: distinguish from Date and POSIXct ----
#' #
#' # Only time-of-day columns are vport_time; dates and datetimes are the base
#' # R classes.
#' is_vport_time(Sys.Date())
#'
#' @seealso [vport_time()] to build one; [apply_spec()] which realizes
#'   temporal columns.
#' @export
is_vport_time <- function(x) {
  inherits(x, "vport_time")
}

#' @exportS3Method format vport_time
format.vport_time <- function(x, ...) {
  s <- unclass(x)
  out <- rep(NA_character_, length(s))
  ok <- !is.na(s)
  if (any(ok)) {
    sv <- s[ok]
    sign <- ifelse(sv < 0, "-", "")
    a <- abs(sv)
    hh <- as.integer(a %/% 3600)
    mm <- as.integer((a %% 3600) %/% 60)
    ss <- as.integer(a %% 60)
    out[ok] <- sprintf("%s%02d:%02d:%02d", sign, hh, mm, ss)
  }
  out
}

#' @exportS3Method print vport_time
print.vport_time <- function(x, ...) {
  cat(sprintf("<vport_time[%d]>\n", length(x)))
  print(format(x), quote = FALSE)
  invisible(x)
}

#' @exportS3Method as.character vport_time
as.character.vport_time <- function(x, ...) {
  format(x)
}

#' @exportS3Method `[` vport_time
`[.vport_time` <- function(x, i) {
  vport_time(unclass(x)[i])
}

#' @exportS3Method `[[` vport_time
`[[.vport_time` <- function(x, i) {
  vport_time(unclass(x)[[i]])
}

#' @exportS3Method c vport_time
c.vport_time <- function(...) {
  parts <- lapply(list(...), function(a) {
    if (!is_vport_time(a) && !is.numeric(a)) {
      cli::cli_abort(
        "Cannot combine {.cls vport_time} with {.obj_type_friendly {a}}.",
        class = "vport_error_input"
      )
    }
    unclass(a)
  })
  vport_time(do.call(c, parts))
}

#' @exportS3Method rep vport_time
rep.vport_time <- function(x, ...) {
  vport_time(rep(unclass(x), ...))
}

# Class-preserving column behavior in data.frame() / as.data.frame().
#' @exportS3Method as.data.frame vport_time
as.data.frame.vport_time <- as.data.frame.vector

#' @exportS3Method xtfrm vport_time
xtfrm.vport_time <- function(x) {
  unclass(x)
}

#' @exportS3Method Ops vport_time
Ops.vport_time <- function(e1, e2) {
  v1 <- if (is_vport_time(e1)) unclass(e1) else e1
  v2 <- if (missing(e2)) {
    NULL
  } else if (is_vport_time(e2)) {
    unclass(e2)
  } else {
    e2
  }
  result <- if (is.null(v2)) get(.Generic)(v1) else get(.Generic)(v1, v2)
  if (.Generic %in% c("+", "-", "*", "/")) vport_time(result) else result
}

#' @exportS3Method Summary vport_time
Summary.vport_time <- function(..., na.rm = FALSE) {
  vals <- lapply(list(...), function(a) {
    if (is_vport_time(a)) unclass(a) else a
  })
  result <- do.call(.Generic, c(vals, list(na.rm = na.rm)))
  if (.Generic %in% c("min", "max", "range")) vport_time(result) else result
}
