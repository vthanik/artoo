# Tests for artoo_spec() construction and is_artoo_spec().

test_that("artoo_spec() builds a valid spec from the bundled tables", {
  spec <- artoo_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  expect_true(is_artoo_spec(spec))
  expect_setequal(spec_datasets(spec), c("ADSL", "DM"))
})

test_that("artoo_spec() coerces a tibble slot to a plain data frame", {
  skip_if_not_installed("tibble")
  spec <- artoo_spec(
    tibble::tibble(dataset = "DM", label = "Demographics"),
    tibble::tibble(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_s3_class(spec@datasets, "data.frame")
  expect_false(inherits(spec@datasets, "tbl_df"))
})

test_that("artoo_spec() fills missing optional columns with typed NAs", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_true("length" %in% names(spec@variables))
  expect_type(spec@variables$length, "integer")
  expect_true(is.na(spec@variables$length))
})

test_that("artoo_spec() canonicalises variable types", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("A", "B"),
      data_type = c("text", "float")
    )
  )
  expect_equal(spec@variables$data_type, c("string", "float"))
})

test_that("artoo_spec() requires datasets and variables", {
  expect_error(artoo_spec(), class = "artoo_error_input")
  expect_error(
    artoo_spec(data.frame(dataset = "DM")),
    class = "artoo_error_input"
  )
})

test_that("artoo_spec() aborts on a missing required column", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(variable = "AGE", data_type = "integer") # no `dataset`
    ),
    class = "artoo_error_spec"
  )
})

test_that("artoo_spec() rejects a variable referencing an unknown dataset", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(dataset = "AE", variable = "AETERM", data_type = "string")
    ),
    class = "artoo_error_spec"
  )
})

test_that("artoo_spec() rejects an unresolved codelist reference", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(
        dataset = "DM",
        variable = "SEX",
        data_type = "string",
        codelist_id = "C99999"
      )
    ),
    class = "artoo_error_spec"
  )
})

test_that("artoo_spec() rejects an unknown variable type", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(dataset = "DM", variable = "A", data_type = "widget")
    ),
    class = "artoo_error_type"
  )
})

test_that("is_artoo_spec() is FALSE for non-specs", {
  expect_false(is_artoo_spec(mtcars))
  expect_false(is_artoo_spec(NULL))
})
