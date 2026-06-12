# Tests for repair_spec() — auto-apply dataType fixes from findings.

test_that("repair_spec() flips an integer_fraction variable to float", {
  dat <- cdisc_adsl
  dat$AGE <- dat$AGE + 0.5
  findings <- check_spec(dat, adam_spec, "ADSL")
  fixed <- repair_spec(adam_spec, findings)
  v <- spec_variables(fixed, "ADSL")
  expect_identical(v$data_type[v$variable == "AGE"], "float")
  # Only the flagged variable changed; every other type is preserved.
  ov <- spec_variables(adam_spec, "ADSL")
  others <- setdiff(v$variable, "AGE")
  expect_identical(
    v$data_type[match(others, v$variable)],
    ov$data_type[match(others, ov$variable)]
  )
})

test_that("repair_spec() makes a previously-aborting frame conform", {
  dat <- cdisc_adsl
  dat$AGE <- dat$AGE + 0.5
  # Before: lossy coercion aborts regardless of conformance.
  expect_error(
    apply_spec(dat, adam_spec, "ADSL", conformance = "off"),
    class = "artoo_error_type"
  )
  fixed <- repair_spec(adam_spec, check_spec(dat, adam_spec, "ADSL"))
  expect_no_error(
    suppressWarnings(apply_spec(dat, fixed, "ADSL", conformance = "off"))
  )
})

test_that("repair_spec() repairs integer_overflow", {
  dat <- cdisc_adsl
  dat$AGE <- dat$AGE + 3e9 # beyond R's 32-bit integer range
  findings <- check_spec(dat, adam_spec, "ADSL")
  expect_true(any(findings$check == "integer_overflow"))
  fixed <- repair_spec(adam_spec, findings)
  v <- spec_variables(fixed, "ADSL")
  expect_identical(v$data_type[v$variable == "AGE"], "float")
})

test_that("repair_spec() is idempotent", {
  dat <- cdisc_adsl
  dat$AGE <- dat$AGE + 0.5
  once <- repair_spec(adam_spec, check_spec(dat, adam_spec, "ADSL"))
  findings2 <- check_spec(dat, once, "ADSL")
  expect_false(
    any(findings2$check %in% c("integer_fraction", "integer_overflow"))
  )
  twice <- suppressMessages(repair_spec(once, findings2))
  expect_identical(twice, once)
})

test_that("repair_spec() with nothing to repair returns the spec unchanged", {
  clean <- check_spec(cdisc_adsl, adam_spec, "ADSL")
  expect_message(
    out <- repair_spec(adam_spec, clean),
    class = "artoo_message_spec"
  )
  expect_identical(out, adam_spec)
})

test_that("repair_spec() applies findings spanning multiple datasets", {
  adae_vars <- spec_variables(adam_spec, "ADAE")$variable
  skip_if_not("AESEQ" %in% adae_vars)
  findings <- data.frame(
    check = c("integer_fraction", "integer_overflow"),
    dimension = "variable",
    severity = "error",
    dataset = c("ADSL", "ADAE"),
    variable = c("AGE", "AESEQ"),
    message = c("a", "b"),
    stringsAsFactors = FALSE
  )
  fixed <- repair_spec(adam_spec, findings)
  vadsl <- spec_variables(fixed, "ADSL")
  vadae <- spec_variables(fixed, "ADAE")
  expect_identical(vadsl$data_type[vadsl$variable == "AGE"], "float")
  expect_identical(vadae$data_type[vadae$variable == "AESEQ"], "float")
})

test_that("repair_spec() aborts on a non-findings input", {
  expect_snapshot(repair_spec(adam_spec, list(a = 1)), error = TRUE)
  expect_error(repair_spec(adam_spec, list(a = 1)), class = "artoo_error_input")
  expect_error(
    repair_spec(adam_spec, data.frame(x = 1)),
    class = "artoo_error_input"
  )
})

test_that("repair_spec() aborts when spec is not an artoo_spec", {
  expect_error(
    repair_spec(cdisc_adsl, data.frame()),
    class = "artoo_error_input"
  )
})
