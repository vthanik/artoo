# Tests for the S7 classes and their validators.

test_that("vport_meta accepts CDISC dataTypes and a valid key set", {
  m <- vport:::vport_meta_class(
    dataset = list(name = "DM", keys = "USUBJID"),
    columns = list(USUBJID = list(dataType = "string"))
  )
  expect_true(S7::S7_inherits(m, vport:::vport_meta_class))
})

test_that("vport_meta rejects a non-CDISC dataType", {
  expect_error(
    vport:::vport_meta_class(
      columns = list(AGE = list(dataType = "widget"))
    ),
    "non-CDISC"
  )
})

test_that("vport_meta rejects keys that name unknown columns", {
  expect_error(
    vport:::vport_meta_class(
      dataset = list(keys = "MISSING"),
      columns = list(AGE = list(dataType = "integer"))
    ),
    "unknown column"
  )
})

test_that("the closed CDISC vocabularies are exactly the spec set", {
  expect_setequal(
    vport:::.cdisc_datatypes,
    c(
      "string",
      "integer",
      "decimal",
      "float",
      "double",
      "boolean",
      "date",
      "datetime",
      "time",
      "URI"
    )
  )
  expect_setequal(vport:::.cdisc_targettypes, c("integer", "decimal"))
})
