# Tests for the json codec (codec_json.R): Dataset-JSON v1.1 round-trips, the
# meta-driven type fidelity (C1), targetDataType emit (9.A.5), decimal-as-
# string (9.A.9), vectorized ragged-row guard (C5), and the structural probe
# (E2). Internals via artoo:::; a frozen `created` keeps bytes stable.

demo_adam_spec <- function() {
  artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
}

demo_sdtm_spec <- function() {
  artoo_spec(
    cdisc_sdtm_datasets,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists
  )
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
  spec <- demo_adam_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
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
  spec <- demo_adam_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(adsl, p, created = frozen)
  back <- read_json(p)
  dcol <- names(adsl)[vapply(adsl, inherits, logical(1), "Date")][1]
  expect_s3_class(back[[dcol]], "Date")
  expect_equal(as.numeric(back[[dcol]]), as.numeric(adsl[[dcol]]))
})

test_that("DM round-trips through the generic dispatcher by extension", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_dataset(dm, p, created = frozen)
  back <- read_dataset(p)
  expect_identical(names(back), names(dm))
  expect_values_equal(back, dm)
})

# ---- byte stability ---------------------------------------------------------

test_that("a frozen created makes two writes byte-identical", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
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
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
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
  ap <- apply_spec(df, artoo_spec(dss, vars), "X", conformance = "off")
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
  ap <- apply_spec(df, artoo_spec(dss, vars), "X", conformance = "off")
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
  df$TM <- hms::hms(c(3600, NA, 7200))
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
  ap <- apply_spec(df, artoo_spec(dss, vars), "X", conformance = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  back <- read_json(p)
  expect_equal(back$I, c(1L, NA, 3L), ignore_attr = c("label", "format.sas"))
  expect_equal(
    back$B,
    c(TRUE, FALSE, NA),
    ignore_attr = c("label", "format.sas")
  )
  expect_s3_class(back$TM, "hms")
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
  ap <- apply_spec(df, artoo_spec(dss, vars), "X", conformance = "off")
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
  ap <- apply_spec(df, artoo_spec(dss, vars), "X", conformance = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  back <- read_json(p)
  expect_identical(as.character(back$DT), c("2021", "2021-03", NA))
})

# ---- empty frame ------------------------------------------------------------

test_that("a zero-row dataset round-trips with an empty rows array", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm[0, ], spec, "DM", conformance = "off")
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
  df <- set_meta(df, artoo:::.meta_from_frame(df))
  expect_snapshot(write_json(df, tempfile(fileext = ".json")), error = TRUE)
  expect_error(
    write_json(df, tempfile(fileext = ".json")),
    class = "artoo_error_type"
  )

  df2 <- data.frame(N = c(1, NaN, 3))
  df2 <- set_meta(df2, artoo:::.meta_from_frame(df2))
  expect_error(
    write_json(df2, tempfile(fileext = ".json")),
    class = "artoo_error_type"
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
  expect_error(read_json(p), class = "artoo_error_codec")
})

test_that("a non-Dataset-JSON file aborts cleanly (E2)", {
  p <- withr::local_tempfile(fileext = ".json")
  writeLines('{"a":1}', p)
  # Scrub the tempfile path by anchoring on the stable message text, so any
  # separator/drive (incl. Windows paths) collapses to '<path>'.
  scrub <- function(x) {
    sub("'[^']*' is not a Dataset-JSON", "'<path>' is not a Dataset-JSON", x)
  }
  expect_snapshot(read_json(p), error = TRUE, transform = scrub)
  expect_error(read_json(p), class = "artoo_error_codec")
})

test_that("malformed JSON aborts with artoo_error_codec", {
  p <- withr::local_tempfile(fileext = ".json")
  writeLines("{not json", p)
  expect_error(read_json(p), class = "artoo_error_codec")
})

