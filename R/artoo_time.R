# artoo_time.R -- a clock-time-of-day S3 class.
#
# SAS TIME values are seconds since midnight. artoo stores them as a bare
# double tagged `artoo_time`, with a format method so the RStudio/Positron
# data viewer renders HH:MM:SS instead of raw seconds. Chosen over hms to
# avoid the vctrs dependency hms pulls in. The underlying double is the
# lossless storage: `unclass()` recovers the exact seconds for the codecs.

#' Build a clock-time-of-day value
#'
#' Construct a `artoo_time`: artoo's class for SAS `TIME` values, held as
#' seconds since midnight and rendered `HH:MM:SS` in the RStudio/Positron
#' data viewer. `read_xpt()` and [apply_spec()] produce these for time
#' variables; build one directly to assemble a time column by hand. Chosen
#' over `hms` to keep artoo free of the `vctrs` dependency.
#'
#' @param x *Seconds since midnight.* `<numeric>: default empty`. Coerced to
#'   double. May exceed 86400 (elapsed times past 24h) or be negative; both
#'   round-trip losslessly. Fractional seconds are kept and render hms-style
#'   (`08:30:00.5`). `NA` is preserved.
#'
#' @return *A `<artoo_time>`* of the same length as `x`.
#'
#' @examples
#' # ---- Example 1: build and render a few clock times ----
#' #
#' # Seconds since midnight become HH:MM:SS in print and in the data viewer.
#' artoo_time(c(0, 30600, 86399))
#'
#' # ---- Example 2: a time column inside a data frame ----
#' #
#' # artoo_time survives data.frame() as a column and keeps its clock display.
#' data.frame(visit = c("BASELINE", "WEEK 2"), aval_tm = artoo_time(c(28800, 50400)))
#'
#' @seealso [is_artoo_time()] to test; [apply_spec()] which realizes SAS time
#'   variables to this class.
#' @export
artoo_time <- function(x = double()) {
  if (is_artoo_time(x)) {
    return(x)
  }
  structure(as.double(x), class = "artoo_time")
}

#' Test for a artoo_time value
#'
#' Report whether an object is a `artoo_time` -- artoo's clock-time-of-day
#' class (seconds since midnight, rendered `HH:MM:SS`). SAS `TIME` columns
#' read by `read_xpt()` and conformed by [apply_spec()] arrive as
#' `artoo_time`; use this to guard before time-specific handling.
#'
#' @param x *Object to test.* `<any>`.
#'
#' @return *A `<logical(1)>`*: `TRUE` when `x` is a `artoo_time`.
#'
#' @examples
#' # ---- Example 1: a time-of-day value is a artoo_time ----
#' #
#' # The class SAS time variables arrive as after read_xpt()/apply_spec().
#' is_artoo_time(artoo_time(c(0, 30600)))
#'
#' # ---- Example 2: distinguish from Date and POSIXct ----
#' #
#' # Only time-of-day columns are artoo_time; dates and datetimes are the base
#' # R classes.
#' is_artoo_time(Sys.Date())
#'
#' @seealso [artoo_time()] to build one; [apply_spec()] which realizes
#'   temporal columns.
#' @export
is_artoo_time <- function(x) {
  inherits(x, "artoo_time")
}

#' @exportS3Method format artoo_time
format.artoo_time <- function(x, ...) {
  s <- unclass(x)
  out <- rep(NA_character_, length(s))
  ok <- !is.na(s)
  if (any(ok)) {
    sv <- s[ok]
    sign <- ifelse(sv < 0, "-", "")
    a <- abs(sv)
    hh <- as.integer(a %/% 3600)
    mm <- as.integer((a %% 3600) %/% 60)
    sec <- a %% 60
    ss <- as.integer(sec)
    base <- sprintf("%s%02d:%02d:%02d", sign, hh, mm, ss)
    # Fractional seconds render hms-style: 08:30:00.5, trailing zeros stripped.
    frac <- sec - ss
    has_frac <- frac > 0
    if (any(has_frac)) {
      fs <- formatC(frac[has_frac], format = "f", digits = 6)
      fs <- sub("^0", "", sub("0+$", "", fs))
      base[has_frac] <- paste0(base[has_frac], fs)
    }
    out[ok] <- base
  }
  out
}

#' @exportS3Method print artoo_time
print.artoo_time <- function(x, ...) {
  cat(sprintf("<artoo_time[%d]>\n", length(x)))
  print(format(x), quote = FALSE)
  invisible(x)
}

#' @exportS3Method as.character artoo_time
as.character.artoo_time <- function(x, ...) {
  format(x)
}

