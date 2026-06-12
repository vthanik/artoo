# Tests for check_study() — study-level conformance driver.

test_that("check_study() stacks per-dataset findings into one frame", {
  adsl <- cdisc_adsl
  adsl$AGE <- adsl$AGE + 0.5
  r <- check_study(adam_spec, list(ADSL = adsl, ADAE = cdisc_adae))
  expect_s3_class(r, "artoo_study_findings")
  expect_s3_class(r, "artoo_findings")
  expect_true(is.data.frame(r))
  # The row count is the sum of the per-dataset check_spec() results.
  n_adsl <- nrow(check_spec(adsl, adam_spec, "ADSL"))
  n_adae <- nrow(check_spec(cdisc_adae, adam_spec, "ADAE"))
  expect_equal(nrow(r), n_adsl + n_adae)
  expect_setequal(unique(r$dataset), c("ADSL", "ADAE"))
})

test_that("check_study() result feeds repair_spec()", {
  adsl <- cdisc_adsl
  adsl$AGE <- adsl$AGE + 0.5
  fixed <- repair_spec(adam_spec, check_study(adam_spec, list(ADSL = adsl)))
  v <- spec_variables(fixed, "ADSL")
  expect_identical(v$data_type[v$variable == "AGE"], "float")
})

test_that("check_study() prints the dataset-by-check matrix", {
  adsl <- cdisc_adsl
  adsl$AGE <- adsl$AGE + 0.5
  expect_snapshot(print(check_study(adam_spec, list(ADSL = adsl))))
})

test_that("check_study() prints a clean message when nothing is found", {
  # All dimensions off -> zero findings -> the empty-matrix print branch.
  off <- artoo_checks(
    missing_variable = FALSE,
    missing_permissible = FALSE,
    extra_variable = FALSE,
    type_mismatch = FALSE,
    length_overflow = FALSE,
    char_length_limit = FALSE,
    codelist_membership = FALSE,
    codelist_membership_extensible = FALSE,
    label_match = FALSE,
    key_uniqueness = FALSE,
    display_format = FALSE,
    variable_name = FALSE,
    dataset_name = FALSE,
    label_length = FALSE,
    integer_overflow = FALSE,
    integer_fraction = FALSE,
    iso8601_format = FALSE
  )
  r <- check_study(adam_spec, list(ADSL = cdisc_adsl), checks = off)
  expect_equal(nrow(r), 0L)
  expect_output(print(r), "No findings")
  expect_output(print(r), "1 dataset")
})

test_that("check_study() aborts on a bad data argument", {
  expect_snapshot(check_study(adam_spec, cdisc_adsl), error = TRUE)
  expect_error(check_study(adam_spec, cdisc_adsl), class = "artoo_error_input")
  expect_error(check_study(adam_spec, list()), class = "artoo_error_input")
  expect_error(
    check_study(adam_spec, list(cdisc_adsl)), # unnamed
    class = "artoo_error_input"
  )
  expect_error(
    check_study(adam_spec, list(ADSL = 1)), # not a data frame
    class = "artoo_error_input"
  )
})

test_that("check_study() aborts on an unknown dataset", {
  expect_snapshot(
    check_study(adam_spec, list(NOPE = cdisc_adsl)),
    error = TRUE
  )
  expect_error(
    check_study(adam_spec, list(NOPE = cdisc_adsl)),
    class = "artoo_error_input"
  )
})

test_that("check_study() aborts when spec is not an artoo_spec", {
  expect_error(
    check_study(cdisc_adsl, list(ADSL = cdisc_adsl)),
    class = "artoo_error_input"
  )
})
