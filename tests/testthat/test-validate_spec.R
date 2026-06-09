# Tests for validate_spec() -- dataset-scoped, returns a vport_check.

clean_spec <- function() {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
  vport_spec(
    ds,
    cdisc_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = "CDISCPILOT01", standard = "ADaMIG 1.1")
  )
}

test_that("validate_spec() returns a vport_check with a findings data frame", {
  chk <- validate_spec(clean_spec(), dataset = "DM")
  expect_true(S7::S7_inherits(chk, vport:::vport_check_class))
  expect_s3_class(chk@findings, "data.frame")
  expect_named(
    chk@findings,
    c("check", "dimension", "severity", "dataset", "variable", "message")
  )
  expect_identical(chk@scope, "DM")
})

test_that("validate_spec() does not throw by default, even with errors", {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "NOTAVAR"
  spec <- vport_spec(ds, cdisc_variables, codelists = cdisc_codelists)
  chk <- expect_no_error(validate_spec(spec, dataset = "DM"))
  expect_true(any(chk@findings$check == "dataset_keys_resolve"))
})

test_that("validate_spec(strict = TRUE) throws on an error-severity finding", {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "NOTAVAR"
  spec <- vport_spec(ds, cdisc_variables, codelists = cdisc_codelists)
  expect_error(
    validate_spec(spec, dataset = "DM", strict = TRUE),
    class = "vport_error_validation"
  )
  expect_snapshot(
    validate_spec(spec, dataset = "DM", strict = TRUE),
    error = TRUE
  )
})

test_that("validate_spec() rejects a non-spec and an unknown dataset", {
  expect_error(validate_spec(mtcars), class = "vport_error_input")
  expect_error(
    validate_spec(clean_spec(), dataset = "NOPE"),
    class = "vport_error_input"
  )
})

# ---- per-dimension checks fire on a crafted spec ------------------------

test_that("dataset/variable checks fire and carry the right severity", {
  spec <- vport_spec(
    data.frame(dataset = "DM"), # no label -> warning
    data.frame(
      dataset = "DM",
      variable = c("AGE", "AVAL"),
      data_type = c("integer", "float"),
      length = c(0L, 8L), # AGE length 0 -> error
      significant_digits = c(NA, -1L), # AVAL -1 -> error
      stringsAsFactors = FALSE
    )
  )
  f <- validate_spec(spec, dataset = "DM")@findings
  sev <- function(id) unique(f$severity[f$check == id])
  expect_identical(sev("dataset_label_present"), "warning")
  expect_identical(sev("variable_length_positive"), "error")
  expect_identical(sev("variable_sigdigits_nonneg"), "error")
  expect_identical(sev("variable_label_present"), "note")
})

test_that("a clean spec yields no findings for the intrinsic checks", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      label = "Age",
      data_type = "integer",
      length = 8L
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec, dataset = "DM")@findings
  expect_false(any(f$check == "variable_length_positive"))
  expect_false(any(f$check == "dataset_label_present"))
  expect_false(any(f$check == "study_name_present"))
})

test_that("study_name_present fires when no study name is present (H9)", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  f <- validate_spec(spec)@findings
  expect_true(any(f$check == "study_name_present"))
})

# ---- method / comment completeness + resolution -------------------------

test_that("method/comment resolution and completeness fire", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("AGE", "SEX"),
      data_type = c("integer", "string"),
      origin = c("Derived", "Derived"),
      method_id = c("MT.MISSING", "MT.SEX"),
      comment_id = c("C.MISSING", NA),
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = "MT.SEX",
      description = NA_character_, # blank -> completeness warning
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec, dataset = "DM")@findings
  # AGE references a method/comment that do not exist -> errors.
  expect_true(any(f$check == "variable_method_resolves" & f$variable == "AGE"))
  expect_true(any(f$check == "variable_comment_resolves" & f$variable == "AGE"))
  # The referenced MT.SEX has a blank description -> warning.
  expect_true(any(f$check == "method_description_present"))
})

test_that("variable_derived_has_method fires, case-insensitively (H6)", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(
      dataset = "DM",
      variable = "AGEGR1",
      data_type = "string",
      origin = "derived", # lowercase
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec, dataset = "DM")@findings
  expect_true(any(f$check == "variable_derived_has_method"))
})

# ---- dataset scoping isolation (the headline test, H13) -----------------

test_that("validation is isolated to the scoped dataset", {
  skip_if_not_installed("readxl")
  fx <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))

  adsl <- validate_spec(fx, dataset = "ADSL")@findings
  dm <- validate_spec(fx, dataset = "DM")@findings

  # ADSL: only AGE (Derived, no method); nothing about DM's MT.DM / C.BLANK.
  expect_true(any(
    adsl$check == "variable_derived_has_method" &
      adsl$variable == "AGE"
  ))
  expect_false(any(grepl("MT.DM|C.BLANK", adsl$message)))

  # DM: the blank-description method/comment; nothing about ADSL's AGE.
  expect_true(any(dm$check == "method_description_present"))
  expect_true(any(dm$check == "comment_description_present"))
  expect_false(any(grepl("AGE", dm$message)))

  # Whole-spec mode reports both.
  all_f <- validate_spec(fx)@findings
  expect_true(any(all_f$variable == "AGE"))
  expect_true(any(all_f$variable == "MT.DM"))
})

