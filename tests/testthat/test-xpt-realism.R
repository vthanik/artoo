# Real SDTM domain fixtures beyond DM: AE (repeated measures, wider) is
# committed; both AE and LB join the round-trip matrix and the pyreadstat
# oracle. LB is download-only, so its tests skip when absent.

test_that("the real AE domain reads with repeated-measures structure", {
  fixture <- test_path("fixtures", "sas-ae.xpt")
  skip_if_not(file.exists(fixture), "AE fixture not present")
  ae <- read_xpt(fixture)
  expect_gt(nrow(ae), 1000L) # many AE records
  expect_gt(ncol(ae), 30L) # wider than DM
  expect_true("USUBJID" %in% names(ae))
  # Repeated measures: a subject appears on more than one row.
  expect_true(any(duplicated(ae$USUBJID)))
  # Metadata recovered for every column.
  meta <- get_meta(ae)
  expect_identical(length(meta@columns), ncol(ae))
})

test_that("AE round-trips through every format losslessly", {
  fixture <- test_path("fixtures", "sas-ae.xpt")
  skip_if_not(file.exists(fixture), "AE fixture not present")
  ae <- read_xpt(fixture)
  fmts <- c("json", "ndjson", "rds")
  if (requireNamespace("nanoparquet", quietly = TRUE)) {
    fmts <- c(fmts, "parquet")
  }
  for (fmt in fmts) {
    p <- withr::local_tempfile(fileext = paste0(".", fmt))
    write_dataset(ae, p, format = fmt)
    back <- read_dataset(p, format = fmt)
    # expect_lossless normalizes the redundant "." tag the xpt reader places
    # on every numeric missing (a "." is an ordinary null; json/parquet drop
    # it, which is correct) — values, real tags, and meta must all match.
    expect_lossless(ae, back, via = fmt)
  }
})

test_that("AE writes back to xpt and pyreadstat agrees", {
  skip_on_cran()
  fixture <- test_path("fixtures", "sas-ae.xpt")
  skip_if_not(file.exists(fixture), "AE fixture not present")
  py <- py_with_pyreadstat()
  skip_if(py == "", "python3 + pyreadstat not available")
  ae <- read_xpt(fixture)
  out_path <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(ae, out_path)
  script <- withr::local_tempfile(fileext = ".py")
  writeLines(
    c(
      "import pyreadstat",
      sprintf("df, meta = pyreadstat.read_xport(r'%s')", out_path),
      "print(len(df))",
      "print(len(df.columns))"
    ),
    script
  )
  res <- system2(py, script, stdout = TRUE)
  expect_identical(as.integer(res[1]), nrow(ae))
  expect_identical(as.integer(res[2]), ncol(ae))
})
