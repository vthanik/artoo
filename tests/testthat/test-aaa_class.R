# Tests for the S7 classes and their validators.

test_that("artoo_meta accepts CDISC dataTypes and a valid key set", {
  m <- artoo:::artoo_meta_class(
    dataset = list(name = "DM", keys = "USUBJID"),
    columns = list(USUBJID = list(dataType = "string"))
  )
  expect_true(S7::S7_inherits(m, artoo:::artoo_meta_class))
})

test_that("artoo_meta rejects a non-CDISC dataType", {
  expect_error(
    artoo:::artoo_meta_class(
      columns = list(AGE = list(dataType = "widget"))
    ),
    "non-CDISC"
  )
})

test_that("artoo_meta rejects keys that name unknown columns", {
  expect_error(
    artoo:::artoo_meta_class(
      dataset = list(keys = "MISSING"),
      columns = list(AGE = list(dataType = "integer"))
    ),
    "unknown column"
  )
})

test_that("artoo_meta rejects a non-CDISC targetDataType", {
  expect_error(
    artoo:::artoo_meta_class(
      columns = list(
        AGE = list(dataType = "integer", targetDataType = "widget")
      )
    ),
    "non-CDISC targetDataType"
  )
})

test_that("artoo_meta rejects a non-integer length or keySequence", {
  expect_error(
    artoo:::artoo_meta_class(
      columns = list(AGE = list(dataType = "integer", length = "ten"))
    ),
    "non-integer length"
  )
  expect_error(
    artoo:::artoo_meta_class(
      columns = list(AGE = list(dataType = "integer", keySequence = "1"))
    ),
    "non-integer keySequence"
  )
})

test_that("artoo_meta rejects a name field that disagrees with its list key", {
  expect_error(
    artoo:::artoo_meta_class(
      columns = list(AGE = list(name = "SEX", dataType = "integer"))
    ),
    "mismatched name"
  )
})

test_that("the closed CDISC vocabularies are exactly the spec set", {
  expect_setequal(
    artoo:::.cdisc_datatypes,
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
  expect_setequal(artoo:::.cdisc_targettypes, c("integer", "decimal"))
})

# ---- mutation safety: @<- re-validates (pinning test) -----------------------

test_that("property mutation re-runs the validator (no silent corruption)", {
  spec <- artoo_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  # A wrong property type is refused by the S7 property check.
  expect_error(spec@datasets <- "not a frame")
  # Get-modify-set of a value INSIDE a slot re-fires the cross-slot
  # validator: breaking referential integrity is impossible via @<-.
  expect_error(
    spec@datasets$dataset[1] <- "ZZZ",
    "variables reference dataset"
  )
  # The object is untouched after the failed mutations.
  expect_identical(spec@datasets$dataset, cdisc_datasets$dataset)
})
