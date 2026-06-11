# vport_temporal.R -- SAS temporal realize/deflate + format classification.
#
# vport presents SAS date/datetime/time columns as native R Date / POSIXct /
# vport_time so they render correctly in the data viewer, while the codecs
# store them as SAS-epoch numerics. `.realize_temporal` (numeric/ISO -> R
# class) and `.deflate_temporal` (R class -> SAS numeric) are the shared
# pair every codec calls; the SAS displayFormat rides in vport_meta. The
# format-classification table is ported from the herald archive
# (xpt-encoding.R); the R-Date conversions there are superseded by the
# epoch-explicit math here.

# SAS epoch anchors. date = days since 1960-01-01; datetime = seconds since
# 1960-01-01 00:00:00 UTC. Computed once at load (deterministic, no locale).
.sas_epoch_date <- as.Date("1960-01-01")
.sas_epoch_datetime <- as.POSIXct("1960-01-01 00:00:00", tz = "UTC")

# ---- format classification (ported; classification only) -------------------

.sas_date_formats <- c(
  "DATE",
  "DAY",
  "DDMMYY",
  "DDMMYYB",
  "DDMMYYC",
  "DDMMYYD",
  "DDMMYYN",
  "DDMMYYP",
  "DDMMYYS",
  "MMDDYY",
  "MMDDYYB",
  "MMDDYYC",
  "MMDDYYD",
  "MMDDYYN",
  "MMDDYYP",
  "MMDDYYS",
  "YYMMDD",
  "YYMMDDB",
  "YYMMDDC",
  "YYMMDDD",
  "YYMMDDN",
  "YYMMDDP",
  "YYMMDDS",
  "YYMM",
  "YYMMC",
  "YYMMD",
  "YYMMN",
  "YYMMP",
  "YYMMS",
  "YYQ",
  "YYQC",
  "YYQD",
  "YYQN",
  "YYQP",
  "YYQS",
  "YYQR",
  "YYQRC",
  "YYQRD",
  "YYQRN",
  "YYQRP",
  "YYQRS",
  "MMYY",
  "MMYYC",
  "MMYYD",
  "MMYYN",
  "MMYYP",
  "MMYYS",
  "MONYY",
  "MONNAME",
  "MONTH",
  "QTR",
  "QTRR",
  "YEAR",
  "WEEKDAY",
  "WEEKDATE",
  "WEEKDATX",
  "WORDDATE",
  "WORDDATX",
  "JULIAN",
  "JULDAY",
  "NENGO",
  "MINGUO",
  "HDATE",
  "HEBDATE",
  "EURDFDD",
  "EURDFDE",
  "EURDFDN",
  "EURDFDT",
  "EURDFDWN",
  "EURDFMN",
  "EURDFMY",
  "EURDFWDX",
  "EURDFWKX",
  "NLDATE",
  "NLDATEL",
  "NLDATEM",
  "NLDATEMD",
  "NLDATEMN",
  "NLDATES",
  "NLDATEW",
  "NLDATEWN",
  "NLDATEYM",
  "NLDATEYMW",
  "PDJULG",
  "PDJULI",
  "B8601DA",
  "E8601DA",
  "DTDATE",
  "DTYEAR",
  "DTMONYY",
  "DTWKDATX",
  "DTYYQC"
)
.sas_datetime_formats <- c(
  "DATETIME",
  "DATEAMPM",
  "MDYAMPM",
  "B8601DN",
  "B8601DT",
  "B8601DZ",
  "B8601LZ",
  "E8601DN",
  "E8601DT",
  "E8601DZ",
  "E8601LZ",
  "NLDATM",
  "NLDATMAP",
  "NLDATMDT",
  "NLDATMMD",
  "NLDATMMN",
  "NLDATMS",
  "NLDATMTM",
  "NLDATMW",
  "NLDATMWN",
  "NLDATMWZ",
  "NLDATMYM",
  "NLDATMYW",
  "NLDATMZ",
  "DTTIME"
)
.sas_time_formats <- c(
  "TIME",
  "TIMEAMPM",
  "HHMM",
  "HOUR",
  "MMSS",
  "TOD",
  "B8601TM",
  "B8601TZ",
  "E8601TM",
  "E8601TZ",
  "NLTIME",
  "NLTIMMAP",
  "NLTIMAP"
)

