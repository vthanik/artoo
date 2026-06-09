# Tests for validate_spec() and its intrinsic findings.

test_that("validate_spec() returns findings invisibly for a clean spec", {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
  spec <- vport_spec(ds, cdisc_variables, codelists = cdisc_codelists)
  findings <- validate_spec(spec)
  expect_s3_class(findings, "data.frame")
  expect_false(any(findings$severity == "error"))
})

test_that("validate_spec() throws on an unresolvable sort key", {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "NOTAVAR"
  spec <- vport_spec(ds, cdisc_variables, codelists = cdisc_codelists)
  expect_error(validate_spec(spec), class = "vport_error_validation")
})

test_that("validate_spec() flags a non-positive length as an error", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      label = "Age",
      data_type = "integer",
      length = 0L
    )
  )
  expect_error(validate_spec(spec), class = "vport_error_validation")
})

test_that("validate_spec() warns (not errors) on a missing dataset label", {
  spec <- vport_spec(
    data.frame(dataset = "DM"), # no label
    data.frame(
      dataset = "DM",
      variable = "AGE",
      label = "Age",
      data_type = "integer"
    )
  )
  findings <- validate_spec(spec)
  expect_true("dataset_label" %in% findings$check)
  expect_true(all(
    findings$severity[findings$check == "dataset_label"] == "warning"
  ))
})

test_that("validate_spec() flags negative significant_digits as an error", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "AVAL",
      label = "Value",
      data_type = "float",
      significant_digits = -1L
    )
  )
  expect_error(validate_spec(spec), class = "vport_error_validation")
})

test_that("validate_spec() emits a note for a variable with no label", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  findings <- validate_spec(spec)
  expect_true("variable_label" %in% findings$check)
  expect_equal(
    findings$severity[findings$check == "variable_label"][[1]],
    "note"
  )
})

test_that("validate_spec() rejects a non-spec argument", {
  expect_error(validate_spec(mtcars), class = "vport_error_input")
})
