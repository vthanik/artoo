# Tests for the json codec (codec_json.R): Dataset-JSON v1.1 round-trips, the
# meta-driven type fidelity (C1), targetDataType emit (9.A.5), decimal-as-
# string (9.A.9), vectorized ragged-row guard (C5), and the structural probe
# (E2). Internals via vport:::; a frozen `created` keeps bytes stable.

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

frozen <- as.POSIXct("2020-01-01", tz = "UTC")

# Compare column VALUES across a round-trip (labels live in meta, not columns).
expect_values_equal <- function(back, orig) {
  for (nm in names(orig)) {
    expect_equal(as.character(back[[nm]]), as.character(orig[[nm]]), info = nm)
  }
}

# ---- round-trip on bundled CDISC data --------------------------------------

test_that("write_json/read_json round-trips ADSL values and metadata", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(adsl, p, created = frozen)
  back <- read_json(p)

  expect_identical(names(back), names(adsl))
  expect_values_equal(back, adsl)
  expect_identical(get_meta(back)@columns, get_meta(adsl)@columns)
  expect_identical(get_meta(back)@dataset$name, "ADSL")
  expect_identical(get_meta(back)@dataset$records, nrow(adsl))
})

test_that("read_json realizes Date columns from ISO strings", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(adsl, p, created = frozen)
  back <- read_json(p)
  dcol <- names(adsl)[vapply(adsl, inherits, logical(1), "Date")][1]
  expect_s3_class(back[[dcol]], "Date")
  expect_equal(as.numeric(back[[dcol]]), as.numeric(adsl[[dcol]]))
})

test_that("DM round-trips through the generic dispatcher by extension", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_dataset(dm, p, created = frozen)
  back <- read_dataset(p)
  expect_identical(names(back), names(dm))
  expect_values_equal(back, dm)
})

# ---- byte stability ---------------------------------------------------------

test_that("a frozen created makes two writes byte-identical", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", on_error = "off")
  p1 <- withr::local_tempfile(fileext = ".json")
  p2 <- withr::local_tempfile(fileext = ".json")
  write_json(dm, p1, created = frozen)
  write_json(dm, p2, created = frozen)
  expect_identical(
    readBin(p1, "raw", file.info(p1)$size),
    readBin(p2, "raw", file.info(p2)$size)
  )
})

test_that("the file carries datasetJSONCreationDateTime from created", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(dm, p, created = frozen)
  raw <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  expect_identical(raw$datasetJSONCreationDateTime, "2020-01-01T00:00:00")
  expect_identical(raw$datasetJSONVersion, "1.1.0")
})

# ---- type fidelity ----------------------------------------------------------

