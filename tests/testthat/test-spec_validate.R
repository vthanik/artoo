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
    artoo:::.validate_slot(
      data.frame(),
      artoo:::.spec_cols_datasets,
      "dataset",
      "datasets"
    ),
    character(0)
  )
})

test_that(".validate_slot flags a missing required column", {
  out <- artoo:::.validate_slot(
    data.frame(x = 1),
    artoo:::.spec_cols_datasets,
    "dataset",
    "datasets"
  )
  expect_match(out, "missing required column", all = FALSE)
})

test_that(".validate_slot flags a wrong-type column", {
  out <- artoo:::.validate_slot(
    data.frame(dataset = "DM", label = 1L),
    artoo:::.spec_cols_datasets,
    "dataset",
    "datasets"
  )
  expect_match(out, "must be character", all = FALSE)
})

test_that("the S7 validator rejects a non-CDISC data_type (bare class)", {
  expect_error(
    artoo:::artoo_spec_class(
      datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
      variables = full_var(data_type = "widget")
    ),
    "non-CDISC"
  )
})

test_that("the S7 validator rejects a bad target_data_type (bare class)", {
  expect_error(
    artoo:::artoo_spec_class(
      datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
      variables = full_var(target_data_type = "bogus")
    ),
    "target_data_type"
  )
})

test_that("the S7 validator rejects an orphan dataset reference (bare class)", {
  expect_error(
    artoo:::artoo_spec_class(
      datasets = data.frame(dataset = "OTHER", stringsAsFactors = FALSE),
      variables = full_var(dataset = "DM")
    ),
    "not in"
  )
})

test_that("the S7 validator rejects an unresolved codelist (bare class)", {
  expect_error(
    artoo:::artoo_spec_class(
      datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
      variables = full_var(codelist_id = "C9")
    ),
    "unresolved codelist"
  )
})

test_that("the S7 validator rejects duplicate (dataset, variable) rows directly", {
  # Last line of defence behind the friendly constructor: building the S7
  # class directly with duplicates must still fail.
  vars <- data.frame(
    dataset = c("DM", "DM"),
    variable = c("SEX", "SEX"),
    data_type = c("string", "string"),
    stringsAsFactors = FALSE
  )
  expect_error(
    artoo:::artoo_spec_class(
      study = data.frame(),
      datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
      variables = vars,
      codelists = data.frame(),
      methods = data.frame(),
      comments = data.frame(),
      documents = data.frame(),
      values = NULL
    ),
    regexp = "duplicate"
  )
})

test_that("the meta validator rejects an unnamed columns list", {
  expect_error(
    artoo:::artoo_meta_class(
      dataset = list(itemGroupOID = "IG.X", name = "X"),
      columns = list(list(name = "A", dataType = "string"))
    ),
    regexp = "named list"
  )
})

test_that("the S7 validator refuses a non-scalar @standard", {
  # The friendly .check_*() layer catches this first, so the validator behind
  # it is the last-line defence and had no test at all. Reached by mutating
  # an already-built object, which is the only way past the constructor.
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  broken <- spec
  attr(broken, "standard") <- c("SDTMIG 3.4", "ADaMIG 1.1")
  expect_match(
    artoo:::.spec_validate(broken),
    "@standard must be a single value",
    all = FALSE
  )
  # And a well-formed spec has nothing to say.
  expect_null(artoo:::.spec_validate(spec))
})
