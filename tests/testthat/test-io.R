# Tests for the codec registry, the read_dataset/write_dataset dispatchers,
# artoo_formats(), and the rds codec round-trip (the spine: a conformed
# frame survives a write/read trip with its artoo_meta intact).

demo_spec <- function() {
  artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

# ---- registry ---------------------------------------------------------------

test_that("rds is a registered read-write codec", {
  fmts <- artoo:::.registered_formats()
  expect_true("rds" %in% fmts)
  codec <- artoo:::.resolve_codec("rds")
  expect_identical(codec$mode, "rw")
  expect_type(codec$encode, "character")
  expect_true(is.function(artoo:::.codec_fn(codec$encode)))
})

test_that(".resolve_codec aborts on an unknown format", {
  expect_error(artoo:::.resolve_codec("xlsx"), class = "artoo_error_codec")
})

test_that(".codec_for_ext maps extensions to formats", {
  expect_identical(artoo:::.codec_for_ext("rds")$format, "rds")
  expect_error(artoo:::.codec_for_ext("zzz"), class = "artoo_error_codec")
})

# ---- format resolution ------------------------------------------------------

test_that("write_dataset / read_dataset resolve the format from the path", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  path <- withr::local_tempfile(fileext = ".rds")

  write_dataset(adsl, path)
  expect_true(file.exists(path))
  back <- read_dataset(path)
  expect_s3_class(back, "data.frame")
})

test_that("an unknown extension with no format aborts", {
  path <- withr::local_tempfile(fileext = ".zzz")
  expect_error(
    write_dataset(cdisc_dm, path),
    class = "artoo_error_input"
  )
})

test_that("explicit format overrides the extension", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  path <- withr::local_tempfile(fileext = ".data")
  write_dataset(adsl, path, format = "rds")
  back <- read_dataset(path, format = "rds")
  expect_identical(get_meta(back)@columns, get_meta(adsl)@columns)
})

# ---- rds codec round-trip (the lossless invariant) --------------------------

test_that("rds round-trip preserves artoo_meta exactly", {
  spec <- demo_spec()
  for (ds in spec_datasets(spec)) {
    src <- if (ds == "ADSL") cdisc_adsl else cdisc_dm
    conformed <- apply_spec(src, spec, ds, conformance = "off")
    path <- withr::local_tempfile(fileext = ".rds")
    write_rds(conformed, path)
    back <- read_rds(path)
    expect_identical(
      get_meta(back)@columns,
      get_meta(conformed)@columns,
      info = ds
    )
    expect_identical(
      get_meta(back)@dataset,
      get_meta(conformed)@dataset,
      info = ds
    )
  }
})

test_that("rds round-trip preserves the data values", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  path <- withr::local_tempfile(fileext = ".rds")
  write_rds(adsl, path)
  back <- read_rds(path)
  expect_equal(as.data.frame(back), as.data.frame(adsl))
})

test_that("write_rds on a bare frame round-trips data and infers metadata", {
  path <- withr::local_tempfile(fileext = ".rds")
  write_rds(cdisc_dm, path)
  back <- read_rds(path)
  # data values round-trip (compare ignoring the now-attached metadata_json)
  attr(back, "metadata_json") <- NULL
  expect_equal(as.data.frame(back), as.data.frame(cdisc_dm))
  # and a bare frame now carries metadata derived from its columns
  back2 <- read_rds(path)
  expect_true(is_artoo_meta(get_meta(back2)))
})

test_that("write_dataset rejects a non-data-frame x", {
  path <- withr::local_tempfile(fileext = ".rds")
  expect_error(write_dataset(list(1), path), class = "artoo_error_input")
})

test_that("read_rds of a plain saveRDS file returns the bare data frame", {
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(cdisc_dm, path) # no metadata_json attr
  back <- read_rds(path)
  expect_s3_class(back, "data.frame")
  expect_null(attr(back, "metadata_json", exact = TRUE))
})

test_that("read_dataset aborts when the file does not exist", {
  gone <- withr::local_tempfile(fileext = ".rds")
  expect_error(read_dataset(gone), class = "artoo_error_input")
})

test_that("write_dataset refuses a read-only codec", {
  artoo:::.register_codec(
    "rotest",
    encode = ".encode_rds",
    decode = ".decode_rds",
    extensions = "rotest",
    mode = "r"
  )
  withr::defer(rm("rotest", envir = artoo:::.artoo_codecs))
  path <- withr::local_tempfile(fileext = ".rotest")
  expect_error(write_dataset(cdisc_dm, path), class = "artoo_error_codec")
})

