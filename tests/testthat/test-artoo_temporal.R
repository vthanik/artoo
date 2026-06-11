# Tests for the temporal layer: SAS-epoch realize/deflate (the crux of
# lossless dates), format classification, and the resolvers. The headline
# guard is the 1960-vs-1970 epoch: 2014-01-02 is SAS day 19725, not 16072.

# ---- format classification + parsing ---------------------------------------

test_that("SAS format families classify correctly", {
  expect_true(artoo:::.is_sas_date_format("DATE"))
  expect_true(artoo:::.is_sas_date_format("yymmdd"))
  expect_true(artoo:::.is_sas_datetime_format("DATETIME"))
  expect_true(artoo:::.is_sas_time_format("TIME"))
  expect_false(artoo:::.is_sas_date_format("DATETIME"))
  expect_false(artoo:::.is_sas_date_format("$CHAR"))
})

test_that(".parse_format_str splits name / width / decimals", {
  expect_identical(artoo:::.parse_format_str("DATE9.")$name, "DATE")
  expect_identical(artoo:::.parse_format_str("DATE9.")$length, 9L)
  expect_identical(artoo:::.parse_format_str("F8.2")$decimals, 2L)
  expect_identical(artoo:::.parse_format_str("DATETIME16")$name, "DATETIME")
  expect_identical(artoo:::.parse_format_str("")$name, "")
})

test_that(".resolve_display_format defaults by dataType when missing", {
  expect_identical(artoo:::.resolve_display_format("date", NA), "DATE9.")
  expect_identical(
    artoo:::.resolve_display_format("datetime", NA),
    "DATETIME20."
  )
  expect_identical(artoo:::.resolve_display_format("time", NA), "TIME8.")
  expect_identical(
    artoo:::.resolve_display_format("date", "YYMMDD10."),
    "YYMMDD10."
  )
})

test_that(".presentation_class maps temporal dataType to R class", {
  expect_identical(artoo:::.presentation_class("date"), "Date")
  expect_identical(artoo:::.presentation_class("datetime"), "POSIXct")
  expect_identical(artoo:::.presentation_class("time"), "hms")
  expect_identical(artoo:::.presentation_class("string"), "character")
})

# ---- realize: numeric SAS-epoch -> R class ---------------------------------

test_that("realize date uses the SAS 1960 epoch (the bug guard)", {
  # SAS day 19725 == 2014-01-02 (NOT the R-epoch 16072).
  d <- artoo:::.realize_temporal(19725, "date", "DATE9.")
  expect_s3_class(d, "Date")
  expect_identical(format(d), "2014-01-02")
})

test_that("realize datetime uses 1960 seconds in UTC", {
  # 2014-01-02 00:00:00 == SAS second 19725*86400.
  dt <- artoo:::.realize_temporal(19725 * 86400, "datetime", "DATETIME20.")
  expect_s3_class(dt, "POSIXct")
  expect_identical(format(dt, tz = "UTC"), "2014-01-02")
  expect_identical(attr(dt, "tzone"), "UTC")
})

test_that("realize time becomes hms seconds since midnight", {
  t <- artoo:::.realize_temporal(30600, "time", "TIME8.")
  expect_s3_class(t, "hms")
  expect_identical(as.numeric(t, units = "secs"), 30600)
  expect_identical(trimws(format(t)), "08:30:00")
})

test_that("realize handles pre-1960 (negative) dates", {
  d <- artoo:::.realize_temporal(-3653, "date", "DATE9.") # SAS day -3653
  expect_identical(format(d), "1949-12-31")
})

test_that("realize is idempotent on already-correct classes", {
  d <- as.Date("2014-01-02")
  expect_identical(artoo:::.realize_temporal(d, "date", "DATE9."), d)
  t <- hms::hms(30600)
  expect_identical(artoo:::.realize_temporal(t, "time", "TIME8."), t)
})

