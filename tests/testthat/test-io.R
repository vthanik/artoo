# Tests for the codec registry, the read_dataset/write_dataset dispatchers,
# vport_formats(), and the rds codec round-trip (the spine: a conformed
# frame survives a write/read trip with its vport_meta intact).

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

# ---- registry ---------------------------------------------------------------

test_that("rds is a registered read-write codec", {
  fmts <- vport:::.registered_formats()
  expect_true("rds" %in% fmts)
  codec <- vport:::.resolve_codec("rds")
  expect_identical(codec$mode, "rw")
  expect_type(codec$encode, "character")
  expect_true(is.function(vport:::.codec_fn(codec$encode)))
})

test_that(".resolve_codec aborts on an unknown format", {
  expect_error(vport:::.resolve_codec("xlsx"), class = "vport_error_codec")
})

test_that(".codec_for_ext maps extensions to formats", {
  expect_identical(vport:::.codec_for_ext("rds")$format, "rds")
  expect_error(vport:::.codec_for_ext("zzz"), class = "vport_error_codec")
})

# ---- format resolution ------------------------------------------------------

test_that("write_dataset / read_dataset resolve the format from the path", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
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
    class = "vport_error_input"
  )
})

test_that("explicit format overrides the extension", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
  path <- withr::local_tempfile(fileext = ".data")
  write_dataset(adsl, path, format = "rds")
  back <- read_dataset(path, format = "rds")
  expect_identical(get_meta(back)@columns, get_meta(adsl)@columns)
})

# ---- rds codec round-trip (the lossless invariant) --------------------------

test_that("rds round-trip preserves vport_meta exactly", {
  spec <- demo_spec()
  for (ds in spec_datasets(spec)) {
    src <- if (ds == "ADSL") cdisc_adsl else cdisc_dm
    conformed <- apply_spec(src, spec, ds, on_error = "off")
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
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
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
  expect_true(is_vport_meta(get_meta(back2)))
})

test_that("write_dataset rejects a non-data-frame x", {
  path <- withr::local_tempfile(fileext = ".rds")
  expect_error(write_dataset(list(1), path), class = "vport_error_input")
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
  expect_error(read_dataset(gone), class = "vport_error_input")
})

test_that("write_dataset refuses a read-only codec", {
  vport:::.register_codec(
    "rotest",
    encode = ".encode_rds",
    decode = ".decode_rds",
    extensions = "rotest",
    mode = "r"
  )
  withr::defer(rm("rotest", envir = vport:::.vport_codecs))
  path <- withr::local_tempfile(fileext = ".rotest")
  expect_error(write_dataset(cdisc_dm, path), class = "vport_error_codec")
})

test_that("rds write falls back to copy when rename fails", {
  testthat::local_mocked_bindings(
    file.rename = function(from, to) FALSE,
    .package = "base"
  )
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
  path <- withr::local_tempfile(fileext = ".rds")
  write_rds(adsl, path)
  expect_true(file.exists(path))
  expect_identical(get_meta(read_rds(path))@columns, get_meta(adsl)@columns)
})

# ---- vport_formats ----------------------------------------------------------

test_that("vport_formats lists each codec with read/write availability", {
  cf <- vport_formats()
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
  expect_error(read_rds(p), class = "vport_error_codec")
  expect_error(read_dataset(p), class = "vport_error_codec")
})