test_that("an embedded NUL byte aborts (B5)", {
  p <- withr::local_tempfile(fileext = ".json")
  writeBin(c(charToRaw('{"a":'), as.raw(0L), charToRaw("1}")), p)
  expect_error(read_json(p), class = "artoo_error_codec")
})

test_that("a leading UTF-8 BOM is stripped on read (B5)", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
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
    class = "artoo_error_codec"
  )
})

# ---- internal helpers -------------------------------------------------------

test_that(".temporal_to_iso renders each class and keeps partial values", {
  expect_identical(
    artoo:::.temporal_to_iso(as.Date("2021-01-15"), "date", "DATE9."),
    "2021-01-15"
  )
  expect_identical(
    artoo:::.temporal_to_iso(
      as.POSIXct("2021-01-15 08:30:00", tz = "UTC"),
      "datetime",
      "DATETIME20."
    ),
    "2021-01-15T08:30:00"
  )
  expect_identical(
    artoo:::.temporal_to_iso(hms::hms(3600), "time", "TIME8."),
    "01:00:00"
  )
  # Partial values that cannot realize stay as character text, never NA.
  expect_identical(artoo:::.temporal_to_iso("2021", "date", "DATE9."), "2021")
  expect_identical(
    artoo:::.temporal_to_iso("2021-01", "datetime", "DATETIME20."),
    "2021-01"
  )
  expect_identical(artoo:::.temporal_to_iso("12:30", "time", "TIME8."), "12:30")
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
  ap <- apply_spec(df, artoo_spec(dss, vars), "X", conformance = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p)
  back <- read_json(p)
  expect_s3_class(back$DTM, "POSIXct")
  expect_equal(as.numeric(back$DTM), as.numeric(df$DTM))
})

test_that("the encode/decode default branches coerce via character", {
  call <- rlang::current_env()
  expect_identical(
    artoo:::.json_col_literals(
      c("a", NA),
      list(dataType = "weird"),
      "X",
      call
    ),
    c("\"a\"", "null")
  )
  expect_identical(
    artoo:::.json_decode_column(list("a", NULL), list(dataType = "weird")),
    c("a", NA)
  )
})

# ---- Part B: encoding (UTF-8 default + foreign-file read) -------------------

test_that("write_json/read_json round-trip a multibyte value as canonical UTF-8", {
  df <- data.frame(STUDYID = "S1", SITE = "café", stringsAsFactors = FALSE)
  p <- withr::local_tempfile(fileext = ".json")
  write_json(df, p)
  back <- read_json(p)
  expect_identical(back$SITE, "café")
  expect_identical(Encoding(back$SITE), "UTF-8")
})

test_that("read_json(encoding=) decodes a foreign (non-UTF-8) Dataset-JSON file", {
  df <- data.frame(STUDYID = "S1", SITE = "café", stringsAsFactors = FALSE)
  p <- withr::local_tempfile(fileext = ".json")
  write_json(df, p)
  # Rewrite the on-disk file as windows-1252 bytes (a non-conformant producer).
  txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
  con <- file(p, "wb")
  writeBin(charToRaw(iconv(txt, "UTF-8", "windows-1252")), con)
  close(con)
  back <- read_json(p, encoding = "windows-1252")
  expect_identical(back$SITE, "café")
})

# ---- on_invalid: UTF-8 validation parity with write_xpt --------------------
test_that("write_json gates invalid UTF-8 through on_invalid", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  dm$USUBJID[1] <- rawToChar(as.raw(c(0x63, 0xE9))) # invalid UTF-8 byte
  p <- withr::local_tempfile(fileext = ".json")
  # Default: abort, naming the offender hex-escaped (artoo_error_codec) --
  # never the old uncontrolled utf8_normalize error.
  expect_error(write_json(dm, p, created = frozen), class = "artoo_error_codec")
  # replace: warn, write a valid-UTF-8 file with ?, round-trip intact.
  expect_warning(
    write_json(dm, p, created = frozen, on_invalid = "replace"),
    class = "artoo_warning_encoding"
  )
  back <- read_json(p)
  expect_true(all(validUTF8(back$USUBJID)))
  expect_match(back$USUBJID[1], "[?]")
  # ignore: silent, byte dropped.
  p2 <- withr::local_tempfile(fileext = ".json")
  expect_no_warning(
    write_json(dm, p2, created = frozen, on_invalid = "ignore")
  )
  expect_identical(read_json(p2)$USUBJID[1], "c")
})