#' @noRd
.is_sas_date_format <- function(fmt_name) {
  toupper(fmt_name) %in% .sas_date_formats
}
#' @noRd
.is_sas_datetime_format <- function(fmt_name) {
  toupper(fmt_name) %in% .sas_datetime_formats
}
#' @noRd
.is_sas_time_format <- function(fmt_name) {
  toupper(fmt_name) %in% .sas_time_formats
}

# Split a SAS format string into name / width / decimals. "DATE9." ->
# (DATE, 9, 0); "F8.2" -> (F, 8, 2); "DATETIME16" -> (DATETIME, 16, 0).
#' @noRd
.parse_format_str <- function(fmt) {
  if (is.null(fmt) || length(fmt) != 1L || is.na(fmt) || !nzchar(fmt)) {
    return(list(name = "", length = 0L, decimals = 0L))
  }
  dot <- regexpr("\\.[0-9]*$", fmt)
  if (dot > 0L) {
    before <- substr(fmt, 1L, dot - 1L)
    after <- substr(fmt, dot + 1L, nchar(fmt))
    decimals <- if (nzchar(after)) as.integer(after) else 0L
  } else {
    before <- fmt
    decimals <- 0L
  }
  wm <- regexpr("[0-9]+$", before)
  if (wm > 0L) {
    name <- substr(before, 1L, wm - 1L)
    width <- as.integer(substr(before, wm, nchar(before)))
  } else {
    name <- before
    width <- 0L
  }
  list(name = name, length = width, decimals = decimals)
}

# ---- resolvers (shared by coerce, encode, meta_from_frame) ------------------

# The R class a dataType presents as (vs .type_storage's on-disk mode).
#' @noRd
.presentation_class <- function(data_type) {
  switch(
    data_type,
    date = "Date",
    datetime = "POSIXct",
    time = "vport_time",
    .type_storage(data_type)
  )
}

# The xpt storage length: the meta length when set, else max(nchar) for a
# character column, else 8 (full IEEE precision) for a numeric one.
#' @noRd
.resolve_xpt_length <- function(meta_len, col) {
  if (!is.null(meta_len) && length(meta_len) == 1L && !is.na(meta_len)) {
    return(as.integer(meta_len))
  }
  if (is.character(col) || is.factor(col)) {
    m <- suppressWarnings(max(nchar(as.character(col)), 1L, na.rm = TRUE))
    return(as.integer(m))
  }
  8L
}

# Infer a column's CDISC dataType and default SAS displayFormat from its R
# class (the no-spec path). Temporal classes win over their double backing.
#' @noRd
.infer_frame_type <- function(col) {
  if (inherits(col, "Date")) {
    list(data_type = "date", display_format = "DATE9.")
  } else if (inherits(col, "POSIXct")) {
    list(data_type = "datetime", display_format = "DATETIME20.")
  } else if (is_vport_time(col) || inherits(col, "difftime")) {
    # difftime/hms is haven's actual TIME representation; treat it as time.
    list(data_type = "time", display_format = "TIME8.")
  } else if (is.factor(col) || is.character(col)) {
    list(data_type = "string", display_format = NULL)
  } else if (is.logical(col)) {
    list(data_type = "boolean", display_format = NULL)
  } else if (is.integer(col)) {
    list(data_type = "integer", display_format = NULL)
  } else {
    list(data_type = "float", display_format = NULL)
  }
}

# The displayFormat to use: the given one, else the SAS default by dataType.
#' @noRd
.resolve_display_format <- function(data_type, display_format = NA) {
  if (
    !is.null(display_format) &&
      length(display_format) == 1L &&
      !is.na(display_format) &&
      nzchar(display_format)
  ) {
    return(display_format)
  }
  switch(
    data_type,
    date = "DATE9.",
    datetime = "DATETIME20.",
    time = "TIME8.",
    NA_character_
  )
}

# ---- realize: storage -> R presentation class ------------------------------

#' @noRd
.hms_to_seconds <- function(x) {
  vapply(
    strsplit(x, ":", fixed = TRUE),
    function(p) {
      if (length(p) != 3L || anyNA(p)) {
        return(NA_real_)
      }
      as.numeric(p[1L]) * 3600 + as.numeric(p[2L]) * 60 + as.numeric(p[3L])
    },
    numeric(1)
  )
}

