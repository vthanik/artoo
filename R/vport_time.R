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
#'   round-trip losslessly. Fractional seconds are kept and render hms-style
#'   (`08:30:00.5`). `NA` is preserved.
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

# A legal right-hand side for assignment into / combination with a vport_time:
# another vport_time, any numeric, or an all-NA logical (the bare `NA`).
#' @noRd
.is_time_rhs <- function(value) {
  is_vport_time(value) ||
    is.numeric(value) ||
    (is.logical(value) && all(is.na(value)))
}

#' @exportS3Method `[<-` vport_time
`[<-.vport_time` <- function(x, i, value) {
  if (!.is_time_rhs(value)) {
    cli::cli_abort(
      "Cannot assign {.obj_type_friendly {value}} into a {.cls vport_time}.",
      class = "vport_error_input",
      call = rlang::caller_env()
    )
  }
  v <- unclass(x)
  v[i] <- if (is_vport_time(value)) unclass(value) else as.double(value)
  vport_time(v)
}

#' @exportS3Method `[[<-` vport_time
`[[<-.vport_time` <- function(x, i, value) {
  if (!.is_time_rhs(value)) {
    cli::cli_abort(
      "Cannot assign {.obj_type_friendly {value}} into a {.cls vport_time}.",
      class = "vport_error_input",
      call = rlang::caller_env()
    )
  }
  v <- unclass(x)
  v[[i]] <- if (is_vport_time(value)) unclass(value) else as.double(value)
  vport_time(v)
}

#' @exportS3Method c vport_time
c.vport_time <- function(...) {
  call <- rlang::caller_env()
  parts <- lapply(list(...), function(a) {
    if (!.is_time_rhs(a)) {
      cli::cli_abort(
        "Cannot combine {.cls vport_time} with {.obj_type_friendly {a}}.",
        class = "vport_error_input",
        call = call
      )
    }
    if (is_vport_time(a)) unclass(a) else as.double(a)
  })
  vport_time(do.call(c, parts))
}

#' @exportS3Method unique vport_time
unique.vport_time <- function(x, ...) {
  vport_time(unique(unclass(x), ...))
}

#' @exportS3Method mean vport_time
mean.vport_time <- function(x, ...) {
  vport_time(mean(unclass(x), ...))
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
  comparison <- .Generic %in% c("==", "!=", "<", "<=", ">", ">=")
  if (comparison && (is.character(e1) || (!missing(e2) && is.character(e2)))) {
    # t == "08:30:00" used to unclass to numeric, then R coerced both to
    # character and compared "30600" with "08:30:00" -- silently wrong.
    cli::cli_abort(
      c(
        "Cannot compare a {.cls vport_time} with a character value.",
        "i" = "Build a {.cls vport_time} with {.fn vport_time}, or compare on seconds."
      ),
      class = "vport_error_input",
      call = rlang::caller_env()
    )
  }
  v1 <- if (is_vport_time(e1)) unclass(e1) else e1
  v2 <- if (missing(e2)) {
    NULL
  } else if (is_vport_time(e2)) {
    unclass(e2)
  } else {
    e2
  }
  result <- if (is.null(v2)) get(.Generic)(v1) else get(.Generic)(v1, v2)
  # %% / %/% join the additive set: day-wrap (t %% 86400) stays a clock time.
  if (.Generic %in% c("+", "-", "*", "/", "%%", "%/%")) {
    vport_time(result)
  } else {
    result
  }
}

#' @exportS3Method Summary vport_time
Summary.vport_time <- function(..., na.rm = FALSE) {
  vals <- lapply(list(...), function(a) {
    if (is_vport_time(a)) unclass(a) else a
  })
  result <- do.call(.Generic, c(vals, list(na.rm = na.rm)))
  if (.Generic %in% c("min", "max", "range")) vport_time(result) else result
}
