# The CDISC temporal storage model: dataType date/datetime/time with no
# numeric targetDataType is ISO 8601 *text* (the --DTC convention, partial
# dates first-class); targetDataType integer/decimal (or a numeric-backed R
# class) is a SAS-epoch numeric. Regression suite for the dogfooded
# BRTHDTC failure: a character ISO date column typed "date" could not be
# written to xpt at all, and complete --DTC columns were silently realized
# to Date (changing SDTM submission shape).

# A one-dataset SDTM-flavoured spec: BRTHDTC is dataType date, RFSTDTC is
# datetime, neither carries targetDataType -> ISO text storage.
dtc_spec <- function(target = NA_character_) {
  vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = c("USUBJID", "BRTHDTC", "RFSTDTC"),
      label = c("Subject ID", "Birth Date/Time", "Reference Start"),
      data_type = c("string", "date", "datetime"),
      target_data_type = c(NA_character_, target, target),
      stringsAsFactors = FALSE
    )
  )
}

dtc_frame <- function() {
  data.frame(
    USUBJID = c("01-001", "01-002", "01-003", "01-004"),
    BRTHDTC = c("1951-12-03", "1951-12", "1951", NA),
    RFSTDTC = c(
      "2014-01-02T11:30:00",
      "2014-01-02T11:30",
      "2014-01-02",
      "2014"
    ),
    stringsAsFactors = FALSE
  )
}

# ---- the headline regression: write_xpt of character ISO --DTC ------------

test_that("write_xpt writes a character ISO date column as text (BRTHDTC regression)", {
  spec <- dtc_spec()
  dm <- apply_spec(dtc_frame(), spec, "DM", on_error = "off")

  # apply_spec must NOT promote ISO text to Date: no targetDataType.
  expect_type(dm$BRTHDTC, "character")
  expect_type(dm$RFSTDTC, "character")

  p <- withr::local_tempfile(fileext = ".xpt")
  expect_no_error(write_xpt(dm, p))
  back <- read_xpt(p)

  # Partial dates ("1951-12", "1951") survive byte-for-byte.
  expect_identical(back$BRTHDTC, dm$BRTHDTC)
  expect_identical(back$RFSTDTC, dm$RFSTDTC)
  # xpt physically stores them as character variables.
  expect_identical(get_meta(back)@columns$BRTHDTC$dataType, "string")
})

test_that("ISO-text xpt variables carry no SAS temporal display format", {
  spec <- dtc_spec()
  dm <- apply_spec(dtc_frame(), spec, "DM", on_error = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p)
  back <- read_xpt(p)
  # A DATE9. format on a character variable would corrupt SAS rendering.
  expect_null(get_meta(back)@columns$BRTHDTC$displayFormat)
})

test_that("targetDataType = integer still demands numeric storage and aborts on partials", {
  spec <- dtc_spec(target = "integer")
  dm <- apply_spec(dtc_frame(), spec, "DM", on_error = "off")
  # Partials cannot realize -> column stays character; the write must fail
  # loud (never a silent garbage date), with the actionable hint.
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(dm, p), class = "vport_error_codec")
  expect_snapshot(error = TRUE, write_xpt(dm, p))
})

test_that("targetDataType = integer realizes complete ISO text to Date and writes numerics", {
  spec <- dtc_spec(target = "integer")
  complete <- dtc_frame()
  complete$BRTHDTC <- c("1951-12-03", "1950-01-15", "1949-07-07", NA)
  complete$RFSTDTC <- c(
    "2014-01-02T11:30:00",
    "2014-01-03T08:00:00",
    "2014-01-04T09:15:00",
    NA
  )
  dm <- apply_spec(complete, spec, "DM", on_error = "off")
  expect_s3_class(dm$BRTHDTC, "Date")
  expect_s3_class(dm$RFSTDTC, "POSIXct")

  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p)
  back <- read_xpt(p)
  expect_s3_class(back$BRTHDTC, "Date")
  expect_identical(as.character(back$BRTHDTC), as.character(dm$BRTHDTC))
})

# ---- cross-format consistency ---------------------------------------------

test_that("character ISO --DTC stays text across json, ndjson, and rds", {
  spec <- dtc_spec()
  dm <- apply_spec(dtc_frame(), spec, "DM", on_error = "off")
  for (ext in c(".json", ".ndjson", ".rds")) {
    p <- withr::local_tempfile(fileext = ext)
    write_dataset(dm, p)
    back <- read_dataset(p)
    expect_identical(back$BRTHDTC, dm$BRTHDTC, info = ext)
    expect_identical(back$RFSTDTC, dm$RFSTDTC, info = ext)
    # The recorded metadata keeps the temporal dataType (no targetDataType).
    m <- get_meta(back)
    expect_identical(m@columns$BRTHDTC$dataType, "date", info = ext)
    expect_null(m@columns$BRTHDTC$targetDataType, info = ext)
  }
})

test_that("character ISO --DTC stays text through parquet", {
  skip_if_not_installed("nanoparquet")
  spec <- dtc_spec()
  dm <- apply_spec(dtc_frame(), spec, "DM", on_error = "off")
  p <- withr::local_tempfile(fileext = ".parquet")
  write_parquet(dm, p)
  back <- read_parquet(p)
  expect_identical(back$BRTHDTC, dm$BRTHDTC)
  expect_null(get_meta(back)@columns$BRTHDTC$targetDataType)
})

test_that("a Date column without spec targetDataType gets integer stamped at apply", {
  # The bundled ADSL dates are R Date and the spec types them "date" with
  # no targetDataType: the truthful exchange form is numeric, and the stamp
  # records it so every codec and sidecar agrees.
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
  m <- get_meta(adsl)
  expect_identical(m@columns$TRTSDT$targetDataType, "integer")
  expect_s3_class(adsl$TRTSDT, "Date")

  # And the json round trip preserves the Date class via that stamp.
  p <- withr::local_tempfile(fileext = ".json")
  write_json(adsl, p)
  back <- read_json(p)
  expect_s3_class(back$TRTSDT, "Date")
  expect_identical(back$TRTSDT, adsl$TRTSDT)
})