test_that("write_json never flags declared-latin1 or factor columns (regression)", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  lat <- rawToChar(as.raw(c(0x63, 0xE9)))
  Encoding(lat) <- "latin1"
  dm$USUBJID[1] <- lat # declared mark: transcodes cleanly under "error"
  p <- withr::local_tempfile(fileext = ".json")
  write_json(dm, p, created = frozen)
  expect_identical(read_json(p)$USUBJID[1], "cé")
  # The on_invalid gate covers character columns only; a factor column in a
  # bare frame (metadata inferred, so meta and frame agree) string-ifies
  # through the inferred dataType and round-trips as character.
  df <- data.frame(
    USUBJID = c("01-001", "01-002"),
    SEXF = factor(c("F", "M")),
    stringsAsFactors = FALSE
  )
  p2 <- withr::local_tempfile(fileext = ".json")
  expect_no_error(write_json(df, p2, created = frozen))
  expect_identical(read_json(p2)$SEXF, c("F", "M"))
})

# ---- Regression: numeric fidelity (code review 2026-06-14) ----

# Minimal one-variable spec for the numeric-fidelity regressions.
one_var_spec <- function(dt) {
  artoo_spec(
    datasets = data.frame(
      dataset = "DS",
      label = "d",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DS",
      variable = "X",
      data_type = dt,
      stringsAsFactors = FALSE
    )
  )
}

test_that("decimal columns round-trip at full precision, not 15 digits", {
  v <- c(0.1 + 0.2, 1 / 3, 1.5, 123456789.98765431)
  ap <- apply_spec(data.frame(X = v), one_var_spec("decimal"), "DS")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p, created = frozen)
  # Pre-fix as.character() wrote "0.3" and read back 0.29999999999999999.
  expect_identical(as.numeric(read_json(p)$X), v)
})

test_that("integer values above the 32-bit range survive a JSON round-trip", {
  ap <- apply_spec(
    data.frame(X = c(3e9, -3e9, 5)),
    one_var_spec("integer"),
    "DS",
    on_coercion_loss = "keep",
    conformance = "off"
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_json(ap, p, created = frozen)
  # Pre-fix as.integer() NA'd 3e9 on both write and read.
  expect_identical(as.numeric(read_json(p)$X), c(3e9, -3e9, 5))
})

test_that("a large integer read from a foreign Dataset-JSON is not NA'd", {
  p <- withr::local_tempfile(fileext = ".json")
  writeLines(
    paste0(
      '{"datasetJSONVersion":"1.1.0","columns":[{"itemOID":"IT.BIG",',
      '"name":"BIG","label":"Big","dataType":"integer"}],"rows":[[3000000000]]}'
    ),
    p
  )
  expect_identical(as.numeric(read_json(p)$BIG), 3e9)
})

test_that("Inf in a decimal column aborts instead of writing invalid JSON", {
  # Pre-fix the decimal branch only as.character()'d, so [..,"Inf"] (invalid
  # CDISC JSON) was written with no abort; the NaN/Inf gate now covers decimal.
  cm <- list(dataType = "decimal")
  expect_error(
    artoo:::.json_col_literals(c(1, Inf), cm, "X", rlang::caller_env()),
    class = "artoo_error_type"
  )
  expect_error(
    artoo:::.json_col_literals(c(1, NaN), cm, "X", rlang::caller_env()),
    class = "artoo_error_type"
  )
})
