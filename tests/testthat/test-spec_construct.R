# Tests for vport_spec() construction and is_vport_spec().

test_that("vport_spec() builds a valid spec from the bundled tables", {
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  expect_true(is_vport_spec(spec))
  expect_setequal(spec_datasets(spec), c("ADSL", "DM"))
})

test_that("vport_spec() coerces a tibble slot to a plain data frame", {
  skip_if_not_installed("tibble")
  spec <- vport_spec(
    tibble::tibble(dataset = "DM", label = "Demographics"),
    tibble::tibble(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_s3_class(spec@datasets, "data.frame")
  expect_false(inherits(spec@datasets, "tbl_df"))
})

test_that("vport_spec() fills missing optional columns with typed NAs", {
  spec <- vport_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_true("length" %in% names(spec@variables))
  expect_type(spec@variables$length, "integer")
  expect_true(is.na(spec@variables$length))
})

test_that("vport_spec() canonicalises variable types", {
  spec <- vport_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("A", "B"),
      data_type = c("text", "float")
    )
  )
  expect_equal(spec@variables$data_type, c("string", "float"))
})

test_that("vport_spec() requires datasets and variables", {
  expect_error(vport_spec(), class = "vport_error_input")
  expect_error(
    vport_spec(data.frame(dataset = "DM")),
    class = "vport_error_input"
  )
})

test_that("vport_spec() aborts on a missing required column", {
  expect_error(
    vport_spec(
      data.frame(dataset = "DM"),
      data.frame(variable = "AGE", data_type = "integer") # no `dataset`
    ),
    class = "vport_error_spec"
  )
})

test_that("vport_spec() rejects a variable referencing an unknown dataset", {
  expect_error(
    vport_spec(
      data.frame(dataset = "DM"),
      data.frame(dataset = "AE", variable = "AETERM", data_type = "string")
    ),
    class = "vport_error_spec"
  )
})

test_that("vport_spec() rejects an unresolved codelist reference", {
  expect_error(
    vport_spec(
      data.frame(dataset = "DM"),
      data.frame(
        dataset = "DM",
        variable = "SEX",
        data_type = "string",
        codelist_id = "C99999"
      )
    ),
    class = "vport_error_spec"
  )
})

test_that("vport_spec() rejects an unknown variable type", {
  expect_error(
    vport_spec(
      data.frame(dataset = "DM"),
      data.frame(dataset = "DM", variable = "A", data_type = "widget")
    ),
    class = "vport_error_type"
  )
})

test_that("is_vport_spec() is FALSE for non-specs", {
  expect_false(is_vport_spec(mtcars))
  expect_false(is_vport_spec(NULL))
})
