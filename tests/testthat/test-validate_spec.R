# Tests for validate_spec() -- dataset-scoped, returns a artoo_check.

clean_spec <- function() {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
  artoo_spec(
    ds,
    cdisc_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = "CDISCPILOT01", standard = "ADaMIG 1.1")
  )
}

test_that("validate_spec() returns a artoo_check with a findings data frame", {
  chk <- validate_spec(clean_spec(), dataset = "DM")
  expect_true(S7::S7_inherits(chk, artoo:::artoo_check_class))
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
  spec <- artoo_spec(ds, cdisc_variables, codelists = cdisc_codelists)
  chk <- expect_no_error(validate_spec(spec, dataset = "DM"))
  expect_true(any(chk@findings$check == "dataset_keys_resolve"))
})

test_that("validate_spec(on_error = 'abort') throws on an error-severity finding", {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "NOTAVAR"
  spec <- artoo_spec(ds, cdisc_variables, codelists = cdisc_codelists)
  expect_error(
    validate_spec(spec, dataset = "DM", on_error = "abort"),
    class = "artoo_error_validation"
  )
  expect_snapshot(
    validate_spec(spec, dataset = "DM", on_error = "abort"),
    error = TRUE
  )
})

test_that("validate_spec() rejects a non-spec and an unknown dataset", {
  expect_error(validate_spec(mtcars), class = "artoo_error_input")
  expect_error(
    validate_spec(clean_spec(), dataset = "NOPE"),
    class = "artoo_error_input"
  )
})

# ---- per-dimension checks fire on a crafted spec ------------------------

