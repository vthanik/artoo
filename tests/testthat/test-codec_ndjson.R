# The NDJSON codec: CDISC Dataset-JSON v1.1, newline-delimited variant.
# Line 1 is the metadata object (everything a .json file carries except
# `rows`); each subsequent line is one row array. Bounded memory in both
# directions: the writer streams slabs, the reader accumulates per slab.

test_that("ndjson round-trips the torture frame losslessly", {
  src <- .torture_frame()
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(src, p)
  back <- read_ndjson(p)
  expect_lossless(src, back, via = "ndjson")
})

test_that("the file is one JSON object per line, meta first", {
  df <- data.frame(
    USUBJID = c("01-001", "01-002"),
    AVAL = c(1.5, NA),
    stringsAsFactors = FALSE
  )
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  lines <- readLines(p)
  expect_length(lines, 3L)
  meta_line <- jsonlite::fromJSON(lines[1], simplifyVector = FALSE)
  expect_identical(meta_line$datasetJSONVersion, "1.1.0")
  expect_false("rows" %in% names(meta_line))
  row1 <- jsonlite::fromJSON(lines[2], simplifyVector = FALSE)
  expect_identical(row1[[1]], "01-001")
  row2 <- jsonlite::fromJSON(lines[3], simplifyVector = FALSE)
  expect_null(row2[[2]])
})

test_that("ndjson is byte-stable under a frozen created", {
  df <- data.frame(USUBJID = "01-001", AVAL = 1.5, stringsAsFactors = FALSE)
  frozen <- as.POSIXct("2024-01-15 10:30:00", tz = "UTC")
  p1 <- withr::local_tempfile(fileext = ".ndjson")
  p2 <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p1, created = frozen)
  write_ndjson(df, p2, created = frozen)
  expect_identical(
    readBin(p1, "raw", file.info(p1)$size),
    readBin(p2, "raw", file.info(p2)$size)
  )
})

test_that("n_max reads only the requested rows", {
  df <- data.frame(ID = sprintf("S-%03d", 1:50), AVAL = as.numeric(1:50))
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  withr::local_options(artoo.json_slab_rows = 7L)
  part <- read_ndjson(p, n_max = 10)
  expect_identical(nrow(part), 10L)
  expect_identical(part$ID, df$ID[1:10])
  expect_identical(get_meta(part)@dataset$records, 10L)
})

test_that("col_select narrows columns with the generic filter", {
  df <- data.frame(A = 1:3, B = c("x", "y", "z"), C = c(0.5, NA, 2.5))
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  part <- read_ndjson(p, col_select = c("C", "A"))
  expect_identical(names(part), c("A", "C"))
  expect_error(
    read_ndjson(p, col_select = "NOPE"),
    class = "artoo_error_input"
  )
})

test_that("a ragged row aborts with the row number", {
  df <- data.frame(A = 1:2, B = c("x", "y"))
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  lines <- readLines(p)
  lines[3] <- "[1]" # row 2 loses a cell
  writeLines(lines, p)
  expect_error(read_ndjson(p), class = "artoo_error_codec")
})

test_that("a non-Dataset-JSON first line aborts cleanly", {
  p <- withr::local_tempfile(fileext = ".ndjson")
  writeLines(c("{\"foo\": 1}", "[1,2]"), p)
  expect_error(read_ndjson(p), class = "artoo_error_codec")
  writeLines("not json at all", p)
  expect_error(read_ndjson(p), class = "artoo_error_codec")
})

test_that("a 0-row frame round-trips with typed columns", {
  df <- data.frame(USUBJID = character(0), AVAL = numeric(0))
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  back <- read_ndjson(p)
  expect_identical(nrow(back), 0L)
  expect_type(back$USUBJID, "character")
  expect_type(back$AVAL, "double")
})

test_that("special missings and the _artoo block ride line 1", {
  df <- data.frame(AENDY = c(10, NA, NA))
  attr(df$AENDY, "sas_missing") <- c(NA, ".A", NA)
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  meta_line <- jsonlite::fromJSON(readLines(p)[1], simplifyVector = FALSE)
  expect_identical(
    unlist(meta_line[["_artoo"]]$specialMissings$AENDY$tags),
    ".A"
  )
  back <- read_ndjson(p)
  expect_identical(attr(back$AENDY, "sas_missing"), c(NA, ".A", NA))
})

