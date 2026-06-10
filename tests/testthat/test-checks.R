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
  expect_true(ck$display_format)
})

test_that("vport_checks() rejects a non-logical toggle", {
  expect_error(
    vport_checks(missing_variable = "yes"),
    class = "vport_error_input"
  )
  expect_error(vport_checks(type_mismatch = NA), class = "vport_error_input")
})

test_that("is_vport_checks is FALSE for other objects", {
  expect_false(is_vport_checks(list()))
  expect_false(is_vport_checks(TRUE))
})

test_that("print.vport_checks renders the toggle grid", {
  expect_snapshot(print(vport_checks()))
  expect_snapshot(print(vport_checks(length_overflow = FALSE)))
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
      on_error = "warn",
      checks = vport_checks(codelist_membership = FALSE)
    )
  )
  findings <- attr(out, "vport.conformance")
  expect_false(any(findings$check == "codelist_membership"))
})

test_that("vport_checks() includes the display_format dimension", {
  ck <- vport_checks()
  expect_true(ck$display_format)
  expect_error(
    vport_checks(display_format = NA),
    class = "vport_error_input"
  )
})

test_that("check_spec flags a temporal var with a non-matching format", {
  spec <- vport_spec(
    data.frame(dataset = "ADSL"),
    data.frame(
      dataset = "ADSL",
      variable = "TRTSDT",
      data_type = "date",
      display_format = "$CHAR8.",
      stringsAsFactors = FALSE
    )
  )
  dat <- data.frame(TRTSDT = c(19725, 19726))
  res <- check_spec(dat, spec, "ADSL")
  hit <- res[res$check == "display_format", , drop = FALSE]
  expect_identical(hit$variable, "TRTSDT")
  expect_identical(hit$severity, "warning")

  # toggling it off suppresses the finding
  off <- check_spec(
    dat,
    spec,
    "ADSL",
    checks = vport_checks(display_format = FALSE)
  )
  expect_false(any(off$check == "display_format"))
})

test_that("check_spec does not flag a valid temporal format", {
  spec <- vport_spec(
    data.frame(dataset = "ADSL"),
    data.frame(
      dataset = "ADSL",
      variable = "TRTSDT",
      data_type = "date",
      display_format = "DATE9.",
      stringsAsFactors = FALSE
    )
  )
  res <- check_spec(data.frame(TRTSDT = 19725), spec, "ADSL")
  expect_false(any(res$check == "display_format"))
})

test_that("check_spec rejects a non-vport_checks checks argument", {
  spec <- demo_spec()
  expect_error(
    check_spec(cdisc_dm, spec, "DM", checks = list(missing_variable = TRUE)),
    class = "vport_error_input"
  )
})

# ---- 1c: one codelist-membership rule, honoring mandatory -------------------

test_that("codelist_membership treats NA in a mandatory variable as a violation (1c)", {
  vars <- function(mand) {
    data.frame(
      dataset = "DM",
      variable = "SEX",
      data_type = "string",
      codelist_id = "C66731",
      mandatory = mand,
      stringsAsFactors = FALSE
    )
  }
  dat <- data.frame(SEX = c("M", NA), stringsAsFactors = FALSE)

  mand_spec <- vport_spec(
    data.frame(dataset = "DM"),
    vars(TRUE),
    codelists = cdisc_codelists
  )
  f <- check_spec(dat, mand_spec, "DM")
  expect_true(any(f$check == "codelist_membership"))

  opt_spec <- vport_spec(
    data.frame(dataset = "DM"),
    vars(FALSE),
    codelists = cdisc_codelists
  )
  f2 <- check_spec(dat, opt_spec, "DM")
  expect_false(any(f2$check == "codelist_membership"))
})

# ---- 1d: decode-aware membership -------------------------------------------

test_that("check_spec(decode=) compares against the matching codelist column (1d)", {
  spec <- demo_spec()
  dec <- apply_spec(
    cdisc_dm,
    spec,
    "DM",
    decode = "to_decode",
    on_error = "off"
  )
  # Checked with the same decode direction: the decoded values are members.
  f_ok <- check_spec(dec, spec, "DM", decode = "to_decode")
  expect_false(any(f_ok$check == "codelist_membership"))
  # Checked as if not decoded: the decode values are no longer terms.
  f_bad <- check_spec(dec, spec, "DM", decode = "none")
  expect_true(any(f_bad$check == "codelist_membership"))
})

test_that("apply_spec threads decode so a clean decode does not warn (1d)", {
  spec <- demo_spec()
  expect_silent(
    apply_spec(cdisc_dm, spec, "DM", decode = "to_decode", on_error = "warn")
  )
})