test_that("dataset/variable checks fire and carry the right severity", {
  spec <- artoo_spec(
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
  spec <- artoo_spec(
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
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  f <- validate_spec(spec)@findings
  expect_true(any(f$check == "study_name_present"))
})

# ---- method / comment completeness + resolution -------------------------

test_that("method/comment resolution and completeness fire", {
  spec <- artoo_spec(
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
  spec <- artoo_spec(
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
  spec <- artoo_spec(
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
  spec <- artoo_spec(
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
  spec <- artoo_spec(
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
  spec <- artoo_spec(
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
  spec <- artoo_spec(
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

# ---- Wave 3 breadth: variable / value-level / codelist / unused ---------

test_that("variable order and text-length checks fire", {
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("A", "B"),
      data_type = c("string", "string"),
      order = c(-1L, 1L),
      length = c(NA_integer_, 5L),
      label = "x",
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec, dataset = "DM")@findings
  expect_true(any(f$check == "variable_order_positive" & f$variable == "A"))
  expect_true(any(f$check == "variable_length_for_text" & f$variable == "A"))
})

test_that("value-level resolution and where-clause checks fire", {
  spec <- artoo_spec(
    data.frame(dataset = "ADSL", label = "ADSL"),
    data.frame(
      dataset = "ADSL",
      variable = "PARAMCD",
      data_type = "string",
      label = "P",
      length = 8L,
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "ADSL",
      variable = c("PARAMCD", "GHOST"),
      where_clause = c(NA, "X EQ 1"),
      method_id = c("MT.NOPE", NA),
      codelist_id = c(NA, "CL.NOPE"),
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec, dataset = "ADSL")@findings
  expect_true(any(f$check == "value_whereclause_present"))
  expect_true(any(f$check == "value_variable_resolves" & f$variable == "GHOST"))
  expect_true(any(f$check == "value_method_resolves"))
  expect_true(any(f$check == "value_codelist_resolves"))
})

test_that("codelist terms-present fires for an empty referenced codelist", {
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(
      dataset = "DM",
      variable = "SEX",
      data_type = "string",
      codelist_id = "CL.EMPTY",
      label = "x",
      length = 1L,
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL.EMPTY",
      term = NA_character_,
      decode = NA_character_,
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  f <- validate_spec(spec, dataset = "DM")@findings
  expect_true(any(
    f$check == "codelist_terms_present" & f$variable == "CL.EMPTY"
  ))
})

test_that("unused checks fire only in whole-spec mode", {
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "DM"),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      data_type = "integer",
      label = "Age",
      length = 8L
    ),
    methods = data.frame(
      method_id = "MT.UNUSED",
      description = "x",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "DOC.UNUSED",
      title = "t",
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyname = "S1")
  )
  whole <- validate_spec(spec)@findings
  expect_true(any(whole$check == "method_unused"))
  expect_true(any(whole$check == "document_unused"))
  # Scoped mode skips unused checks.
  scoped <- validate_spec(spec, dataset = "DM")@findings
  expect_false(any(scoped$check == "method_unused"))
})

# ---- controlled terminology vs input data -------------------------------

ct_spec <- function() {
  artoo_spec(
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
  spec <- artoo_spec(
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
  spec <- artoo_spec(
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
    class = "artoo_error_input"
  )
})

test_that("a zero-variable scoped dataset does not crash (H15)", {
  spec <- artoo_spec(
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

test_that("a brace in spec content cannot break the strict gate (review B5)", {
  # Finding messages embed spec values; a "{" must render literally, not be
  # parsed as cli interpolation (which crashed with a raw glue error and lost
  # both the report and the documented error class).
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "NOT{AVAR"
  spec <- artoo_spec(ds, cdisc_variables, codelists = cdisc_codelists)
  expect_error(
    validate_spec(spec, dataset = "DM", on_error = "abort"),
    class = "artoo_error_validation"
  )
})

test_that("on_error = 'warn' signals a classed warning but still returns (1e)", {
  ds <- cdisc_datasets
  ds$keys[ds$dataset == "DM"] <- "NOTAVAR"
  spec <- artoo_spec(ds, cdisc_variables, codelists = cdisc_codelists)
  expect_warning(
    chk <- validate_spec(spec, dataset = "DM", on_error = "warn"),
    class = "artoo_warning_validation"
  )
  # The warning does not suppress the report: every finding is still returned.
  expect_true(any(chk@findings$severity == "error"))
})

test_that("as.data.frame returns the 6-column findings frame (1f)", {
  spec <- artoo_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  chk <- validate_spec(spec, dataset = "ADSL")
  df <- as.data.frame(chk)
  expect_identical(
    names(df),
    c("check", "dimension", "severity", "dataset", "variable", "message")
  )
  expect_identical(df, chk@findings)
})

test_that("artoo_check rejects findings missing a column or with a bad severity (1f)", {
  bad_cols <- data.frame(
    check = "x",
    severity = "error",
    stringsAsFactors = FALSE
  )
  expect_error(artoo:::artoo_check_class(findings = bad_cols))
  bad_sev <- artoo:::.empty_findings()
  bad_sev[1, ] <- list("x", "study", "fatal", NA, NA, "m")
  expect_error(artoo:::artoo_check_class(findings = bad_sev))
})

# ---- Part A: submission-readiness spec checks ------------------------------

test_that("variable_name_length flags a 9-char name but not an 8-char name", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("EXACTLY8", "NINECHAR9"),
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  chk <- validate_spec(spec, dataset = "DM")
  hit <- chk@findings[
    chk@findings$check == "variable_name_length",
    ,
    drop = FALSE
  ]
  expect_identical(hit$variable, "NINECHAR9")
  expect_identical(hit$severity, "warning")
})

test_that("variable_label_length flags over-40-byte labels, ignores blanks and the boundary", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("A", "B"),
      data_type = "string",
      label = c(strrep("x", 41L), NA_character_),
      stringsAsFactors = FALSE
    )
  )
  ll <- validate_spec(spec, dataset = "DM")@findings
  hit <- ll[ll$check == "variable_label_length", , drop = FALSE]
  expect_identical(hit$variable, "A")
  expect_identical(hit$severity, "warning")

  # 40-byte boundary is clean.
  spec40 <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = "A",
      data_type = "string",
      label = strrep("x", 40L),
      stringsAsFactors = FALSE
    )
  )
  expect_false(any(
    validate_spec(spec40, dataset = "DM")@findings$check ==
      "variable_label_length"
  ))
})

test_that("cross_dataset checks fire in whole mode and not in scoped mode", {
  spec <- artoo_spec(
    data.frame(dataset = c("DM", "ADSL")),
    data.frame(
      dataset = c("DM", "ADSL"),
      variable = c("AGE", "AGE"),
      data_type = c("integer", "string"),
      label = c("Age", "Age in Years"),
      stringsAsFactors = FALSE
    )
  )
  whole <- validate_spec(spec)@findings
  expect_identical(sum(whole$check == "cross_dataset_label"), 1L)
  expect_identical(sum(whole$check == "cross_dataset_type"), 1L)
  cl <- whole[whole$check == "cross_dataset_label", , drop = FALSE]
  expect_identical(cl$variable, "AGE")
  expect_identical(cl$severity, "note")
  expect_true(is.na(cl$dataset))
  ct <- whole[whole$check == "cross_dataset_type", , drop = FALSE]
  expect_identical(ct$severity, "warning")

  # scoped to one dataset: cross-dataset checks do not run.
  scoped <- validate_spec(spec, dataset = "DM")@findings
  expect_false(any(scoped$check == "cross_dataset_label"))
  expect_false(any(scoped$check == "cross_dataset_type"))
})

test_that("cross_dataset is silent when a shared variable is consistent", {
  spec <- artoo_spec(
    data.frame(dataset = c("DM", "ADSL")),
    data.frame(
      dataset = c("DM", "ADSL"),
      variable = c("AGE", "AGE"),
      data_type = c("integer", "integer"),
      label = c("Age", "Age"),
      stringsAsFactors = FALSE
    )
  )
  whole <- validate_spec(spec)@findings
  expect_false(any(whole$check == "cross_dataset_label"))
  expect_false(any(whole$check == "cross_dataset_type"))
})

# ---- keySequence / order / itemOID integrity (checks expansion) -------------

.ks_spec <- function(
  key_sequence,
  keys = NA_character_,
  orders = NULL,
  itemoids = NULL
) {
  vars <- data.frame(
    dataset = "DM",
    variable = c("STUDYID", "USUBJID", "AGE"),
    label = c("Study", "Subject", "Age"),
    data_type = c("string", "string", "integer"),
    length = c(10L, 12L, 8L),
    key_sequence = key_sequence,
    stringsAsFactors = FALSE
  )
  if (!is.null(orders)) {
    vars$order <- orders
  }
  if (!is.null(itemoids)) {
    vars$itemoid <- itemoids
  }
  artoo_spec(
    data.frame(dataset = "DM", label = "Demographics", keys = keys),
    vars
  )
}

test_that("key_sequence_contiguous flags gaps and duplicates", {
  ok <- validate_spec(.ks_spec(c(1L, 2L, NA)))
  expect_false(any(ok@findings$check == "key_sequence_contiguous"))

  gap <- validate_spec(.ks_spec(c(1L, 3L, NA)))
  expect_true(any(gap@findings$check == "key_sequence_contiguous"))

  dup <- validate_spec(.ks_spec(c(1L, 1L, NA)))
  expect_true(any(dup@findings$check == "key_sequence_contiguous"))

  none <- validate_spec(.ks_spec(c(NA_integer_, NA_integer_, NA_integer_)))
  expect_false(any(none@findings$check == "key_sequence_contiguous"))
})

test_that("key_sequence_matches_keys flags disagreement with declared keys", {
  agree <- validate_spec(.ks_spec(c(1L, 2L, NA), keys = "STUDYID USUBJID"))
  expect_false(any(agree@findings$check == "key_sequence_matches_keys"))

  disagree <- validate_spec(.ks_spec(c(2L, 1L, NA), keys = "STUDYID USUBJID"))
  expect_true(any(disagree@findings$check == "key_sequence_matches_keys"))

  # keys declared, no keySequence at all -> nothing to compare, no finding.
  silent <- validate_spec(.ks_spec(
    c(NA_integer_, NA_integer_, NA_integer_),
    keys = "STUDYID USUBJID"
  ))
  expect_false(any(silent@findings$check == "key_sequence_matches_keys"))
})

test_that("variable_order_unique flags duplicate order values per dataset", {
  dup <- validate_spec(.ks_spec(
    c(NA_integer_, NA_integer_, NA_integer_),
    orders = c(1L, 1L, 2L)
  ))
  expect_true(any(dup@findings$check == "variable_order_unique"))

  ok <- validate_spec(.ks_spec(
    c(NA_integer_, NA_integer_, NA_integer_),
    orders = c(1L, 2L, 3L)
  ))
  expect_false(any(ok@findings$check == "variable_order_unique"))
})

test_that("itemoid_unique flags a duplicated itemOID across the spec", {
  dup <- validate_spec(.ks_spec(
    c(NA_integer_, NA_integer_, NA_integer_),
    itemoids = c("IT.DM.A", "IT.DM.A", "IT.DM.AGE")
  ))
  io <- dup@findings[dup@findings$check == "itemoid_unique", ]
  expect_true(nrow(io) >= 1L)
  expect_identical(unique(io$severity), "error")

  ok <- validate_spec(.ks_spec(
    c(NA_integer_, NA_integer_, NA_integer_),
    itemoids = c("IT.DM.STUDYID", "IT.DM.USUBJID", "IT.DM.AGE")
  ))
  expect_false(any(ok@findings$check == "itemoid_unique"))
})
