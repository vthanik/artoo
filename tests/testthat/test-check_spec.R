# Data-conformance dims added in the checks expansion: XPORT naming rules on
# actual columns and the dataset name, label-attribute byte limits, 32-bit
# integer overflow, and the extensible-codelist membership branch.

.w3_spec <- function(extended = FALSE) {
  vport_spec(
    data.frame(dataset = "AE", label = "Adverse Events"),
    data.frame(
      dataset = c("AE", "AE", "AE"),
      variable = c("USUBJID", "AESEQ", "AESEV"),
      label = c("Subject", "Sequence", "Severity"),
      data_type = c("string", "integer", "string"),
      codelist_id = c(NA, NA, "CL.SEV"),
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL.SEV",
      term = c("MILD", "MODERATE", "SEVERE"),
      decode = c("Mild", "Moderate", "Severe"),
      extended = extended,
      stringsAsFactors = FALSE
    )
  )
}

# ---- variable_name / dataset_name -------------------------------------------

test_that("variable_name flags long and malformed data column names", {
  df <- data.frame(
    USUBJID = "01-001",
    AESEQ = 1L,
    AESEV = "MILD",
    AVERYLONGNAME = 1, # > 8 chars (v5)
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  df[["BAD-NAME"]] <- 2 # invalid character
  f <- check_spec(df, .w3_spec(), "AE")
  vn <- f[f$check == "variable_name", ]
  expect_setequal(vn$variable, c("AVERYLONGNAME", "BAD-NAME"))
  expect_true(all(vn$severity == "warning"))

  # Toggle off.
  f2 <- check_spec(
    df,
    .w3_spec(),
    "AE",
    checks = vport_checks(variable_name = FALSE)
  )
  expect_false(any(f2$check == "variable_name"))
})

test_that("dataset_name flags a name over 8 characters", {
  spec <- vport_spec(
    data.frame(dataset = "AELONGNAME", label = "x"),
    data.frame(
      dataset = "AELONGNAME",
      variable = "USUBJID",
      label = "Subject",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  df <- data.frame(USUBJID = "01-001", stringsAsFactors = FALSE)
  f <- check_spec(df, spec, "AELONGNAME")
  expect_true(any(f$check == "dataset_name"))
  f2 <- check_spec(
    df,
    spec,
    "AELONGNAME",
    checks = vport_checks(dataset_name = FALSE)
  )
  expect_false(any(f2$check == "dataset_name"))
})

# ---- label_length ------------------------------------------------------------

test_that("label_length flags a column label attribute over 40 bytes", {
  df <- data.frame(USUBJID = "01-001", AESEQ = 1L, AESEV = "MILD")
  attr(df$AESEV, "label") <- strrep("S", 41L)
  f <- check_spec(df, .w3_spec(), "AE")
  ll <- f[f$check == "label_length", ]
  expect_identical(ll$variable, "AESEV")
  expect_identical(ll$severity, "warning")
  f2 <- check_spec(
    df,
    .w3_spec(),
    "AE",
    checks = vport_checks(label_length = FALSE)
  )
  expect_false(any(f2$check == "label_length"))
})

# ---- integer_overflow ---------------------------------------------------------

test_that("integer_overflow flags values beyond R's 32-bit range", {
  df <- data.frame(
    USUBJID = "01-001",
    AESEQ = 9999999999, # > 2^31 - 1, double-stored, spec dataType integer
    AESEV = "MILD",
    stringsAsFactors = FALSE
  )
  f <- check_spec(df, .w3_spec(), "AE")
  io <- f[f$check == "integer_overflow", ]
  expect_identical(io$variable, "AESEQ")
  expect_identical(io$severity, "error")

  ok <- df
  ok$AESEQ <- 12
  expect_false(any(
    check_spec(ok, .w3_spec(), "AE")$check == "integer_overflow"
  ))

  f2 <- check_spec(
    df,
    .w3_spec(),
    "AE",
    checks = vport_checks(integer_overflow = FALSE)
  )
  expect_false(any(f2$check == "integer_overflow"))
})

# ---- extensible codelists -----------------------------------------------------

test_that("an extensible codelist downgrades membership to a note", {
  df <- data.frame(
    USUBJID = "01-001",
    AESEQ = 1L,
    AESEV = "LIFE-THREATENING", # not in the enumerated terms
    stringsAsFactors = FALSE
  )
  # Closed codelist: an error-severity membership finding.
  f_closed <- check_spec(df, .w3_spec(extended = FALSE), "AE")
  expect_true(any(f_closed$check == "codelist_membership"))
  expect_false(any(f_closed$check == "codelist_membership_extensible"))

  # Extensible codelist: the note-severity variant instead.
  f_ext <- check_spec(df, .w3_spec(extended = TRUE), "AE")
  expect_false(any(f_ext$check == "codelist_membership"))
  ext <- f_ext[f_ext$check == "codelist_membership_extensible", ]
  expect_identical(ext$variable, "AESEV")
  expect_identical(ext$severity, "note")

  # The toggle silences the extensible variant independently.
  f_off <- check_spec(
    df,
    .w3_spec(extended = TRUE),
    "AE",
    checks = vport_checks(codelist_membership_extensible = FALSE)
  )
  expect_false(any(grepl("codelist_membership", f_off$check)))
})

test_that("a conformed clean dataset still has zero findings", {
  df <- data.frame(
    USUBJID = c("01-001", "01-002"),
    AESEQ = 1:2,
    AESEV = c("MILD", "SEVERE"),
    stringsAsFactors = FALSE
  )
  out <- apply_spec(df, .w3_spec(), "AE", on_error = "off")
  expect_identical(nrow(check_spec(out, .w3_spec(), "AE")), 0L)
})