# Never-silent-NA gate: if parsing a character temporal turned any non-NA
# value into NA (a shape-valid but impossible date like 2014-13-45, an
# unparseable offset), keep the whole column character so a later deflate
# fails loud instead of writing garbage.
#' @noRd
.keep_if_lossy <- function(col, parsed) {
  if (any(!is.na(col) & is.na(parsed))) {
    return(col)
  }
  parsed
}

#' @noRd
.realize_date <- function(col) {
  if (inherits(col, "Date")) {
    # Canonical in-memory backing is double (what as.Date(character) and the
    # SAS-epoch path produce); nanoparquet's DATE arrives integer-backed.
    # Normalize so identical() holds across codecs.
    if (is.integer(unclass(col))) {
      attrs <- attributes(col)
      col <- as.numeric(unclass(col))
      attributes(col) <- attrs
    }
    return(col)
  }
  if (is.character(col)) {
    full <- is.na(col) | grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", col)
    if (!all(full)) {
      return(col) # partial ISO -> stay character (never silent NA)
    }
    # Explicit format=: strptime returns NA for an impossible date (the bare
    # charToDate path errors on 2014-13-45). .keep_if_lossy catches the NA.
    return(.keep_if_lossy(col, as.Date(col, format = "%Y-%m-%d")))
  }
  as.Date(as.numeric(col), origin = .sas_epoch_date)
}

# Parse full ISO 8601 datetimes to UTC instants. A trailing zone (Z, or
# +/-HH:MM, or +/-HHMM) shifts the wall clock to the UTC instant via %z; a
# value with no zone is read as UTC. Fractional seconds parse via %OS. The
# offset itself is NOT round-tripped on write -- deflate stores SAS numeric
# datetimes, which are UTC instants, by design.
#' @noRd
.parse_iso_datetime <- function(x) {
  out <- .POSIXct(rep(NA_real_, length(x)), tz = "UTC")
  has_zone <- !is.na(x) & grepl("(Z|[+-][0-9]{2}:?[0-9]{2})$", x)
  if (any(has_zone)) {
    z <- sub("Z$", "+0000", x[has_zone])
    z <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", z)
    out[has_zone] <- as.POSIXct(
      z,
      format = "%Y-%m-%dT%H:%M:%OS%z",
      tz = "UTC"
    )
  }
  naive <- !is.na(x) & !has_zone
  if (any(naive)) {
    out[naive] <- as.POSIXct(
      x[naive],
      format = "%Y-%m-%dT%H:%M:%OS",
      tz = "UTC"
    )
  }
  out
}

#' @noRd
.realize_datetime <- function(col) {
  if (inherits(col, "POSIXct")) {
    attr(col, "tzone") <- "UTC" # force UTC display, same instant
    return(col)
  }
  if (is.character(col)) {
    pat <- paste0(
      "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}",
      "(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$"
    )
    full <- is.na(col) | grepl(pat, col)
    if (!all(full)) {
      return(col)
    }
    return(.keep_if_lossy(col, .parse_iso_datetime(col)))
  }
  as.POSIXct(as.numeric(col), origin = .sas_epoch_datetime, tz = "UTC")
}

#' @noRd
.realize_time <- function(col) {
  if (is_vport_time(col)) {
    return(col)
  }
  if (is.character(col)) {
    full <- is.na(col) | grepl("^[0-9]+:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?$", col)
    if (!all(full)) {
      return(col)
    }
    return(.keep_if_lossy(col, vport_time(.hms_to_seconds(col))))
  }
  vport_time(as.numeric(col))
}