#' @exportS3Method `[` artoo_time
`[.artoo_time` <- function(x, i) {
  artoo_time(unclass(x)[i])
}

#' @exportS3Method `[[` artoo_time
`[[.artoo_time` <- function(x, i) {
  artoo_time(unclass(x)[[i]])
}

# A legal right-hand side for assignment into / combination with a artoo_time:
# another artoo_time, any numeric, or an all-NA logical (the bare `NA`).
#' @noRd
.is_time_rhs <- function(value) {
  is_artoo_time(value) ||
    is.numeric(value) ||
    (is.logical(value) && all(is.na(value)))
}

#' @exportS3Method `[<-` artoo_time
`[<-.artoo_time` <- function(x, i, value) {
  if (!.is_time_rhs(value)) {
    cli::cli_abort(
      "Cannot assign {.obj_type_friendly {value}} into a {.cls artoo_time}.",
      class = "artoo_error_input",
      call = rlang::caller_env()
    )
  }
  v <- unclass(x)
  v[i] <- if (is_artoo_time(value)) unclass(value) else as.double(value)
  artoo_time(v)
}

#' @exportS3Method `[[<-` artoo_time
`[[<-.artoo_time` <- function(x, i, value) {
  if (!.is_time_rhs(value)) {
    cli::cli_abort(
      "Cannot assign {.obj_type_friendly {value}} into a {.cls artoo_time}.",
      class = "artoo_error_input",
      call = rlang::caller_env()
    )
  }
  v <- unclass(x)
  v[[i]] <- if (is_artoo_time(value)) unclass(value) else as.double(value)
  artoo_time(v)
}

#' @exportS3Method c artoo_time
c.artoo_time <- function(...) {
  call <- rlang::caller_env()
  parts <- lapply(list(...), function(a) {
    if (!.is_time_rhs(a)) {
      cli::cli_abort(
        "Cannot combine {.cls artoo_time} with {.obj_type_friendly {a}}.",
        class = "artoo_error_input",
        call = call
      )
    }
    if (is_artoo_time(a)) unclass(a) else as.double(a)
  })
  artoo_time(do.call(c, parts))
}

#' @exportS3Method unique artoo_time
unique.artoo_time <- function(x, ...) {
  artoo_time(unique(unclass(x), ...))
}

#' @exportS3Method mean artoo_time
mean.artoo_time <- function(x, ...) {
  artoo_time(mean(unclass(x), ...))
}

#' @exportS3Method rep artoo_time
rep.artoo_time <- function(x, ...) {
  artoo_time(rep(unclass(x), ...))
}

# Class-preserving column behavior in data.frame() / as.data.frame().
#' @exportS3Method as.data.frame artoo_time
as.data.frame.artoo_time <- as.data.frame.vector

#' @exportS3Method xtfrm artoo_time
xtfrm.artoo_time <- function(x) {
  unclass(x)
}

#' @exportS3Method Ops artoo_time
Ops.artoo_time <- function(e1, e2) {
  comparison <- .Generic %in% c("==", "!=", "<", "<=", ">", ">=")
  if (comparison && (is.character(e1) || (!missing(e2) && is.character(e2)))) {
    # t == "08:30:00" used to unclass to numeric, then R coerced both to
    # character and compared "30600" with "08:30:00" -- silently wrong.
    cli::cli_abort(
      c(
        "Cannot compare a {.cls artoo_time} with a character value.",
        "i" = "Build a {.cls artoo_time} with {.fn artoo_time}, or compare on seconds."
      ),
      class = "artoo_error_input",
      call = rlang::caller_env()
    )
  }
  v1 <- if (is_artoo_time(e1)) unclass(e1) else e1
  v2 <- if (missing(e2)) {
    NULL
  } else if (is_artoo_time(e2)) {
    unclass(e2)
  } else {
    e2
  }
  result <- if (is.null(v2)) get(.Generic)(v1) else get(.Generic)(v1, v2)
  # %% / %/% join the additive set: day-wrap (t %% 86400) stays a clock time.
  if (.Generic %in% c("+", "-", "*", "/", "%%", "%/%")) {
    artoo_time(result)
  } else {
    result
  }
}

#' @exportS3Method Summary artoo_time
Summary.artoo_time <- function(..., na.rm = FALSE) {
  vals <- lapply(list(...), function(a) {
    if (is_artoo_time(a)) unclass(a) else a
  })
  result <- do.call(.Generic, c(vals, list(na.rm = na.rm)))
  if (.Generic %in% c("min", "max", "range")) artoo_time(result) else result
}
