# Tests for the vport_checks() conformance control: construction, validation,
# and its effect on which check_spec() dimensions fire.

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

test_that("vport_checks() defaults every conformance dimension on", {
  ck <- vport_checks()
  expect_true(is_vport_checks(ck))
  expect_true(ck$missing_variable)
  expect_true(ck$codelist_membership)
  expect_null(ck$encoding_check)
})

test_that("vport_checks() rejects a non-logical toggle", {
  expect_error(
    vport_checks(missing_variable = "yes"),
    class = "vport_error_input"
  )
  expect_error(vport_checks(type_mismatch = NA), class = "vport_error_input")
})

test_that("vport_checks() validates encoding_check", {
  expect_error(vport_checks(encoding_check = 1L), class = "vport_error_input")
  expect_silent(vport_checks(encoding_check = "US-ASCII"))
})

test_that("is_vport_checks is FALSE for other objects", {
  expect_false(is_vport_checks(list()))
  expect_false(is_vport_checks(TRUE))
})

test_that("print.vport_checks renders the toggle grid", {
  expect_snapshot(print(vport_checks()))
  expect_snapshot(
    print(vport_checks(length_overflow = FALSE, encoding_check = "US-ASCII"))
  )
})

test_that("disabling a dimension suppresses its findings", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z" # would trip codelist_membership
  raw$NOTSPEC <- 1 # would trip extra_variable

  on <- check_spec(raw, spec, "DM")
  expect_true(any(on$check == "codelist_membership"))
  expect_true(any(on$check == "extra_variable"))

  off <- check_spec(
    raw,
    spec,
    "DM",
    checks = vport_checks(codelist_membership = FALSE, extra_variable = FALSE)
  )
  expect_false(any(off$check == "codelist_membership"))
  expect_false(any(off$check == "extra_variable"))
})

test_that("apply_spec threads checks through to the conformance step", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z"
  # codelist check off -> no error finding -> no conformance warning.
  expect_silent(
    out <- apply_spec(
      raw,
      spec,
      "DM",
      decode = "none",
      no_match = "error",
      check = "warn",
      checks = vport_checks(codelist_membership = FALSE)
    )
  )
  findings <- attr(out, "vport.conformance")
  expect_false(any(findings$check == "codelist_membership"))
})

test_that("check_spec rejects a non-vport_checks checks argument", {
  spec <- demo_spec()
  expect_error(
    check_spec(cdisc_dm, spec, "DM", checks = list(missing_variable = TRUE)),
    class = "vport_error_input"
  )
})
