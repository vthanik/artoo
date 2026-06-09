# Tests for the spec accessors.

demo_spec <- function() {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
  vport_spec(
    ds,
    cdisc_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = "CDISCPILOT01", standard = "ADaMIG 1.1")
  )
}

test_that("spec_datasets() returns the declared dataset names", {
  expect_setequal(spec_datasets(demo_spec()), c("ADSL", "DM"))
})

test_that("spec_variables() filters to one dataset or returns all", {
  spec <- demo_spec()
  dm <- spec_variables(spec, "DM")
  expect_true(all(dm$dataset == "DM"))
  expect_equal(nrow(spec_variables(spec)), nrow(cdisc_variables))
})

test_that("spec_variables() rejects an unknown dataset", {
  expect_error(spec_variables(demo_spec(), "NOPE"), class = "vport_error_input")
})

test_that("spec_codelist() returns one codelist's terms", {
  cl <- spec_codelist(demo_spec(), "C66731")
  expect_setequal(cl$term, c("F", "M", "U", "UNDIFFERENTIATED"))
})

test_that("spec_codelist() rejects an unknown codelist", {
  expect_error(
    spec_codelist(demo_spec(), "C00000"),
    class = "vport_error_input"
  )
})

test_that("spec_keys() parses whitespace-separated keys", {
  expect_equal(spec_keys(demo_spec(), "DM"), c("STUDYID", "USUBJID"))
})

test_that("spec_keys() returns empty when no keys are declared", {
  expect_equal(spec_keys(demo_spec(), "ADSL"), character(0))
})

test_that("spec_study() returns the row or one field", {
  spec <- demo_spec()
  expect_s3_class(spec_study(spec), "data.frame")
  expect_equal(spec_study(spec, "studyid"), "CDISCPILOT01")
})

test_that("spec_study() rejects an unknown field", {
  expect_error(spec_study(demo_spec(), "nope"), class = "vport_error_input")
})

test_that("accessors reject a non-spec argument", {
  expect_error(spec_datasets(mtcars), class = "vport_error_input")
  expect_error(spec_variables(mtcars), class = "vport_error_input")
})