# Realize a temporal column to its R class. dataType is authoritative for the
# class; displayFormat only validates -- when it does not classify as the
# matching family, the column is left numeric and the caller (check_spec)
# reports it. Idempotent on already-correct classes.
#
# `from_text` gates character input. Realization exists to make SAS-epoch
# NUMBERS readable; ISO 8601 text is already readable, and in CDISC a
# temporal dataType with no numeric targetDataType IS text (the --DTC
# convention), so promoting it to Date would silently change the
# submission storage shape. Callers pass from_text = TRUE only when the
# metadata explicitly demands numeric storage (targetDataType integer/
# decimal) -- then parsing full-ISO text to the R class is the conform
# step's job (partials still stay character via the never-silent-NA gate).
#' @noRd
.realize_temporal <- function(
  col,
  data_type,
  display_format = NA,
  from_text = FALSE
) {
  if (!(data_type %in% c("date", "datetime", "time"))) {
    return(col)
  }
  if (is.character(col) && !isTRUE(from_text)) {
    return(col)
  }
  fmt <- .resolve_display_format(data_type, display_format)
  fmt_name <- .parse_format_str(fmt)$name
  ok <- switch(
    data_type,
    date = .is_sas_date_format(fmt_name),
    datetime = .is_sas_datetime_format(fmt_name),
    time = .is_sas_time_format(fmt_name)
  )
  if (!isTRUE(ok)) {
    return(col)
  }
  switch(
    data_type,
    date = .realize_date(col),
    datetime = .realize_datetime(col),
    time = .realize_time(col)
  )
}

# ---- deflate: R presentation class -> SAS-epoch numeric --------------------

# A temporal dataType accepts ONLY its presentation class or an
# already-SAS-epoch bare numeric (double-deflate / never-realized column).
# Anything else aborts: a character column would coerce a year-only partial
# date ("2014") to SAS day 2014 = 1965-07-07, and a mismatched temporal class
# (POSIXct under "date") would write seconds as days -- both silent garbage.
# This only fires when the metadata demands numeric storage (targetDataType
# integer/decimal); without one, a character temporal column is written as
# ISO 8601 text (the --DTC convention) and never reaches deflate.
#' @noRd
.deflate_temporal_abort <- function(col, data_type, expected, var, call) {
  headline <- if (is.null(var)) {
    "Cannot write this column as a SAS {data_type} numeric."
  } else {
    "Cannot write column {.var {var}} as a SAS {data_type} numeric."
  }
  cli::cli_abort(
    c(
      headline,
      "x" = "It is {.obj_type_friendly {col}}; with targetDataType {.val integer} a {data_type} column must be {expected} or already a SAS-epoch numeric.",
      "i" = "Partial ISO 8601 values cannot be SAS numerics. Drop the spec's targetDataType to write them as ISO text, or complete the values."
    ),
    class = "vport_error_codec",
    call = call
  )
}

#' @noRd
.deflate_temporal <- function(
  col,
  data_type,
  var = NULL,
  call = rlang::caller_env()
) {
  # is.numeric() is FALSE for Date/POSIXct (base S3 methods) but TRUE for
  # vport_time's bare double, so exclude it explicitly from the passthrough.
  bare_numeric <- is.numeric(col) && !is_vport_time(col)
  switch(
    data_type,
    date = if (inherits(col, "Date")) {
      as.numeric(col - .sas_epoch_date)
    } else if (bare_numeric) {
      as.numeric(col)
    } else {
      .deflate_temporal_abort(col, data_type, "a Date", var, call)
    },
    datetime = if (inherits(col, "POSIXct")) {
      as.numeric(col) - as.numeric(.sas_epoch_datetime)
    } else if (bare_numeric) {
      as.numeric(col)
    } else {
      .deflate_temporal_abort(col, data_type, "a POSIXct", var, call)
    },
    time = if (is_vport_time(col)) {
      unclass(col)
    } else if (inherits(col, "difftime")) {
      as.numeric(col, units = "secs")
    } else if (bare_numeric) {
      as.numeric(col)
    } else {
      .deflate_temporal_abort(col, data_type, "a vport_time", var, call)
    },
    as.numeric(col)
  )
}

# ---- ISO 8601 validation (CDISC-partial-aware) ------------------------------

# Validate character temporal values as ISO 8601 in the forms CDISC data
# actually carries: complete values, right truncation ("2003", "2003-12",
# "2003-12-15T13"), and the SDTMIG hyphen placeholders for unknown
# intermediate components ("2003---15", "--12-15"). NA and "" are never
# violations here -- missingness is the mandatory/codelist checks' concern.
# Returns a logical vector aligned to `x`.
#' @noRd
.iso8601_valid <- function(x, family) {
  out <- rep(TRUE, length(x))
  idx <- which(!is.na(x) & nzchar(trimws(x)))
  if (!length(idx)) {
    return(out)
  }
  out[idx] <- vapply(
    trimws(x[idx]),
    .iso8601_valid1,
    logical(1),
    family = family,
    USE.NAMES = FALSE
  )
  out
}