test_that("realize forces UTC on an already-POSIXct input", {
  p <- as.POSIXct("2014-01-02 08:00:00", tz = "America/New_York")
  out <- artoo:::.realize_temporal(p, "datetime", "DATETIME20.")
  expect_identical(attr(out, "tzone"), "UTC")
  # same absolute instant, not a wall-clock shift
  expect_equal(as.numeric(out), as.numeric(p))
})

test_that("realize leaves NA as the classed NA", {
  d <- artoo:::.realize_temporal(c(19725, NA), "date", "DATE9.")
  expect_true(is.na(d[2]))
  expect_s3_class(d, "Date")
})

test_that("an unrecognized format leaves the column numeric (validation defers)", {
  out <- artoo:::.realize_temporal(19725, "date", "$CHAR8.")
  expect_type(out, "double")
  expect_identical(out, 19725)
})

test_that("partial ISO dates stay character (never silent NA)", {
  out <- artoo:::.realize_temporal(c("2014-01-02", "2014"), "date", "DATE9.")
  expect_type(out, "character")
})

# ---- deflate: R class -> SAS-epoch numeric ---------------------------------

test_that("deflate inverts realize for all three families", {
  expect_identical(
    artoo:::.deflate_temporal(as.Date("2014-01-02"), "date"),
    19725
  )
  dt <- as.POSIXct("2014-01-02", tz = "UTC")
  expect_identical(artoo:::.deflate_temporal(dt, "datetime"), 19725 * 86400)
  expect_identical(artoo:::.deflate_temporal(hms::hms(30600), "time"), 30600)
})

test_that("deflate is robust to an already-numeric input (double-deflate safe)", {
  expect_identical(artoo:::.deflate_temporal(19725, "date"), 19725)
})

test_that("realize parses complete ISO character input per family (from_text)", {
  # from_text = TRUE is the explicit opt-in (targetDataType demands numeric
  # storage); without it, ISO text is the CDISC storage form and stays put.
  d <- artoo:::.realize_temporal(
    c("2014-01-02", NA),
    "date",
    "E8601DA.",
    from_text = TRUE
  )
  expect_s3_class(d, "Date")
  expect_identical(format(d[1]), "2014-01-02")

  dt <- artoo:::.realize_temporal(
    "2014-01-02T08:30:00",
    "datetime",
    "E8601DT.",
    from_text = TRUE
  )
  expect_s3_class(dt, "POSIXct")
  expect_identical(format(dt, "%H:%M:%S", tz = "UTC"), "08:30:00")

  t <- artoo:::.realize_temporal(
    c("08:30:00", "25:00:00"),
    "time",
    "TIME8.",
    from_text = TRUE
  )
  expect_s3_class(t, "hms")
  expect_identical(as.numeric(t, units = "secs"), c(30600, 90000))
})

test_that("character ISO text stays character without from_text", {
  expect_type(
    artoo:::.realize_temporal(c("2014-01-02", NA), "date", "DATE9."),
    "character"
  )
})

test_that("partial ISO datetime and time stay character even under from_text", {
  expect_type(
    artoo:::.realize_temporal(
      c("2014-01-02T08", "x"),
      "datetime",
      "DATETIME20.",
      from_text = TRUE
    ),
    "character"
  )
  expect_type(
    artoo:::.realize_temporal(
      c("8h", "9h"),
      "time",
      "TIME8.",
      from_text = TRUE
    ),
    "character"
  )
})

test_that(".parse_hms_text returns NA for a malformed token", {
  expect_identical(artoo:::.parse_hms_text("08:30"), NA_real_)
})

test_that(".parse_format_str handles a name with no width", {
  expect_identical(artoo:::.parse_format_str("DATE.")$name, "DATE")
  expect_identical(artoo:::.parse_format_str("DATE.")$length, 0L)
})

test_that("realize then deflate round-trips a date vector exactly", {
  days <- c(0, 19725, -3653, 30000)
  back <- artoo:::.deflate_temporal(
    artoo:::.realize_temporal(days, "date", "DATE9."),
    "date"
  )
  expect_identical(back, days)
})

