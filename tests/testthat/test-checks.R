# Tests for the artoo_checks() conformance control: construction, validation,
# and its effect on which check_spec() dimensions fire.

demo_adam_spec <- function() {
  artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
}

demo_sdtm_spec <- function() {
  artoo_spec(
    cdisc_sdtm_datasets,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists
  )
}

test_that("artoo_checks() defaults every conformance dimension on", {
  ck <- artoo_checks()
  expect_true(is_artoo_checks(ck))
  expect_true(ck$missing_variable)
  expect_true(ck$codelist_membership)
  expect_true(ck$display_format)
})

test_that("artoo_checks() rejects a non-logical toggle", {
  expect_error(
    artoo_checks(missing_variable = "yes"),
    class = "artoo_error_input"
  )
  expect_error(artoo_checks(type_mismatch = NA), class = "artoo_error_input")
})

test_that("is_artoo_checks is FALSE for other objects", {
  expect_false(is_artoo_checks(list()))
  expect_false(is_artoo_checks(TRUE))
})

test_that("print.artoo_checks renders the toggle grid", {
  expect_snapshot(print(artoo_checks()))
  expect_snapshot(print(artoo_checks(length_overflow = FALSE)))
})

test_that("disabling a dimension suppresses its findings", {
  spec <- demo_sdtm_spec()
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
    checks = artoo_checks(codelist_membership = FALSE, extra_variable = FALSE)
  )
  expect_false(any(off$check == "codelist_membership"))
  expect_false(any(off$check == "extra_variable"))
})

test_that("check_spec honors a checks control on a conformed frame", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z"
  out <- apply_spec(raw, spec, "DM", conformance = "off")
  # codelist check off -> no codelist_membership finding.
  findings <- check_spec(
    out,
    spec,
    "DM",
    checks = artoo_checks(codelist_membership = FALSE)
  )
  expect_false(any(findings$check == "codelist_membership"))
})

test_that("artoo_checks() includes the display_format dimension", {
  ck <- artoo_checks()
  expect_true(ck$display_format)
  expect_error(
    artoo_checks(display_format = NA),
    class = "artoo_error_input"
  )
})

test_that("check_spec flags a temporal var with a non-matching format", {
  spec <- artoo_spec(
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
    checks = artoo_checks(display_format = FALSE)
  )
  expect_false(any(off$check == "display_format"))
})

