# Tests for the spec accessors.

demo_spec <- function() {
  ds <- cdisc_sdtm_datasets
  ds$keys <- "STUDYID USUBJID"
  artoo_spec(
    ds,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = "CDISCPILOT01")
  )
}

test_that("spec_datasets() returns the declared dataset names", {
  expect_setequal(spec_datasets(demo_spec()), "DM")
  # Multi-dataset (single-standard) coverage rides the bundled SDTM spec.
  expect_setequal(spec_datasets(sdtm_spec), c("TS", "DM", "VS", "SUPPDM"))
})

test_that("spec_variables() filters to one dataset or returns all", {
  spec <- demo_spec()
  dm <- spec_variables(spec, "DM")
  expect_true(all(dm$dataset == "DM"))
  expect_equal(nrow(spec_variables(spec)), nrow(cdisc_sdtm_variables))
  # Across a multi-dataset spec, the unfiltered table spans every domain.
  expect_setequal(
    unique(spec_variables(sdtm_spec)$dataset),
    c("TS", "DM", "VS", "SUPPDM")
  )
})

test_that("spec_variables() rejects an unknown dataset", {
  expect_error(spec_variables(demo_spec(), "NOPE"), class = "artoo_error_input")
})

test_that("spec_codelists() returns one codelist's terms", {
  cl <- spec_codelists(demo_spec(), "C66731")
  expect_setequal(cl$term, c("F", "M", "U", "UNDIFFERENTIATED"))
})

test_that("spec_codelists() rejects an unknown codelist", {
  expect_error(
    spec_codelists(demo_spec(), "C00000"),
    class = "artoo_error_input"
  )
  # Attributes to the user's spec_codelists() call, not an internal frame.
  expect_snapshot(spec_codelists(demo_spec(), "C00000"), error = TRUE)
})

test_that("spec_keys() parses whitespace-separated keys", {
  expect_equal(spec_keys(demo_spec(), "DM"), c("STUDYID", "USUBJID"))
})

test_that("spec_keys() returns empty when no keys are declared", {
  keyless <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
  expect_equal(spec_keys(keyless, "ADSL"), character(0))
})

test_that("spec_study() returns the row or one field", {
  spec <- demo_spec()
  expect_s3_class(spec_study(spec), "data.frame")
  expect_equal(spec_study(spec, "studyid"), "CDISCPILOT01")
})

test_that("spec_study() rejects an unknown field", {
  expect_error(spec_study(demo_spec(), "nope"), class = "artoo_error_input")
  expect_snapshot(spec_study(demo_spec(), "nope"), error = TRUE)
})

test_that("accessors reject a non-spec argument", {
  expect_error(spec_datasets(mtcars), class = "artoo_error_input")
  expect_error(spec_variables(mtcars), class = "artoo_error_input")
  expect_error(spec_methods(mtcars), class = "artoo_error_input")
  expect_error(spec_comments(mtcars), class = "artoo_error_input")
  expect_error(spec_documents(mtcars), class = "artoo_error_input")
})

test_that("spec_methods/comments/documents return their slots", {
  spec <- artoo_spec(
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
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_equal(nrow(spec_methods(spec)), 0L)
  expect_equal(nrow(spec_comments(spec)), 0L)
  expect_equal(nrow(spec_documents(spec)), 0L)
})