# ---- external oracle: known SAS-epoch day / second counts -------------------
# Independent of the deflate code: 1960-01-01 is day 0, 1960 is a leap year.

test_that(".deflate_temporal matches known SAS-epoch constants", {
  expect_identical(artoo:::.deflate_temporal(as.Date("1960-01-01"), "date"), 0)
  expect_identical(
    artoo:::.deflate_temporal(as.Date("1961-01-01"), "date"),
    366
  )
  expect_identical(
    artoo:::.deflate_temporal(as.Date("2020-01-01"), "date"),
    21915
  )
  expect_identical(
    artoo:::.deflate_temporal(
      as.POSIXct("1960-01-01 00:00:01", tz = "UTC"),
      "datetime"
    ),
    1
  )
})

test_that(".realize_temporal inverts the known SAS-epoch constants", {
  expect_identical(
    artoo:::.realize_temporal(0, "date", "DATE9."),
    as.Date("1960-01-01")
  )
  expect_identical(
    artoo:::.realize_temporal(366, "date", "DATE9."),
    as.Date("1961-01-01")
  )
})

# ---- Wave 2: fractional seconds, UTC offsets, impossible dates, difftime ----

test_that("realize datetime parses fractional seconds", {
  dt <- artoo:::.realize_temporal(
    "2014-01-02T08:30:00.5",
    "datetime",
    "E8601DT.",
    from_text = TRUE
  )
  expect_s3_class(dt, "POSIXct")
  expect_identical(as.numeric(dt) %% 60, 0.5)
})

test_that("realize datetime honors a UTC offset as an instant", {
  # 08:30 at +05:30 is the same instant as 03:00 UTC.
  off <- artoo:::.realize_temporal(
    "2014-01-02T08:30:00+05:30",
    "datetime",
    "E8601DT.",
    from_text = TRUE
  )
  utc <- artoo:::.realize_temporal(
    "2014-01-02T03:00:00",
    "datetime",
    "E8601DT.",
    from_text = TRUE
  )
  expect_identical(as.numeric(off), as.numeric(utc))
  # Z is the zero offset
  z <- artoo:::.realize_temporal(
    "2014-01-02T03:00:00Z",
    "datetime",
    "E8601DT.",
    from_text = TRUE
  )
  expect_identical(as.numeric(z), as.numeric(utc))
})

test_that("realize datetime leaves an impossible datetime character", {
  out <- artoo:::.realize_temporal(
    c("2014-01-02T08:30:00", "2014-13-45T08:30:00"),
    "datetime",
    "E8601DT.",
    from_text = TRUE
  )
  expect_type(out, "character")
})

test_that("realize time parses fractional seconds", {
  t <- artoo:::.realize_temporal(
    "08:30:00.5",
    "time",
    "TIME8.",
    from_text = TRUE
  )
  expect_s3_class(t, "hms")
  expect_identical(as.numeric(t, units = "secs"), 30600.5)
})

test_that("realize date leaves a shape-valid impossible date character", {
  # 2014-13-45 matches the YYYY-MM-DD shape but as.Date() would crash on it
  # via charToDate; the realize must not crash and must not silently NA it.
  out <- artoo:::.realize_temporal(
    c("2014-01-02", "2014-13-45"),
    "date",
    "DATE9.",
    from_text = TRUE
  )
  expect_type(out, "character")
  out2 <- artoo:::.realize_temporal(
    c("2014-01-02", "2014-02-30"),
    "date",
    "DATE9."
  )
  expect_type(out2, "character")
})

test_that(".infer_frame_type recognizes difftime/hms columns as time", {
  d <- as.difftime(30600, units = "secs")
  expect_identical(artoo:::.infer_frame_type(d)$data_type, "time")
  expect_identical(artoo:::.infer_frame_type(d)$display_format, "TIME8.")
  hms <- structure(30600, class = c("hms", "difftime"), units = "secs")
  expect_identical(artoo:::.infer_frame_type(hms)$data_type, "time")
})