test_that("decimal rides as an exact string end to end", {
  df <- data.frame(D = c("0.10", "100.000", NA), stringsAsFactors = FALSE)
  vars <- data.frame(
    dataset = "X",
    variable = "D",
    label = "dec",
    data_type = "decimal",
    length = NA_integer_,
    order = 1L,
    stringsAsFactors = FALSE
  )
  dss <- data.frame(dataset = "X", label = "x", stringsAsFactors = FALSE)
  ap <- apply_spec(df, vport_spec(dss, vars), "X", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  back <- read_json(p)
  expect_identical(as.character(back$D), c("0.10", "100.000", NA))
})

test_that("a whole-number double stays double on re-read (C1)", {
  df <- data.frame(N = c(1, 2, 3))
  vars <- data.frame(
    dataset = "X",
    variable = "N",
    label = "num",
    data_type = "double",
    length = NA_integer_,
    order = 1L,
    stringsAsFactors = FALSE
  )
  dss <- data.frame(dataset = "X", label = "x", stringsAsFactors = FALSE)
  ap <- apply_spec(df, vport_spec(dss, vars), "X", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  back <- read_json(p)
  expect_true(is.double(back$N))
  # set_meta() now projects the column label/format.sas as attrs (haven
  # parity); ignore just those two, the value+type are asserted strictly.
  expect_equal(back$N, c(1, 2, 3), ignore_attr = c("label", "format.sas"))
})

test_that("integer, boolean, and time columns round-trip by type", {
  df <- data.frame(I = c(1L, NA, 3L), B = c(TRUE, FALSE, NA))
  df$TM <- vport_time(c(3600, NA, 7200))
  vars <- data.frame(
    dataset = "X",
    variable = c("I", "B", "TM"),
    label = c("i", "b", "t"),
    data_type = c("integer", "boolean", "time"),
    length = NA_integer_,
    order = 1:3,
    stringsAsFactors = FALSE
  )
  dss <- data.frame(dataset = "X", label = "x", stringsAsFactors = FALSE)
  ap <- apply_spec(df, vport_spec(dss, vars), "X", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  back <- read_json(p)
  expect_equal(back$I, c(1L, NA, 3L), ignore_attr = c("label", "format.sas"))
  expect_equal(
    back$B,
    c(TRUE, FALSE, NA),
    ignore_attr = c("label", "format.sas")
  )
  expect_s3_class(back$TM, "vport_time")
  expect_identical(unclass(back$TM), unclass(ap$TM))
})

test_that("a date with targetDataType integer rides as a number (9.A.5)", {
  df <- data.frame(DT = as.Date(c("2021-01-15", NA, "2021-03-01")))
  vars <- data.frame(
    dataset = "X",
    variable = "DT",
    label = "d",
    data_type = "date",
    target_data_type = "integer",
    display_format = "DATE9.",
    length = NA_integer_,
    order = 1L,
    stringsAsFactors = FALSE
  )
  dss <- data.frame(dataset = "X", label = "x", stringsAsFactors = FALSE)
  ap <- apply_spec(df, vport_spec(dss, vars), "X", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  raw <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  # First cell is a SAS day number, not an ISO string.
  expect_true(is.numeric(raw$rows[[1]][[1]]))
  back <- read_json(p)
  expect_s3_class(back$DT, "Date")
  expect_equal(as.numeric(back$DT), as.numeric(df$DT))
})

test_that("a partial ISO date stays a character string", {
  df <- data.frame(DT = c("2021", "2021-03", NA), stringsAsFactors = FALSE)
  vars <- data.frame(
    dataset = "X",
    variable = "DT",
    label = "d",
    data_type = "date",
    length = NA_integer_,
    order = 1L,
    stringsAsFactors = FALSE
  )
  dss <- data.frame(dataset = "X", label = "x", stringsAsFactors = FALSE)
  ap <- apply_spec(df, vport_spec(dss, vars), "X", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  back <- read_json(p)
  expect_identical(as.character(back$DT), c("2021", "2021-03", NA))
})

# ---- empty frame ------------------------------------------------------------

test_that("a zero-row dataset round-trips with an empty rows array", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm[0, ], spec, "DM", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(dm, p, created = frozen)
  raw <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  expect_length(raw$rows, 0L)
  back <- read_json(p)
  expect_identical(nrow(back), 0L)
  expect_identical(names(back), names(dm))
})

# ---- error paths ------------------------------------------------------------

test_that("NaN and Inf abort the write (C2)", {
  df <- data.frame(N = c(1, Inf, 3))
  df <- set_meta(df, vport:::.meta_from_frame(df))
  expect_snapshot(write_json(df, tempfile(fileext = ".json")), error = TRUE)
  expect_error(
    write_json(df, tempfile(fileext = ".json")),
    class = "vport_error_type"
  )

  df2 <- data.frame(N = c(1, NaN, 3))
  df2 <- set_meta(df2, vport:::.meta_from_frame(df2))
  expect_error(
    write_json(df2, tempfile(fileext = ".json")),
    class = "vport_error_type"
  )
})

test_that("a ragged row aborts at its index (C5)", {
  p <- withr::local_tempfile(fileext = ".json")
  obj <- list(
    datasetJSONVersion = "1.1.0",
    itemGroupOID = "IG.X",
    name = "X",
    columns = list(
      list(itemOID = "a", name = "A", dataType = "integer"),
      list(itemOID = "b", name = "B", dataType = "integer")
    ),
    rows = list(list(1L, 2L), list(3L))
  )
  writeLines(jsonlite::toJSON(obj, auto_unbox = TRUE), p)
  expect_error(read_json(p), class = "vport_error_codec")
})

test_that("a non-Dataset-JSON file aborts cleanly (E2)", {
  p <- withr::local_tempfile(fileext = ".json")
  writeLines('{"a":1}', p)
  scrub <- function(x) gsub("'/[^']*\\.json'", "'<path>'", x)
  expect_snapshot(read_json(p), error = TRUE, transform = scrub)
  expect_error(read_json(p), class = "vport_error_codec")
})

test_that("malformed JSON aborts with vport_error_codec", {
  p <- withr::local_tempfile(fileext = ".json")
  writeLines("{not json", p)
  expect_error(read_json(p), class = "vport_error_codec")
})

test_that("an embedded NUL byte aborts (B5)", {
  p <- withr::local_tempfile(fileext = ".json")
  writeBin(c(charToRaw('{"a":'), as.raw(0L), charToRaw("1}")), p)
  expect_error(read_json(p), class = "vport_error_codec")
})

test_that("a leading UTF-8 BOM is stripped on read (B5)", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(dm, p, created = frozen)
  body <- readBin(p, "raw", file.info(p)$size)
  withbom <- withr::local_tempfile(fileext = ".json")
  writeBin(c(as.raw(c(0xEF, 0xBB, 0xBF)), body), withbom)
  back <- read_json(withbom)
  expect_identical(names(back), names(dm))
})

test_that("writing a zero-column frame aborts", {
  df <- data.frame(a = 1:3)[, FALSE, drop = FALSE]
  expect_error(
    write_json(df, tempfile(fileext = ".json")),
    class = "vport_error_codec"
  )
})

# ---- internal helpers -------------------------------------------------------

test_that(".temporal_to_iso renders each class and keeps partial values", {
  expect_identical(
    vport:::.temporal_to_iso(as.Date("2021-01-15"), "date", "DATE9."),
    "2021-01-15"
  )
  expect_identical(
    vport:::.temporal_to_iso(
      as.POSIXct("2021-01-15 08:30:00", tz = "UTC"),
      "datetime",
      "DATETIME20."
    ),
    "2021-01-15T08:30:00"
  )
  expect_identical(
    vport:::.temporal_to_iso(vport_time(3600), "time", "TIME8."),
    "01:00:00"
  )
  # Partial values that cannot realize stay as character text, never NA.
  expect_identical(vport:::.temporal_to_iso("2021", "date", "DATE9."), "2021")
  expect_identical(
    vport:::.temporal_to_iso("2021-01", "datetime", "DATETIME20."),
    "2021-01"
  )
  expect_identical(vport:::.temporal_to_iso("12:30", "time", "TIME8."), "12:30")
})

test_that("an end-to-end datetime column round-trips as POSIXct", {
  df <- data.frame(
    DTM = as.POSIXct(
      c("2021-01-15 08:30:00", NA, "2021-03-01 12:00:00"),
      tz = "UTC"
    )
  )
  vars <- data.frame(
    dataset = "X",
    variable = "DTM",
    label = "dtm",
    data_type = "datetime",
    display_format = "DATETIME20.",
    length = NA_integer_,
    order = 1L,
    stringsAsFactors = FALSE
  )
  dss <- data.frame(dataset = "X", label = "x", stringsAsFactors = FALSE)
  ap <- apply_spec(df, vport_spec(dss, vars), "X", on_error = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  back <- read_json(p)
  expect_s3_class(back$DTM, "POSIXct")
  expect_equal(as.numeric(back$DTM), as.numeric(df$DTM))
})

test_that("the encode/decode default branches coerce via character", {
  call <- rlang::current_env()
  expect_identical(
    vport:::.json_encode_column(
      c("a", NA),
      list(dataType = "weird"),
      "X",
      call
    ),
    list("a", NULL)
  )
  expect_identical(
    vport:::.json_decode_column(list("a", NULL), list(dataType = "weird")),
    c("a", NA)
  )
})