test_that("write_ndjson(strict = TRUE) suppresses _artoo with a warning", {
  df <- data.frame(AENDY = c(10, NA))
  attr(df$AENDY, "sas_missing") <- c(NA, ".A")
  p <- withr::local_tempfile(fileext = ".ndjson")
  expect_warning(
    write_ndjson(df, p, strict = TRUE),
    class = "artoo_warning_codec"
  )
  meta_line <- jsonlite::fromJSON(readLines(p)[1], simplifyVector = FALSE)
  expect_false("_artoo" %in% names(meta_line))
})

# ---- gz transparency (json + ndjson) ----------------------------------------

test_that("a .ndjson.gz round-trips transparently", {
  src <- .torture_frame()
  p <- withr::local_tempfile(fileext = ".ndjson.gz")
  write_ndjson(src, p)
  # The bytes on disk are gzip.
  head2 <- readBin(p, "raw", 2L)
  expect_identical(head2, as.raw(c(0x1F, 0x8B)))
  expect_lossless(src, read_ndjson(p), via = "ndjson.gz")
  # And the generic dispatcher resolves the double extension.
  expect_lossless(src, read_dataset(p), via = "ndjson.gz dispatch")
})

test_that("a .json.gz round-trips transparently", {
  src <- .torture_frame()
  p <- withr::local_tempfile(fileext = ".json.gz")
  write_dataset(src, p)
  head2 <- readBin(p, "raw", 2L)
  expect_identical(head2, as.raw(c(0x1F, 0x8B)))
  expect_lossless(src, read_dataset(p), via = "json.gz")
})

test_that("gz is refused for formats that do not stream text", {
  df <- data.frame(A = 1)
  p <- withr::local_tempfile(fileext = ".xpt.gz")
  expect_error(write_dataset(df, p), class = "artoo_error_input")
})

# ---- coverage of the guard branches -----------------------------------------

test_that("encode without metadata aborts (0-column frame)", {
  df <- data.frame()
  p <- withr::local_tempfile(fileext = ".ndjson")
  expect_error(write_ndjson(df, p), class = "artoo_error_codec")
})

test_that("an empty file and a BOM-prefixed file are handled", {
  p <- withr::local_tempfile(fileext = ".ndjson")
  file.create(p)
  expect_error(read_ndjson(p), class = "artoo_error_codec")

  # A BOM before the metadata line is stripped, not a parse error.
  df <- data.frame(A = 1:2)
  write_ndjson(df, p)
  lines <- readLines(p)
  con <- file(p, "wb")
  writeBin(
    c(
      as.raw(c(0xEF, 0xBB, 0xBF)),
      charToRaw(paste0(
        paste(lines, collapse = "\n"),
        "\n"
      ))
    ),
    con
  )
  close(con)
  back <- read_ndjson(p)
  expect_identical(back$A, 1:2)
})

test_that("a row line that is not JSON aborts with the row range", {
  df <- data.frame(A = 1:3)
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  lines <- readLines(p)
  lines[3] <- "[1,}garbage"
  writeLines(lines, p)
  expect_error(read_ndjson(p), class = "artoo_error_codec")
})

test_that("n_max larger than the file reads everything", {
  df <- data.frame(A = 1:5)
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  expect_identical(nrow(read_ndjson(p, n_max = 100)), 5L)
})

test_that("interior blank lines are tolerated", {
  df <- data.frame(A = 1:3)
  p <- withr::local_tempfile(fileext = ".ndjson")
  write_ndjson(df, p)
  lines <- readLines(p)
  writeLines(c(lines[1], lines[2], "", lines[3], lines[4], ""), p)
  withr::local_options(artoo.json_slab_rows = 2L)
  back <- read_ndjson(p)
  expect_identical(back$A, 1:3)
})

test_that("a failed encode leaves any prior ndjson untouched", {
  p <- withr::local_tempfile(fileext = ".ndjson")
  df <- data.frame(A = 1:2)
  write_ndjson(df, p)
  before <- readBin(p, "raw", file.info(p)$size)
  bad <- data.frame(AVAL = c(1, NaN))
  expect_error(write_ndjson(bad, p), class = "artoo_error_type")
  expect_identical(readBin(p, "raw", file.info(p)$size), before)
})

test_that("the jsonl extension resolves to the ndjson codec", {
  df <- data.frame(A = 1:2)
  p <- withr::local_tempfile(fileext = ".jsonl")
  write_dataset(df, p)
  expect_identical(read_dataset(p)$A, 1:2)
})
