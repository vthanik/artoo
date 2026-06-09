# Tests for .meta_from_frame(): deriving vport_meta from a bare or
# haven-shaped data frame's column attributes and R classes, so write_*()
# preserves labels/formats/types without a spec.

test_that("class inference maps R types to CDISC dataTypes", {
  x <- data.frame(
    chr = "a",
    int = 1L,
    dbl = 1.5,
    lgl = TRUE,
    dte = as.Date("2014-01-02"),
    dtm = as.POSIXct("2014-01-02 08:00:00", tz = "UTC")
  )
  x$tm <- vport_time(30600)
  meta <- vport:::.meta_from_frame(x)

  dt <- function(v) meta@columns[[v]]$dataType
  expect_identical(dt("chr"), "string")
  expect_identical(dt("int"), "integer")
  expect_identical(dt("dbl"), "float")
  expect_identical(dt("lgl"), "boolean")
  expect_identical(dt("dte"), "date")
  expect_identical(dt("dtm"), "datetime")
  expect_identical(dt("tm"), "time")
})

test_that("temporal columns get a default displayFormat", {
  x <- data.frame(dte = as.Date("2014-01-02"))
  x$tm <- vport_time(0)
  meta <- vport:::.meta_from_frame(x)
  expect_identical(meta@columns$dte$displayFormat, "DATE9.")
  expect_identical(meta@columns$tm$displayFormat, "TIME8.")
})

test_that("a haven-shaped label/format.sas attribute is preserved", {
  col <- structure(c(1, 2), label = "Treatment Start", format.sas = "DATE9.")
  x <- data.frame(z = c(1, 2))
  x$AVAL <- col
  meta <- vport:::.meta_from_frame(x)
  expect_identical(meta@columns$AVAL$label, "Treatment Start")
  expect_identical(meta@columns$AVAL$displayFormat, "DATE9.")
})

test_that("character length is max(nchar); numeric defaults to 8", {
  x <- data.frame(
    nm = c("AB", "ABCDE"),
    val = c(1.5, 2.5),
    stringsAsFactors = FALSE
  )
  meta <- vport:::.meta_from_frame(x)
  expect_identical(meta@columns$nm$length, 5L)
  expect_identical(meta@columns$val$length, 8L)
})

test_that("an explicit SASlength attribute wins over inference", {
  col <- structure(c("A", "B"), SASlength = 20L)
  x <- data.frame(z = c(1, 2))
  x$V <- col
  meta <- vport:::.meta_from_frame(x)
  expect_identical(meta@columns$V$length, 20L)
})

test_that("factor columns become string dataType", {
  x <- data.frame(grp = factor(c("LOW", "HIGH")))
  meta <- vport:::.meta_from_frame(x)
  expect_identical(meta@columns$grp$dataType, "string")
})

test_that("dataset name and label come from frame attributes", {
  x <- data.frame(a = 1)
  attr(x, "dataset_name") <- "adsl"
  attr(x, "label") <- "Subject Level"
  meta <- vport:::.meta_from_frame(x)
  expect_identical(meta@dataset$name, "ADSL")
  expect_identical(meta@dataset$itemGroupOID, "IG.ADSL")
  expect_identical(meta@dataset$label, "Subject Level")
  expect_identical(meta@dataset$records, 1L)
})

test_that("a 0-column frame yields NULL", {
  expect_null(vport:::.meta_from_frame(data.frame()[0]))
})

test_that("write_dataset of a bare frame carries inferred metadata into rds", {
  x <- data.frame(
    USUBJID = c("01-001", "01-002"),
    AGE = c(54L, 61L),
    stringsAsFactors = FALSE
  )
  attr(x, "dataset_name") <- "DM"
  path <- withr::local_tempfile(fileext = ".rds")
  write_dataset(x, path)
  meta <- get_meta(read_dataset(path))
  expect_identical(meta@dataset$name, "DM")
  expect_identical(meta@columns$AGE$dataType, "integer")
  expect_identical(meta@columns$USUBJID$dataType, "string")
})