test_that("check_spec does not flag a valid temporal format", {
  spec <- artoo_spec(
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

test_that("check_spec rejects a non-artoo_checks checks argument", {
  spec <- demo_sdtm_spec()
  expect_error(
    check_spec(cdisc_dm, spec, "DM", checks = list(missing_variable = TRUE)),
    class = "artoo_error_input"
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

  mand_spec <- artoo_spec(
    data.frame(dataset = "DM"),
    vars(TRUE),
    codelists = cdisc_codelists
  )
  f <- check_spec(dat, mand_spec, "DM")
  expect_true(any(f$check == "codelist_membership"))

  opt_spec <- artoo_spec(
    data.frame(dataset = "DM"),
    vars(FALSE),
    codelists = cdisc_codelists
  )
  f2 <- check_spec(dat, opt_spec, "DM")
  expect_false(any(f2$check == "codelist_membership"))
})

# ---- 1d: decode-aware membership -------------------------------------------

test_that("check_spec(decode=) compares against the matching codelist column (1d)", {
  spec <- demo_sdtm_spec()
  dec <- decode_column(cdisc_dm, spec, "DM", from = "SEX")
  # Checked with the same decode direction: the decoded values are members.
  f_ok <- check_spec(dec, spec, "DM", decode = "to_decode")
  expect_false(any(f_ok$check == "codelist_membership"))
  # Checked as if not decoded: the decode values are no longer terms.
  f_bad <- check_spec(dec, spec, "DM", decode = "none")
  expect_true(any(f_bad$check == "codelist_membership"))
})

# ---- Part A: submission-readiness data checks ------------------------------

test_that("char_length_limit flags over-200-byte values independent of declared length", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = "COMMENT",
      data_type = "string",
      length = 5000L, # declared length far above 201 -> length_overflow stays quiet
      stringsAsFactors = FALSE
    )
  )
  over <- check_spec(
    data.frame(COMMENT = strrep("a", 201L), stringsAsFactors = FALSE),
    spec,
    "DM"
  )
  hit <- over[over$check == "char_length_limit", , drop = FALSE]
  expect_identical(hit$variable, "COMMENT")
  expect_identical(hit$severity, "warning")
  expect_false(any(over$check == "length_overflow"))

  # 200-byte boundary is clean.
  ok <- check_spec(
    data.frame(COMMENT = strrep("a", 200L), stringsAsFactors = FALSE),
    spec,
    "DM"
  )
  expect_false(any(ok$check == "char_length_limit"))

  # all-NA column is inert (max of an empty byte set is 0).
  na_only <- check_spec(
    data.frame(COMMENT = NA_character_, stringsAsFactors = FALSE),
    spec,
    "DM"
  )
  expect_false(any(na_only$check == "char_length_limit"))

  off <- check_spec(
    data.frame(COMMENT = strrep("a", 201L), stringsAsFactors = FALSE),
    spec,
    "DM",
    checks = artoo_checks(char_length_limit = FALSE)
  )
  expect_false(any(off$check == "char_length_limit"))
})

test_that("key_uniqueness flags duplicate keys and short-circuits on a missing key", {
  ds <- cdisc_sdtm_datasets
  ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
  spec <- artoo_spec(ds, cdisc_sdtm_variables, codelists = cdisc_codelists)
  keys <- spec_keys(spec, "DM")
  expect_true(length(keys) > 0L) # DM now declares keys

  dup <- rbind(cdisc_dm, cdisc_dm[1L, , drop = FALSE])
  f <- check_spec(dup, spec, "DM")
  hit <- f[f$check == "key_uniqueness", , drop = FALSE]
  expect_identical(nrow(hit), 1L)
  expect_identical(hit$severity, "error")
  expect_true(is.na(hit$variable))

  # unique keys -> no finding.
  expect_false(any(check_spec(cdisc_dm, spec, "DM")$check == "key_uniqueness"))

  # 0-row frame is inert.
  expect_false(any(
    check_spec(cdisc_dm[0L, , drop = FALSE], spec, "DM")$check ==
      "key_uniqueness"
  ))

  # a missing key column short-circuits (that is missing_variable's job).
  no_key <- cdisc_dm[, setdiff(names(cdisc_dm), keys[1L]), drop = FALSE]
  f_mk <- check_spec(no_key, spec, "DM")
  expect_false(any(f_mk$check == "key_uniqueness"))

  off <- check_spec(
    dup,
    spec,
    "DM",
    checks = artoo_checks(key_uniqueness = FALSE)
  )
  expect_false(any(off$check == "key_uniqueness"))
})

test_that("label_match flags a column label that differs from the spec", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      data_type = "integer",
      label = "Age",
      stringsAsFactors = FALSE
    )
  )
  labelled <- function(lab) {
    col <- 1:3
    attr(col, "label") <- lab
    d <- data.frame(AGE = 1:3)
    d$AGE <- col
    d
  }

  f <- check_spec(labelled("Years Old"), spec, "DM")
  hit <- f[f$check == "label_match", , drop = FALSE]
  expect_identical(hit$variable, "AGE")
  expect_identical(hit$severity, "note")

  # matching label -> clean.
  expect_false(any(
    check_spec(labelled("Age"), spec, "DM")$check == "label_match"
  ))

  # no label attr on the column -> skip (raw frame).
  expect_false(any(
    check_spec(data.frame(AGE = 1:3), spec, "DM")$check == "label_match"
  ))

  # blank spec label -> skip.
  spec_blank <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      data_type = "integer",
      label = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  expect_false(any(
    check_spec(labelled("Years Old"), spec_blank, "DM")$check == "label_match"
  ))

  off <- check_spec(
    labelled("Years Old"),
    spec,
    "DM",
    checks = artoo_checks(label_match = FALSE)
  )
  expect_false(any(off$check == "label_match"))
})

test_that("missing_permissible splits missing variables by the mandatory flag", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("USUBJID", "COMMENT"),
      data_type = c("string", "string"),
      mandatory = c(TRUE, FALSE),
      stringsAsFactors = FALSE
    )
  )
  f <- check_spec(data.frame(AGE = 1:2), spec, "DM")
  mv <- f[f$check == "missing_variable", , drop = FALSE]
  mp <- f[f$check == "missing_permissible", , drop = FALSE]
  expect_identical(mv$variable, "USUBJID")
  expect_identical(mv$severity, "error")
  expect_identical(mp$variable, "COMMENT")
  expect_identical(mp$severity, "warning")

  # NA mandatory -> conservatively mandatory (error bucket).
  spec_na <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = "XX",
      data_type = "string",
      mandatory = NA,
      stringsAsFactors = FALSE
    )
  )
  fna <- check_spec(data.frame(AGE = 1:2), spec_na, "DM")
  expect_true(any(fna$check == "missing_variable" & fna$variable == "XX"))
  expect_false(any(fna$check == "missing_permissible"))

  # the two buckets toggle independently.
  off_mv <- check_spec(
    data.frame(AGE = 1:2),
    spec,
    "DM",
    checks = artoo_checks(missing_variable = FALSE)
  )
  expect_false(any(off_mv$check == "missing_variable"))
  expect_true(any(off_mv$check == "missing_permissible"))
})

test_that(".is_mandatory classifies logical and character flags, NA as mandatory", {
  expect_identical(
    artoo:::.is_mandatory(c(TRUE, FALSE, NA)),
    c(TRUE, FALSE, TRUE)
  )
  expect_identical(
    artoo:::.is_mandatory(c("Y", "N", "Yes", "No", NA)),
    c(TRUE, FALSE, TRUE, FALSE, TRUE)
  )
  expect_identical(artoo:::.is_mandatory(character(0)), logical(0))
  expect_identical(artoo:::.is_mandatory(logical(0)), logical(0))
})
