# Tests for set_type() — declarative spec dataType override.

test_that("set_type() retypes one variable and leaves the original intact", {
  fixed <- set_type(adam_spec, "ADSL", AGE = "float")
  v <- spec_variables(fixed, "ADSL")
  expect_identical(v$data_type[v$variable == "AGE"], "float")
  # Immutable: the source spec still reports the original type.
  ov <- spec_variables(adam_spec, "ADSL")
  expect_identical(ov$data_type[ov$variable == "AGE"], "integer")
  expect_true(is_artoo_spec(fixed))
})

test_that("set_type() retypes several variables and canonicalises spellings", {
  fixed <- set_type(adam_spec, "ADSL", AGE = "Float", SEX = "text")
  v <- spec_variables(fixed, "ADSL")
  expect_identical(v$data_type[v$variable == "AGE"], "float")
  expect_identical(v$data_type[v$variable == "SEX"], "string")
})

test_that("set_type() changes only the named dataset's row for a shared variable", {
  # USUBJID appears in both ADSL and ADAE; retyping it in ADSL must not touch
  # ADAE's row.
  skip_if_not("USUBJID" %in% spec_variables(adam_spec, "ADAE")$variable)
  before <- spec_variables(adam_spec, "ADAE")
  before_type <- before$data_type[before$variable == "USUBJID"]
  fixed <- set_type(adam_spec, "ADSL", USUBJID = "integer")
  a <- spec_variables(fixed, "ADSL")
  b <- spec_variables(fixed, "ADAE")
  expect_identical(a$data_type[a$variable == "USUBJID"], "integer")
  expect_identical(b$data_type[b$variable == "USUBJID"], before_type)
})

test_that("set_type() aborts on an unknown dataset", {
  expect_snapshot(set_type(adam_spec, "NOPE", AGE = "float"), error = TRUE)
  expect_error(
    set_type(adam_spec, "NOPE", AGE = "float"),
    class = "artoo_error_input"
  )
})

test_that("set_type() aborts on an unknown variable", {
  expect_snapshot(set_type(adam_spec, "ADSL", NOPE = "float"), error = TRUE)
  expect_error(
    set_type(adam_spec, "ADSL", NOPE = "float"),
    class = "artoo_error_input"
  )
})

test_that("set_type() aborts on an unnamed or empty override", {
  expect_snapshot(set_type(adam_spec, "ADSL", "float"), error = TRUE)
  expect_error(
    set_type(adam_spec, "ADSL", "float"),
    class = "artoo_error_input"
  )
  expect_snapshot(set_type(adam_spec, "ADSL"), error = TRUE)
  expect_error(set_type(adam_spec, "ADSL"), class = "artoo_error_input")
})

test_that("set_type() aborts on an unknown type token", {
  expect_snapshot(
    set_type(adam_spec, "ADSL", AGE = "frobnicate"),
    error = TRUE
  )
  expect_error(
    set_type(adam_spec, "ADSL", AGE = "frobnicate"),
    class = "artoo_error_type"
  )
})

test_that("set_type() aborts when spec is not an artoo_spec", {
  expect_error(
    set_type(cdisc_adsl, "ADSL", AGE = "float"),
    class = "artoo_error_input"
  )
})