#' @noRd
.iso8601_valid1 <- function(s, family) {
  if (family == "time") {
    return(.iso_time_ok(sub("^T", "", s)))
  }
  has_t <- grepl("T", s, fixed = TRUE)
  if (family == "date" && has_t) {
    return(FALSE)
  }
  if (!has_t) {
    return(.iso_date_ok(s))
  }
  parts <- strsplit(s, "T", fixed = TRUE)[[1L]]
  if (length(parts) != 2L || !nzchar(parts[2L])) {
    return(FALSE)
  }
  # ISO 8601 requires the date complete (or placeholder-complete) before a
  # time component may follow: "2003-12T13" is malformed.
  .iso_date_ok(parts[1L], need_complete = TRUE) && .iso_time_ok(parts[2L])
}

# One date token: right-truncated digits, or a hyphen-placeholder form.
# Range-checks the present components; full dates get a real calendar check.
#' @noRd
.iso_date_ok <- function(d, need_complete = FALSE) {
  m <- regmatches(
    d,
    regexec("^([0-9]{4})(?:-([0-9]{2})(?:-([0-9]{2}))?)?$", d)
  )[[1L]]
  if (length(m)) {
    if (need_complete && (!nzchar(m[3L]) || !nzchar(m[4L]))) {
      return(FALSE)
    }
    return(.iso_ymd_ok(m[2L], m[3L], m[4L]))
  }
  # SDTMIG placeholders: unknown month ("2003---15") or unknown year
  # ("--12-15"). The remaining digits are still range-checked.
  m <- regmatches(d, regexec("^([0-9]{4})---?([0-9]{2})$", d))[[1L]]
  if (length(m)) {
    return(.iso_ymd_ok(m[2L], "", m[3L]))
  }
  m <- regmatches(d, regexec("^--([0-9]{2})-([0-9]{2})$", d))[[1L]]
  if (length(m)) {
    return(.iso_ymd_ok("", m[2L], m[3L]))
  }
  FALSE
}

#' @noRd
.iso_ymd_ok <- function(y, mo, dy) {
  if (nzchar(mo)) {
    moi <- as.integer(mo)
    if (moi < 1L || moi > 12L) {
      return(FALSE)
    }
  }
  if (nzchar(dy)) {
    dyi <- as.integer(dy)
    if (dyi < 1L || dyi > 31L) {
      return(FALSE)
    }
  }
  if (nzchar(y) && nzchar(mo) && nzchar(dy)) {
    # Real calendar check for complete dates (2014-02-30 is invalid).
    return(!is.na(as.Date(paste(y, mo, dy, sep = "-"), format = "%Y-%m-%d")))
  }
  TRUE
}

# One time token (zone stripped first): right-truncated hh[:mm[:ss[.f]]],
# with the SDTMIG unknown-hour placeholder ("-:15") accepted.
#' @noRd
.iso_time_ok <- function(t) {
  t <- sub("(Z|[+-][0-9]{2}:?[0-9]{2})$", "", t)
  if (!nzchar(t)) {
    return(FALSE)
  }
  m <- regmatches(
    t,
    regexec(
      "^([0-9]{2}|-)(?::([0-9]{2}|-)(?::([0-9]{2})(?:\\.[0-9]+)?)?)?$",
      t
    )
  )[[1L]]
  if (!length(m)) {
    return(FALSE)
  }
  h <- m[2L]
  mi <- m[3L]
  se <- m[4L]
  if (identical(h, "-") && !nzchar(mi)) {
    return(FALSE)
  }
  ok <- TRUE
  if (grepl("^[0-9]{2}$", h)) {
    ok <- ok && as.integer(h) <= 23L
  }
  if (grepl("^[0-9]{2}$", mi)) {
    ok <- ok && as.integer(mi) <= 59L
  }
  if (nzchar(se)) {
    ok <- ok && as.integer(se) <= 59L
  }
  ok
}