test_that("rds write falls back to copy when rename fails", {
  testthat::local_mocked_bindings(
    file.rename = function(from, to) FALSE,
    .package = "base"
  )
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  path <- withr::local_tempfile(fileext = ".rds")
  write_rds(adsl, path)
  expect_true(file.exists(path))
  expect_identical(get_meta(read_rds(path))@columns, get_meta(adsl)@columns)
})

# ---- artoo_formats ----------------------------------------------------------

test_that("artoo_formats lists each codec with read/write availability", {
  cf <- artoo_formats()
  expect_s3_class(cf, "data.frame")
  expect_true(all(c("format", "read", "write") %in% names(cf)))
  expect_true("rds" %in% cf$format)
})

# ---- review 2026-06: dots hygiene, return convention, payload validation ----

test_that("write_* returns the input data invisibly (review D1)", {
  # readr/haven convention: a write sits mid-pipeline, so it hands back the
  # data, not the path.
  df <- data.frame(SUBJ = "A", stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "T"
  p <- withr::local_tempfile(fileext = ".xpt")
  vis <- withVisible(write_xpt(df, p))
  expect_false(vis$visible)
  expect_identical(vis$value, df)

  p2 <- withr::local_tempfile(fileext = ".rds")
  vis2 <- withVisible(write_rds(cdisc_dm, p2))
  expect_false(vis2$visible)
  expect_identical(vis2$value, cdisc_dm)
})

test_that("a misspelled codec argument errors instead of being swallowed (review B8)", {
  # write_xpt(verison = 8) used to silently write v5.
  df <- data.frame(SUBJ = "A", stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "T"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p, verison = 8), "unused argument")
  write_xpt(df, p)
  expect_error(read_xpt(p, encodng = "latin1"), "unused argument")
  expect_error(write_rds(cdisc_dm, p, compress = "xz"), "unused argument")
  expect_error(
    write_dataset(df, p, format = "xpt", verison = 8),
    "unused argument"
  )
})

test_that("`call` cannot be smuggled through write_dataset dots (review B8)", {
  df <- data.frame(SUBJ = "A", stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "T"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_dataset(df, p, format = "xpt", call = emptyenv()))
})

test_that("read_rds refuses a non-data-frame payload (review D2)", {
  # The docs promise a data frame; an arbitrary serialized object must be a
  # classed refusal, not a silent passthrough.
  p <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(a = 1), p)
  expect_error(read_rds(p), class = "artoo_error_codec")
  expect_error(read_dataset(p), class = "artoo_error_codec")
})

# ---- Wave 3: universal partial reads (the generic filter is the authority) ---

test_that("partial-read args are type-validated before any decode runs", {
  # The payload is not a data frame, so a decode that ran first would raise
  # artoo_error_codec; validation winning proves it runs ahead of decode.
  p <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(a = 1), p)
  expect_error(read_dataset(p, n_max = -1), class = "artoo_error_input")
  expect_error(read_dataset(p, n_max = NA), class = "artoo_error_input")
  expect_error(read_dataset(p, col_select = 1L), class = "artoo_error_input")
})

test_that("n_max = 0 returns an empty frame and syncs the record count", {
  p <- withr::local_tempfile(fileext = ".rds")
  write_rds(cdisc_dm, p)
  back <- read_rds(p, n_max = 0)
  expect_identical(nrow(back), 0L)
  expect_identical(get_meta(back)@dataset$records, 0L)
})

test_that("col_select returns file order, not the requested order", {
  p <- withr::local_tempfile(fileext = ".rds")
  write_rds(cdisc_dm, p)
  pick <- rev(names(cdisc_dm)[1:3]) # requested reversed
  back <- read_rds(p, col_select = pick)
  expect_identical(names(back), names(cdisc_dm)[1:3]) # file order
})

test_that("col_select with an unknown name aborts artoo_error_input (rds, json)", {
  pr <- withr::local_tempfile(fileext = ".rds")
  write_rds(cdisc_dm, pr)
  expect_error(read_rds(pr, col_select = "NOPE"), class = "artoo_error_input")
  pj <- withr::local_tempfile(fileext = ".json")
  write_json(cdisc_dm, pj)
  expect_error(read_json(pj, col_select = "NOPE"), class = "artoo_error_input")
})

