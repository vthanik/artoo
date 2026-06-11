# decode_column(): single-variable codelist translation -- the
# metatools::create_var_from_codelist() shape driven by the artoo_spec.
# Shares .map_codelist_values() with apply_spec()'s decode step, so the
# policies (no_match, trim, ignore_case) behave identically.

demo_spec <- function() {
  artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

# Spec extended with a numeric coded variable (the RACEN pattern): SEXN is
# integer, owning a codelist whose terms are codes and decodes are SEX values.
sexn_spec <- function() {
  vars <- rbind(
    cdisc_variables,
    data.frame(
      dataset = "DM",
      variable = "SEXN",
      label = "Sex (N)",
      data_type = "integer",
      length = 8L,
      order = NA_integer_,
      codelist_id = "SEXN",
      stringsAsFactors = FALSE
    )
  )
  cls <- rbind(
    cdisc_codelists,
    data.frame(
      codelist_id = "SEXN",
      term = c("1", "2"),
      decode = c("F", "M"),
      order = 1:2,
      stringsAsFactors = FALSE
    )
  )
  artoo_spec(cdisc_datasets, vars, codelists = cls)
}

test_that("decode_column decodes into a new column, source untouched", {
  out <- decode_column(
    cdisc_dm,
    demo_spec(),
    "DM",
    from = "SEX",
    to = "SEXDECD"
  )
  expect_identical(out$SEX, cdisc_dm$SEX)
  expect_setequal(unique(out$SEXDECD), c("Female", "Male"))
  # New column appends; everything else is unchanged.
  expect_identical(names(out), c(names(cdisc_dm), "SEXDECD"))
})

test_that("decode_column translates in place by default (to = from)", {
  out <- decode_column(cdisc_dm, demo_spec(), "DM", from = "SEX")
  expect_setequal(unique(out$SEX), c("Female", "Male"))
})

test_that("decode_column derives a coded numeric from its decode (RACEN pattern)", {
  out <- decode_column(
    cdisc_dm,
    sexn_spec(),
    "DM",
    from = "SEX",
    to = "SEXN",
    direction = "to_code"
  )
  # Spec dataType integer -> the result is integer, not character.
  expect_type(out$SEXN, "integer")
  expect_identical(out$SEXN[out$SEX == "F"][1], 1L)
  expect_identical(out$SEXN[out$SEX == "M"][1], 2L)
  # And the spec label rides along.
  expect_identical(attr(out$SEXN, "label"), "Sex (N)")
})

test_that("the destination's codelist wins over the source's", {
  # SEX references C66731, SEXN references SEXN; to = SEXN must map through
  # SEXN's pairs (F -> 1), not C66731's (F -> Female).
  out <- decode_column(
    cdisc_dm,
    sexn_spec(),
    "DM",
    from = "SEX",
    to = "SEXN",
    direction = "to_code"
  )
  expect_true(all(out$SEXN %in% c(1L, 2L)))
})

test_that("decode_column honors the no_match policy", {
  raw <- cdisc_dm
  raw$SEX[1] <- "X"
  spec <- demo_spec()
  expect_error(
    decode_column(raw, spec, "DM", from = "SEX", to = "SEXDECD"),
    class = "artoo_error_codelist"
  )
  kept <- decode_column(
    raw,
    spec,
    "DM",
    from = "SEX",
    to = "SEXDECD",
    no_match = "keep"
  )
  expect_identical(kept$SEXDECD[1], "X")
  nad <- decode_column(
    raw,
    spec,
    "DM",
    from = "SEX",
    to = "SEXDECD",
    no_match = "na"
  )
  expect_true(is.na(nad$SEXDECD[1]))
})

test_that("decode_column soft-matches after trim and reports the variant", {
  raw <- cdisc_dm
  raw$SEX[1] <- "F "
  expect_warning(
    out <- decode_column(raw, demo_spec(), "DM", from = "SEX", to = "SEXDECD"),
    class = "artoo_warning_codelist"
  )
  expect_identical(out$SEXDECD[1], "Female")
})

test_that("decode_column validates its inputs loudly", {
  spec <- demo_spec()
  expect_error(
    decode_column(1, spec, "DM", from = "SEX"),
    class = "artoo_error_input"
  )
  expect_error(
    decode_column(cdisc_dm, spec, "DM", from = "NOPE"),
    class = "artoo_error_input"
  )
  expect_error(
    decode_column(cdisc_dm, spec, "DM", from = "SEX", to = c("A", "B")),
    class = "artoo_error_input"
  )
  # No codelist on either end is an explicit error, not a silent no-op.
  expect_error(
    decode_column(cdisc_dm, spec, "DM", from = "USUBJID", to = "USUBJ2"),
    class = "artoo_error_codelist"
  )
  expect_snapshot(
    error = TRUE,
    decode_column(cdisc_dm, spec, "DM", from = "USUBJID", to = "USUBJ2")
  )
})

test_that("decode_column to_decode then to_code restores the codes", {
  spec <- demo_spec()
  dec <- decode_column(cdisc_dm, spec, "DM", from = "SEX")
  back <- decode_column(dec, spec, "DM", from = "SEX", direction = "to_code")
  expect_identical(as.vector(back$SEX), as.vector(cdisc_dm$SEX))
})

test_that("decode_column warns when the spec dataType coercion introduces NA", {
  # Destination is integer but the codelist terms are not numeric: the
  # coercion cannot represent them and must say so, never silently.
  vars <- rbind(
    cdisc_variables,
    data.frame(
      dataset = "DM",
      variable = "SEXN",
      label = "Sex (N)",
      data_type = "integer",
      length = 8L,
      order = NA_integer_,
      codelist_id = "SEXTXT",
      stringsAsFactors = FALSE
    )
  )
  cls <- rbind(
    cdisc_codelists,
    data.frame(
      codelist_id = "SEXTXT",
      term = c("MALE", "FEMALE"),
      decode = c("M", "F"),
      order = 1:2,
      stringsAsFactors = FALSE
    )
  )
  spec <- artoo_spec(cdisc_datasets, vars, codelists = cls)
  expect_warning(
    out <- decode_column(
      cdisc_dm,
      spec,
      "DM",
      from = "SEX",
      to = "SEXN",
      direction = "to_code"
    ),
    class = "artoo_warning_coercion"
  )
  expect_true(all(is.na(out$SEXN)))
})
