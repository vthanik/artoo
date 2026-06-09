# Tests for the S7 validators (.validate_slot, .spec_validate) reached
# directly and via the bare class, to exercise the last-line-of-defence
# branches the friendly constructor normally short-circuits.

# A complete-schema one-row variables table, for bare-class construction.
full_var <- function(
  dataset = "DM",
  data_type = "string",
  target_data_type = NA_character_,
  codelist_id = NA_character_
) {
  data.frame(
    dataset = dataset,
    variable = "X",
    itemoid = NA_character_,
    label = "X",
    data_type = data_type,
    target_data_type = target_data_type,
    length = NA_integer_,
    display_format = NA_character_,
    key_sequence = NA_integer_,
    order = NA_integer_,
    codelist_id = codelist_id,
    mandatory = NA,
    significant_digits = NA_integer_,
    origin = NA_character_,
    stringsAsFactors = FALSE
  )
}

test_that(".validate_slot skips an uninitialised slot", {
  expect_identical(
    vport:::.validate_slot(
      data.frame(),
      vport:::.spec_cols_datasets,
      "dataset",
      "datasets"
    ),
    character(0)
  )
})

test_that(".validate_slot flags a missing required column", {
  out <- vport:::.validate_slot(
    data.frame(x = 1),
    vport:::.spec_cols_datasets,
    "dataset",
    "datasets"
  )
  expect_match(out, "missing required column", all = FALSE)
})

test_that(".validate_slot flags a wrong-type column", {
  out <- vport:::.validate_slot(
    data.frame(dataset = "DM", label = 1L),
    vport:::.spec_cols_datasets,
    "dataset",
    "datasets"
  )
  expect_match(out, "must be character", all = FALSE)
})

test_that("the S7 validator rejects a non-CDISC data_type (bare class)", {
  expect_error(
    vport:::vport_spec_class(
      datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
      variables = full_var(data_type = "widget")
    ),
    "non-CDISC"
  )
})

test_that("the S7 validator rejects a bad target_data_type (bare class)", {
  expect_error(
    vport:::vport_spec_class(
      datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
      variables = full_var(target_data_type = "bogus")
    ),
    "target_data_type"
  )
})

test_that("the S7 validator rejects an orphan dataset reference (bare class)", {
  expect_error(
    vport:::vport_spec_class(
      datasets = data.frame(dataset = "OTHER", stringsAsFactors = FALSE),
      variables = full_var(dataset = "DM")
    ),
    "not in"
  )
})

test_that("the S7 validator rejects an unresolved codelist (bare class)", {
  expect_error(
    vport:::vport_spec_class(
      datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
      variables = full_var(codelist_id = "C9")
    ),
    "unresolved codelist"
  )
})
