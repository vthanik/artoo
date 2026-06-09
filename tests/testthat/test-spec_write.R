# Tests for write_spec() (native vport JSON).

test_that("write_spec() writes the canonical key order with a null values slot", {
  skip_if_not_installed("jsonlite")
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  p <- withr::local_tempfile(fileext = ".json")
  expect_identical(write_spec(spec, p), p)
  expect_true(file.exists(p))

  raw <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  expect_identical(
    names(raw),
    c(
      "vport_spec_version",
      "study",
      "datasets",
      "variables",
      "codelists",
      "values",
      "methods",
      "comments",
      "documents"
    )
  )
  expect_identical(raw$vport_spec_version, "1")
  expect_null(raw$values)
})

test_that("write_spec() is deterministic (byte-identical on rewrite)", {
  skip_if_not_installed("jsonlite")
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  p1 <- withr::local_tempfile(fileext = ".json")
  p2 <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p1)
  write_spec(spec, p2)
  expect_identical(readLines(p1), readLines(p2))
})

test_that("write_spec() rejects a non-spec input", {
  skip_if_not_installed("jsonlite")
  p <- withr::local_tempfile(fileext = ".json")
  expect_error(write_spec(mtcars, p), class = "vport_error_input")
  expect_snapshot(write_spec(mtcars, p), error = TRUE)
})

test_that("write_spec() rejects a bad path", {
  spec <- vport_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_error(write_spec(spec, 42), class = "vport_error_input")
})
