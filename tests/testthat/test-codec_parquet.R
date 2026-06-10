# Tests for the parquet codec (codec_parquet.R): native data via nanoparquet
# plus the metadata_json sidecar, meta-first temporal realize on read (D1),
# and graceful degrade for a foreign parquet with no sidecar (9.B). Needs
# nanoparquet; skipped where absent.

skip_if_not_installed("nanoparquet")

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

expect_values_equal <- function(back, orig) {
  for (nm in names(orig)) {
    expect_equal(as.character(back[[nm]]), as.character(orig[[nm]]), info = nm)
  }
}

# ---- round-trip on bundled CDISC data --------------------------------------

test_that("write_parquet/read_parquet round-trips ADSL values and metadata", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", check = "off")
  p <- withr::local_tempfile(fileext = ".parquet")
  write_parquet(adsl, p)
  back <- read_parquet(p)

  expect_identical(names(back), names(adsl))
  expect_values_equal(back, adsl)
  expect_identical(get_meta(back)@columns, get_meta(adsl)@columns)
  expect_identical(get_meta(back)@dataset$name, "ADSL")
  expect_identical(get_meta(back)@dataset$records, nrow(adsl))
})

test_that("read_parquet realizes Date columns natively", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", check = "off")
  p <- withr::local_tempfile(fileext = ".parquet")
  write_parquet(adsl, p)
  back <- read_parquet(p)
  dcol <- names(adsl)[vapply(adsl, inherits, logical(1), "Date")][1]
  expect_s3_class(back[[dcol]], "Date")
  expect_equal(as.numeric(back[[dcol]]), as.numeric(adsl[[dcol]]))
})

test_that("DM round-trips through the generic dispatcher by extension", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", check = "off")
  p <- withr::local_tempfile(fileext = ".parquet")
  write_dataset(dm, p)
  back <- read_dataset(p)
  expect_identical(names(back), names(dm))
  expect_values_equal(back, dm)
})

# ---- decimal + time fidelity ------------------------------------------------

test_that("decimal stays an exact string and time becomes vport_time", {
  df <- data.frame(D = c("0.10", "100.000", NA), stringsAsFactors = FALSE)
  df$TM <- vport_time(c(3600, NA, 7200))
  vars <- data.frame(
    dataset = "X",
    variable = c("D", "TM"),
    label = c("dec", "t"),
    data_type = c("decimal", "time"),
    length = NA_integer_,
    order = 1:2,
    stringsAsFactors = FALSE
  )
  dss <- data.frame(dataset = "X", label = "x", stringsAsFactors = FALSE)
  ap <- apply_spec(df, vport_spec(dss, vars), "X", check = "off")
  p <- withr::local_tempfile(fileext = ".parquet")
  write_parquet(ap, p)
  back <- read_parquet(p)
  expect_identical(as.character(back$D), c("0.10", "100.000", NA))
  expect_s3_class(back$TM, "vport_time")
  expect_identical(unclass(back$TM), unclass(ap$TM))
})

# ---- the metadata_json sidecar ----------------------------------------------

test_that("the sidecar is embedded under the metadata_json key", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", check = "off")
  p <- withr::local_tempfile(fileext = ".parquet")
  write_parquet(dm, p)
  kv <- nanoparquet::read_parquet_metadata(
    p
  )$file_meta_data$key_value_metadata[[1]]
  expect_true("metadata_json" %in% kv$key)
  json <- kv$value[kv$key == "metadata_json"]
  expect_identical(
    vport:::.meta_from_datasetjson(json)@columns,
    get_meta(dm)@columns
  )
})

test_that("a plain nanoparquet file degrades to a bare frame (9.B)", {
  p <- withr::local_tempfile(fileext = ".parquet")
  nanoparquet::write_parquet(data.frame(a = 1:3, b = c("x", "y", "z")), p)
  back <- read_parquet(p)
  expect_identical(nrow(back), 3L)
  expect_null(attr(back, "metadata_json", exact = TRUE))
})

test_that("encode without meta writes a sidecar-free parquet", {
  # The kv-NULL branch: a frame with no vport_meta still writes its data.
  df <- data.frame(a = 1:3, b = c("x", "y", "z"))
  p <- withr::local_tempfile(fileext = ".parquet")
  vport:::.encode_parquet(df, NULL, p)
  expect_null(vport:::.parquet_sidecar(p))
  back <- read_parquet(p)
  expect_identical(back$a, 1:3)
})

# ---- cross-format chain -----------------------------------------------------

test_that("xpt -> parquet -> json preserves metadata across the chain", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", check = "off")
  px <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(adsl, px, created = as.POSIXct("2020-01-01", tz = "UTC"))
  fromx <- read_xpt(px)

  pp <- withr::local_tempfile(fileext = ".parquet")
  write_parquet(fromx, pp)
  back_pq <- read_parquet(pp)
  expect_identical(get_meta(back_pq)@columns, get_meta(fromx)@columns)

  pj <- withr::local_tempfile(fileext = ".json")
  write_json(back_pq, pj)
  back_js <- read_json(pj)
  expect_identical(get_meta(back_js)@columns, get_meta(fromx)@columns)
})

# ---- check_formats ----------------------------------------------------------

test_that("check_formats reports parquet available when nanoparquet is present", {
  cf <- check_formats()
  row <- cf[cf$format == "parquet", ]
  expect_true(row$read)
  expect_true(row$write)
  expect_true(all(c("json", "parquet", "rds", "xpt") %in% cf$format))
})

# ---- internals + atomicity --------------------------------------------------

test_that("a file with KV metadata but no metadata_json key has no sidecar", {
  p <- withr::local_tempfile(fileext = ".parquet")
  nanoparquet::write_parquet(data.frame(a = 1:3), p, metadata = c(other = "v"))
  expect_null(vport:::.parquet_sidecar(p))
})

test_that("a failed encode leaves any prior file untouched (9.A.4)", {
  p <- withr::local_tempfile(fileext = ".parquet")
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", check = "off")
  write_parquet(dm, p)
  before <- readBin(p, "raw", file.info(p)$size)

  # A complex column is unrepresentable in Parquet: nanoparquet aborts after
  # the temp file is opened, so the cleanup path runs and the target survives.
  bad <- data.frame(a = 1:2)
  bad$b <- c(1 + 2i, 3 + 4i)
  bad <- set_meta(bad, vport:::.meta_from_frame(bad))
  expect_error(write_parquet(bad, p))
  expect_identical(readBin(p, "raw", file.info(p)$size), before)
})
