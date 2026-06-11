# Byte-golden snapshots. A frozen `created` is the only header entropy (no
# Sys.info / R.version / OS fields, and IEEE->IBM + formatC are locale-
# independent), so a write is byte-deterministic. These pin the exact bytes:
# a diff means the serializer changed — inspect it, never blind-accept.

golden_created <- as.POSIXct("2020-01-01", tz = "UTC")

golden_frame <- function() {
  df <- data.frame(
    SUBJ = c("001", "002", "003"),
    AGE = c(34, 51, 29),
    SEX = c("F", "M", "F"),
    stringsAsFactors = FALSE
  )
  attr(df, "dataset_name") <- "DM"
  df
}

test_that("v5 write is byte-golden", {
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(golden_frame(), p, version = 5, created = golden_created)
  expect_snapshot_file(
    p,
    "golden-v5.xpt",
    compare = testthat::compare_file_binary
  )
})

test_that("v8 write is byte-golden", {
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(golden_frame(), p, version = 8, created = golden_created)
  expect_snapshot_file(
    p,
    "golden-v8.xpt",
    compare = testthat::compare_file_binary
  )
})