test_that(".deflate_temporal converts a difftime via seconds", {
  d <- as.difftime(c(30600, 50400), units = "mins")
  expect_identical(
    artoo:::.deflate_temporal(d, "time"),
    c(30600, 50400) * 60
  )
})

# ---- review 2026-06: deflate refuses inputs it would corrupt ----------------

test_that(".deflate_temporal refuses character temporals (review B7)", {
  # A year-only partial date ("2014") coerced fine via as.numeric() and was
  # silently written as SAS day 2014 = 1965-07-07.
  expect_error(
    artoo:::.deflate_temporal(c("2014", "2015"), "date", var = "ADT"),
    class = "artoo_error_codec"
  )
})

test_that(".deflate_temporal refuses a class/dataType mismatch (review B7)", {
  expect_error(
    artoo:::.deflate_temporal(
      as.POSIXct("2014-01-02", tz = "UTC"),
      "date",
      var = "ADT"
    ),
    class = "artoo_error_codec"
  )
  expect_error(
    artoo:::.deflate_temporal(as.Date("2014-01-02"), "datetime", var = "ADTM"),
    class = "artoo_error_codec"
  )
  expect_error(
    artoo:::.deflate_temporal(hms::hms(30600), "date", var = "ADT"),
    class = "artoo_error_codec"
  )
})

test_that(".deflate_temporal still passes through SAS-epoch numerics", {
  expect_identical(artoo:::.deflate_temporal(c(2014, NA), "date"), c(2014, NA))
  expect_identical(artoo:::.deflate_temporal(30600L, "time"), 30600)
})

# ---- hms time model (replaces the old artoo_time class) ---------------------

test_that(".time_iso_text renders unpadded exchange text", {
  # Sign preserved, hours past 24 allowed, fraction only where present
  # (deliberately NOT format(<hms>), which pads and uniformizes fractions).
  expect_identical(
    artoo:::.time_iso_text(c(30600, NA, 30600.5, -120, 100000)),
    c("08:30:00", NA, "08:30:00.5", "-00:02:00", "27:46:40")
  )
})

test_that("deflating an hms yields a bare double with no units attribute", {
  s <- artoo:::.deflate_temporal(hms::hms(c(3600.5, NA, -120)), "time")
  expect_identical(s, c(3600.5, NA, -120))
  expect_null(attributes(s))
})

test_that("a plain difftime realizes to hms with unit conversion", {
  d <- as.difftime(1.5, units = "hours")
  t <- artoo:::.realize_temporal(d, "time", "TIME8.")
  expect_s3_class(t, "hms")
  expect_identical(as.numeric(t, units = "secs"), 5400)
})

test_that(">24h, negative, and fractional times round-trip every codec", {
  df <- data.frame(USUBJID = c("01", "02", "03", "04"))
  df$ATM <- hms::hms(c(100000, -120, 30600.5, NA))
  for (writer_ext in c(".xpt", ".json", ".ndjson", ".parquet", ".rds")) {
    if (writer_ext == ".parquet") {
      skip_if_not_installed("nanoparquet")
    }
    p <- withr::local_tempfile(fileext = writer_ext)
    write_dataset(df, p)
    back <- read_dataset(p)
    expect_s3_class(back$ATM, "hms")
    expect_identical(
      as.numeric(back$ATM, units = "secs"),
      as.numeric(df$ATM, units = "secs"),
      info = writer_ext
    )
  }
})

test_that("a scaffolded time variable is hms after apply_spec", {
  spec <- artoo_spec(
    data.frame(dataset = "ADVS"),
    data.frame(
      dataset = "ADVS",
      variable = c("USUBJID", "ATM"),
      data_type = c("string", "time"),
      target_data_type = c(NA, "integer"),
      display_format = c(NA, "TIME8."),
      stringsAsFactors = FALSE
    )
  )
  raw <- data.frame(USUBJID = c("01-001", "01-002"), stringsAsFactors = FALSE)
  out <- apply_spec(raw, spec, "ADVS", conformance = "off")
  expect_s3_class(out$ATM, "hms")
  expect_true(all(is.na(out$ATM)))
})