test_that("selecting every column in file order equals a full read (idempotent)", {
  p <- withr::local_tempfile(fileext = ".rds")
  write_rds(cdisc_dm, p)
  full <- read_rds(p)
  sel <- read_rds(p, col_select = names(cdisc_dm))
  expect_identical(full, sel)
})

test_that(".meta_select_columns recomputes keys, dropping removed key columns", {
  cols <- list(
    A = list(
      itemOID = "IT.T.A",
      name = "A",
      dataType = "string",
      keySequence = 1L
    ),
    B = list(
      itemOID = "IT.T.B",
      name = "B",
      dataType = "string",
      keySequence = 2L
    ),
    C = list(itemOID = "IT.T.C", name = "C", dataType = "float")
  )
  ds <- artoo:::.assemble_dataset_meta(
    itemGroupOID = "IG.T",
    name = "T",
    keys = c("A", "B")
  )
  meta <- artoo:::artoo_meta_class(dataset = ds, columns = cols)
  red <- artoo:::.meta_select_columns(meta, c("B", "C"))
  expect_identical(red@dataset$keys, "B")
  expect_named(red@columns, c("B", "C"))
})

test_that("json honors col_select and n_max via the generic filter", {
  p <- withr::local_tempfile(fileext = ".json")
  write_json(cdisc_dm, p)
  back <- read_json(p, col_select = names(cdisc_dm)[1:2], n_max = 3)
  expect_identical(names(back), names(cdisc_dm)[1:2])
  expect_identical(nrow(back), 3L)
})

test_that("parquet honors col_select (native projection) and n_max", {
  skip_if_not_installed("nanoparquet")
  p <- withr::local_tempfile(fileext = ".parquet")
  write_parquet(cdisc_dm, p)
  back <- read_parquet(p, col_select = rev(names(cdisc_dm)[1:3]), n_max = 4)
  expect_identical(names(back), names(cdisc_dm)[1:3]) # file order despite native
  expect_identical(nrow(back), 4L)
})

test_that("col_select works on a foreign parquet with no artoo metadata", {
  skip_if_not_installed("nanoparquet")
  df <- data.frame(A = 1:3, B = 4:6, C = 7:9)
  p <- withr::local_tempfile(fileext = ".parquet")
  nanoparquet::write_parquet(df, p)
  back <- read_parquet(p, col_select = c("C", "A"))
  expect_identical(names(back), c("A", "C")) # file order
  # The synthesized meta is narrowed to the kept columns like any other meta.
  expect_identical(names(get_meta(back)@columns), c("A", "C"))
})

# ---- Part B: rds encoding (faithful default + foreign read) -----------------

test_that("rds round-trips a multibyte value faithfully", {
  df <- data.frame(STUDYID = "S1", SITE = "café", stringsAsFactors = FALSE)
  path <- withr::local_tempfile(fileext = ".rds")
  write_rds(df, path)
  back <- read_rds(path)
  expect_identical(back$SITE, "café")
})

test_that("write_rds(encoding=) records the source charset", {
  df <- data.frame(STUDYID = "S1", SITE = "café", stringsAsFactors = FALSE)
  path <- withr::local_tempfile(fileext = ".rds")
  write_rds(df, path, encoding = "windows-1252")
  back <- read_rds(path)
  expect_identical(get_meta(back)@dataset$encoding, "windows-1252")
})

test_that("read_rds(encoding=) transcodes a foreign byte column; default stays faithful", {
  w1252 <- iconv("café", "UTF-8", "windows-1252")
  df <- data.frame(STUDYID = "S1", SITE = w1252, stringsAsFactors = FALSE)
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(df, path) # plain rds, raw bytes
  with_enc <- read_rds(path, encoding = "windows-1252")
  expect_identical(with_enc$SITE, "café")
  # default read is faithful: leaves the raw byte untranscoded.
  faithful <- read_rds(path)
  expect_identical(charToRaw(faithful$SITE), charToRaw(w1252))
})

test_that("read_rds(encoding=) preserves a column label through the transcode", {
  col <- c("a", "b")
  attr(col, "label") <- "Site"
  df <- data.frame(STUDYID = c("S1", "S2"), stringsAsFactors = FALSE)
  df$SITE <- col
  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(df, path)
  back <- read_rds(path, encoding = "windows-1252") # forces .recode_col
  expect_identical(attr(back$SITE, "label"), "Site")
})
