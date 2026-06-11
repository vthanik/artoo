# Tests for write_spec() (native artoo JSON).

test_that("write_spec() writes the canonical key order with a null values slot", {
  spec <- artoo_spec(
    cdisc_sdtm_datasets,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists
  )
  p <- withr::local_tempfile(fileext = ".json")
  expect_identical(write_spec(spec, p), p)
  expect_true(file.exists(p))

  raw <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  expect_identical(
    names(raw),
    c(
      "artoo_spec_version",
      "standard",
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
  expect_identical(raw$artoo_spec_version, "1")
  expect_null(raw$values)
})

test_that("write_spec() is deterministic (byte-identical on rewrite)", {
  spec <- artoo_spec(
    cdisc_sdtm_datasets,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists
  )
  p1 <- withr::local_tempfile(fileext = ".json")
  p2 <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p1)
  write_spec(spec, p2)
  expect_identical(readLines(p1), readLines(p2))
})

test_that("write_spec() rejects a non-spec input", {
  p <- withr::local_tempfile(fileext = ".json")
  expect_error(write_spec(mtcars, p), class = "artoo_error_input")
  expect_snapshot(write_spec(mtcars, p), error = TRUE)
})

test_that("write_spec() rejects a bad path", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_error(write_spec(spec, 42), class = "artoo_error_input")
})

test_that("@standard round-trips through native JSON", {
  spec <- artoo_spec(
    data.frame(dataset = "ADSL"),
    data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
    standard = "ADaMIG 1.1"
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  back <- read_spec(p)
  expect_identical(spec_standard(back), "ADaMIG 1.1")
  expect_identical(back, spec)

  # An unspecified standard (NA) serialises to JSON null and reads back NA.
  bare <- artoo_spec(
    data.frame(dataset = "ADSL"),
    data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer")
  )
  p2 <- withr::local_tempfile(fileext = ".json")
  write_spec(bare, p2)
  expect_identical(spec_standard(read_spec(p2)), NA_character_)
})
