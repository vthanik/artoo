# Tests for the temporal layer: SAS-epoch realize/deflate (the crux of
# lossless dates), format classification, and the resolvers. The headline
# guard is the 1960-vs-1970 epoch: 2014-01-02 is SAS day 19725, not 16072.

# ---- format classification + parsing ---------------------------------------

test_that("SAS format families classify correctly", {
  expect_true(vport:::.is_sas_date_format("DATE"))
  expect_true(vport:::.is_sas_date_format("yymmdd"))
  expect_true(vport:::.is_sas_datetime_format("DATETIME"))
  expect_true(vport:::.is_sas_time_format("TIME"))
  expect_false(vport:::.is_sas_date_format("DATETIME"))
  expect_false(vport:::.is_sas_date_format("$CHAR"))
})

test_that(".parse_format_str splits name / width / decimals", {
  expect_identical(vport:::.parse_format_str("DATE9.")$name, "DATE")
  expect_identical(vport:::.parse_format_str("DATE9.")$length, 9L)
  expect_identical(vport:::.parse_format_str("F8.2")$decimals, 2L)
  expect_identical(vport:::.parse_format_str("DATETIME16")$name, "DATETIME")
  expect_identical(vport:::.parse_format_str("")$name, "")
})

test_that(".resolve_display_format defaults by dataType when missing", {
  expect_identical(vport:::.resolve_display_format("date", NA), "DATE9.")
  expect_identical(
    vport:::.resolve_display_format("datetime", NA),
    "DATETIME20."
  )
  expect_identical(vport:::.resolve_display_format("time", NA), "TIME8.")
  expect_identical(
    vport:::.resolve_display_format("date", "YYMMDD10."),
    "YYMMDD10."
  )
})

test_that(".presentation_class maps temporal dataType to R class", {
  expect_identical(vport:::.presentation_class("date"), "Date")
  expect_identical(vport:::.presentation_class("datetime"), "POSIXct")
  expect_identical(vport:::.presentation_class("time"), "vport_time")
  expect_identical(vport:::.presentation_class("string"), "character")
})

# ---- realize: numeric SAS-epoch -> R class ---------------------------------

test_that("realize date uses the SAS 1960 epoch (the bug guard)", {
  # SAS day 19725 == 2014-01-02 (NOT the R-epoch 16072).
  d <- vport:::.realize_temporal(19725, "date", "DATE9.")
  expect_s3_class(d, "Date")
  expect_identical(format(d), "2014-01-02")
})

test_that("realize datetime uses 1960 seconds in UTC", {
  # 2014-01-02 00:00:00 == SAS second 19725*86400.
  dt <- vport:::.realize_temporal(19725 * 86400, "datetime", "DATETIME20.")
  expect_s3_class(dt, "POSIXct")
  expect_identical(format(dt, tz = "UTC"), "2014-01-02")
  expect_identical(attr(dt, "tzone"), "UTC")
})

test_that("realize time becomes vport_time seconds since midnight", {
  t <- vport:::.realize_temporal(30600, "time", "TIME8.")
  expect_true(is_vport_time(t))
  expect_identical(format(t), "08:30:00")
})

test_that("realize handles pre-1960 (negative) dates", {
  d <- vport:::.realize_temporal(-3653, "date", "DATE9.") # SAS day -3653
  expect_identical(format(d), "1949-12-31")
})

test_that("realize is idempotent on already-correct classes", {
  d <- as.Date("2014-01-02")
  expect_identical(vport:::.realize_temporal(d, "date", "DATE9."), d)
  t <- vport_time(30600)
  expect_identical(vport:::.realize_temporal(t, "time", "TIME8."), t)
})

test_that("realize forces UTC on an already-POSIXct input", {
  p <- as.POSIXct("2014-01-02 08:00:00", tz = "America/New_York")
  out <- vport:::.realize_temporal(p, "datetime", "DATETIME20.")
  expect_identical(attr(out, "tzone"), "UTC")
  # same absolute instant, not a wall-clock shift
  expect_equal(as.numeric(out), as.numeric(p))
})

test_that("realize leaves NA as the classed NA", {
  d <- vport:::.realize_temporal(c(19725, NA), "date", "DATE9.")
  expect_true(is.na(d[2]))
  expect_s3_class(d, "Date")
})

test_that("an unrecognized format leaves the column numeric (validation defers)", {
  out <- vport:::.realize_temporal(19725, "date", "$CHAR8.")
  expect_type(out, "double")
  expect_identical(out, 19725)
})

test_that("partial ISO dates stay character (never silent NA)", {
  out <- vport:::.realize_temporal(c("2014-01-02", "2014"), "date", "DATE9.")
  expect_type(out, "character")
})

# ---- deflate: R class -> SAS-epoch numeric ---------------------------------

test_that("deflate inverts realize for all three families", {
  expect_identical(
    vport:::.deflate_temporal(as.Date("2014-01-02"), "date"),
    19725
  )
  dt <- as.POSIXct("2014-01-02", tz = "UTC")
  expect_identical(vport:::.deflate_temporal(dt, "datetime"), 19725 * 86400)
  expect_identical(vport:::.deflate_temporal(vport_time(30600), "time"), 30600)
})

test_that("deflate is robust to an already-numeric input (double-deflate safe)", {
  expect_identical(vport:::.deflate_temporal(19725, "date"), 19725)
})

test_that("realize parses complete ISO character input per family", {
  d <- vport:::.realize_temporal(c("2014-01-02", NA), "date", "E8601DA.")
  expect_s3_class(d, "Date")
  expect_identical(format(d[1]), "2014-01-02")

  dt <- vport:::.realize_temporal("2014-01-02T08:30:00", "datetime", "E8601DT.")
  expect_s3_class(dt, "POSIXct")
  expect_identical(format(dt, "%H:%M:%S", tz = "UTC"), "08:30:00")

  t <- vport:::.realize_temporal(c("08:30:00", "25:00:00"), "time", "TIME8.")
  expect_true(is_vport_time(t))
  expect_identical(unclass(t), c(30600, 90000))
})

test_that("partial ISO datetime and time stay character", {
  expect_type(
    vport:::.realize_temporal(
      c("2014-01-02T08", "x"),
      "datetime",
      "DATETIME20."
    ),
    "character"
  )
  expect_type(
    vport:::.realize_temporal(c("8h", "9h"), "time", "TIME8."),
    "character"
  )
})

test_that(".hms_to_seconds returns NA for a malformed token", {
  expect_identical(vport:::.hms_to_seconds("08:30"), NA_real_)
})

test_that(".parse_format_str handles a name with no width", {
  expect_identical(vport:::.parse_format_str("DATE.")$name, "DATE")
  expect_identical(vport:::.parse_format_str("DATE.")$length, 0L)
})

test_that("realize then deflate round-trips a date vector exactly", {
  days <- c(0, 19725, -3653, 30000)
  back <- vport:::.deflate_temporal(
    vport:::.realize_temporal(days, "date", "DATE9."),
    "date"
  )
  expect_identical(back, days)
})
