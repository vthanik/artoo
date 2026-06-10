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

test_that("spec_codelists() returns one codelist's terms", {
  cl <- spec_codelists(demo_spec(), "C66731")
  expect_setequal(cl$term, c("F", "M", "U", "UNDIFFERENTIATED"))
})

test_that("spec_codelists() rejects an unknown codelist", {
  expect_error(
    spec_codelists(demo_spec(), "C00000"),
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
  expect_error(spec_methods(mtcars), class = "vport_error_input")
  expect_error(spec_comments(mtcars), class = "vport_error_input")
  expect_error(spec_documents(mtcars), class = "vport_error_input")
})

test_that("spec_methods/comments/documents return their slots", {
  spec <- vport_spec(
    data.frame(dataset = "ADSL"),
    data.frame(
      dataset = "ADSL",
      variable = "AGEGR1",
      data_type = "string",
      method_id = "MT.AGEGR1",
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = "MT.AGEGR1",
      description = "Age group.",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "C1",
      description = "Note.",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "SAP",
      title = "SAP",
      stringsAsFactors = FALSE
    )
  )
  expect_identical(spec_methods(spec)$method_id, "MT.AGEGR1")
  expect_identical(spec_comments(spec)$comment_id, "C1")
  expect_identical(spec_documents(spec)$document_id, "SAP")
})

test_that("the supporting-metadata slots are empty by default", {
  spec <- vport_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_equal(nrow(spec_methods(spec)), 0L)
  expect_equal(nrow(spec_comments(spec)), 0L)
  expect_equal(nrow(spec_documents(spec)), 0L)
})