test_that("dataset and codelist comment references must resolve", {
  spec <- vport_spec(
    data.frame(
      dataset = "DM",
      label = "DM",
      comment_id = "C.DSMISS",
      stringsAsFactors = FALSE
    ),
    data.frame(
      dataset = "DM",
      variable = "SEX",
      data_type = "string",
      codelist_id = "CL1",
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL1",
      term = c("M", "F"),
      comment_id = "C.CLMISS",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "C.OTHER",
      description = "x",
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec, dataset = "DM")@findings
  expect_true(any(f$check == "dataset_comment_resolves"))
  expect_true(any(f$check == "codelist_comment_resolves"))
})

test_that("method/comment id-uniqueness, document refs, and completeness fire", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("A", "B"),
      data_type = "string",
      method_id = c("MT.DUP", NA),
      comment_id = c("C.REF", "C.DUP"),
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = c("MT.DUP", "MT.DUP"),
      description = c("d", "d"),
      document_id = c("DOC.MISS", NA),
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = c("C.REF", "C.DUP", "C.DUP"),
      description = c(NA, "x", "x"),
      document_id = c("DOC.MISS2", NA, NA),
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec, dataset = "DM")@findings
  expect_true(any(f$check == "method_id_unique"))
  expect_true(any(f$check == "comment_id_unique"))
  expect_true(any(f$check == "method_document_resolves"))
  expect_true(any(f$check == "comment_document_resolves"))
  expect_true(any(f$check == "comment_description_present"))
})

test_that("document_id_unique fires on a duplicate document id", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      data_type = "integer",
      label = "Age",
      length = 8L
    ),
    documents = data.frame(
      document_id = c("DOC.DUP", "DOC.DUP"),
      title = "t",
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec)@findings
  expect_true(any(f$check == "document_id_unique"))
})

test_that("study_name_present fires when the study row has a blank name", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      data_type = "integer",
      label = "Age",
      length = 8L
    ),
    study = data.frame(studyname = NA_character_)
  )
  f <- validate_spec(spec)@findings
  expect_true(any(f$check == "study_name_present"))
})

test_that("value-level rows are scoped to the dataset", {
  spec <- vport_spec(
    data.frame(dataset = c("DM", "AE"), label = c("DM", "AE")),
    data.frame(
      dataset = c("DM", "AE"),
      variable = c("AGE", "AETERM"),
      data_type = c("integer", "string"),
      label = c("Age", "Term"),
      length = c(8L, 200L),
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = c("DM", "AE"),
      variable = c("AGE", "AETERM"),
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  chk <- expect_no_error(validate_spec(spec, dataset = "DM"))
  expect_identical(chk@scope, "DM")
})

# ---- controlled terminology vs input data -------------------------------

ct_spec <- function() {
  vport_spec(
    data.frame(dataset = "ADSL", label = "ADSL"),
    data.frame(
      dataset = "ADSL",
      variable = c("SEX", "NOTINDATA"),
      data_type = "string",
      codelist_id = "C66731",
      mandatory = c(TRUE, FALSE),
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "C66731",
      term = c("M", "F", "U"),
      decode = c("Male", "Female", "Unknown"),
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
}

test_that("CT-vs-data flags bad values, unused terms, and missing columns", {
  dat <- data.frame(SEX = c("M", "F", "F", "X"), stringsAsFactors = FALSE)
  f <- validate_spec(ct_spec(), data = dat, dataset = "ADSL")@findings
  expect_true(any(f$check == "ct_value_in_codelist" & f$variable == "SEX"))
  expect_true(any(f$check == "ct_term_unused" & f$variable == "SEX"))
  expect_true(any(
    f$check == "variable_present_in_data" & f$variable == "NOTINDATA"
  ))
})

test_that("CT checks do not run without data", {
  f <- validate_spec(ct_spec(), dataset = "ADSL")@findings
  expect_false(any(grepl("^ct_", f$check)))
  expect_false(any(f$check == "variable_present_in_data"))
})

test_that("CT checks run on the bundled cdisc_adsl data", {
  spec <- vport_spec(
    data.frame(dataset = "ADSL", label = "ADSL"),
    data.frame(
      dataset = "ADSL",
      variable = "SEX",
      data_type = "string",
      codelist_id = "C66731",
      mandatory = TRUE,
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "C66731",
      term = c("M", "F", "U"),
      decode = c("Male", "Female", "Unknown"),
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "CDISCPILOT01")
  )
  f <- validate_spec(
    spec,
    data = as.data.frame(cdisc_adsl),
    dataset = "ADSL"
  )@findings
  # The 60-subject demo has only M/F, so U is an unused term; all SEX values
  # are valid CT, so no value violation.
  expect_true(any(f$check == "ct_term_unused"))
  expect_false(any(f$check == "ct_value_in_codelist"))
})

test_that("a single data frame needs a length-1 dataset (H18)", {
  spec <- vport_spec(
    data.frame(dataset = c("ADSL", "DM"), label = c("ADSL", "DM")),
    data.frame(
      dataset = c("ADSL", "DM"),
      variable = c("SEX", "AGE"),
      data_type = c("string", "integer"),
      label = c("Sex", "Age"),
      length = c(1L, 8L),
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  expect_error(
    validate_spec(spec, data = data.frame(SEX = "M")),
    class = "vport_error_input"
  )
})

test_that("a zero-variable scoped dataset does not crash (H15)", {
  spec <- vport_spec(
    data.frame(dataset = c("DM", "AE"), label = c("DM", "AE")),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      data_type = "integer",
      label = "Age",
      length = 8L
    ),
    study = data.frame(studyname = "S1")
  )
  chk <- expect_no_error(validate_spec(spec, dataset = "AE"))
  expect_identical(chk@scope, "AE")
})