test_that("xpt read records targetDataType = integer for numeric temporals", {
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(adsl, p)
  back <- read_xpt(p)
  expect_identical(get_meta(back)@columns$TRTSDT$targetDataType, "integer")
  expect_s3_class(back$TRTSDT, "Date")
})

test_that("scaffolded temporal variables honor the storage form", {
  # No targetDataType -> ISO text -> character NA; integer -> numeric NA.
  spec <- dtc_spec()
  out <- apply_spec(
    data.frame(USUBJID = "01-001", stringsAsFactors = FALSE),
    spec,
    "DM",
    on_error = "off"
  )
  expect_type(out$BRTHDTC, "character")
  expect_true(is.na(out$BRTHDTC))

  spec_num <- dtc_spec(target = "integer")
  out_num <- apply_spec(
    data.frame(USUBJID = "01-001", stringsAsFactors = FALSE),
    spec_num,
    "DM",
    on_error = "off"
  )
  expect_type(out_num$BRTHDTC, "double")
})

# ---- iso8601_format conformance --------------------------------------------

test_that("iso8601_format accepts CDISC partial and placeholder forms", {
  ok <- c(
    "1951",
    "1951-12",
    "1951-12-03",
    "2003---15",
    "--12-15",
    NA,
    ""
  )
  expect_true(all(vport:::.iso8601_valid(ok, "date")))

  ok_dtm <- c(
    "2003",
    "2003-12",
    "2003-12-15",
    "2003-12-15T13",
    "2003-12-15T13:14",
    "2003-12-15T13:14:17",
    "2003-12-15T13:14:17.123",
    "2003-12-15T13:14:17Z",
    "2003-12-15T13:14:17+05:30",
    "2003---15T13:14",
    "2003-12-15T-:15"
  )
  expect_true(all(vport:::.iso8601_valid(ok_dtm, "datetime")))

  ok_time <- c("13", "13:14", "13:14:17", "13:14:17.5", "T13:14", "-:15")
  expect_true(all(vport:::.iso8601_valid(ok_time, "time")))
})

test_that("iso8601_format rejects non-ISO and impossible values", {
  bad <- c(
    "12NOV2019",
    "2014-13-01",
    "2014-02-30",
    "2014-12-45",
    "2014/12/01",
    "2014-1-2",
    "2014-12T13"
  )
  expect_false(any(vport:::.iso8601_valid(bad, "date")))
  expect_false(any(vport:::.iso8601_valid(
    c("2014-12T13", "2014-12-01T25:00", "2014-12-01T13:75"),
    "datetime"
  )))
  expect_false(any(vport:::.iso8601_valid(c("25", "13:75", "x"), "time")))
})

test_that("check_spec flags invalid ISO text and passes valid partials", {
  spec <- dtc_spec()
  good <- apply_spec(dtc_frame(), spec, "DM", on_error = "off")
  f <- check_spec(good, spec, "DM")
  expect_false("iso8601_format" %in% f$check)
  # And no type_mismatch: character IS the storage form for text temporals.
  expect_false("type_mismatch" %in% f$check)

  bad <- dtc_frame()
  bad$BRTHDTC[1] <- "03DEC1951"
  badc <- apply_spec(bad, spec, "DM", on_error = "off")
  f2 <- check_spec(badc, spec, "DM")
  row <- f2[f2$check == "iso8601_format", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$severity, "error")
  expect_match(row$message, "03DEC1951")
})

# ---- integer_fraction + on_lossy --------------------------------------------

frac_spec <- function() {
  vport_spec(
    data.frame(dataset = "ADVS"),
    data.frame(
      dataset = "ADVS",
      variable = c("USUBJID", "HEIGHTBL"),
      data_type = c("string", "integer"),
      stringsAsFactors = FALSE
    )
  )
}

frac_frame <- function() {
  data.frame(
    USUBJID = c("01-001", "01-002"),
    HEIGHTBL = c(162.6, 171.2),
    stringsAsFactors = FALSE
  )
}

test_that("check_spec pre-flights fractional values under an integer dataType", {
  f <- check_spec(frac_frame(), frac_spec(), "ADVS")
  row <- f[f$check == "integer_fraction", ]
  expect_identical(nrow(row), 1L)
  expect_identical(row$severity, "error")
  expect_identical(row$variable, "HEIGHTBL")
})

test_that("apply_spec aborts on truncating coercion by default (on_lossy)", {
  expect_error(
    apply_spec(frac_frame(), frac_spec(), "ADVS", on_error = "off"),
    class = "vport_error_type"
  )
  expect_snapshot(
    error = TRUE,
    apply_spec(frac_frame(), frac_spec(), "ADVS", on_error = "off")
  )
  # Opt out: the old warning behavior.
  expect_warning(
    out <- apply_spec(
      frac_frame(),
      frac_spec(),
      "ADVS",
      on_error = "off",
      on_lossy = "warn"
    ),
    class = "vport_warning_coercion"
  )
  expect_identical(out$HEIGHTBL, c(162L, 171L))
})

test_that("on_lossy = error also covers 32-bit overflow", {
  spec <- vport_spec(
    data.frame(dataset = "X"),
    data.frame(dataset = "X", variable = "BIGN", data_type = "integer")
  )
  big <- data.frame(BIGN = 3e9)
  expect_error(
    apply_spec(big, spec, "X", on_error = "off"),
    class = "vport_error_type"
  )
})
