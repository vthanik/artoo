# Tests for apply_spec() and check_spec(): the transactional conform
# pipeline and the thin conformance check, on bundled CDISC demo data.

demo_spec <- function() {
  artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

# ---- apply_spec surface -----------------------------------------------------

test_that("apply_spec exposes exactly the five load-bearing arguments", {
  expect_named(
    formals(apply_spec),
    c("x", "spec", "dataset", "conformance", "na_position")
  )
})

# ---- apply_spec core --------------------------------------------------------

test_that("apply_spec conforms ADSL and stamps metadata", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")

  expect_s3_class(adsl, "data.frame")
  # Columns are exactly the spec variables, in spec order.
  expect_identical(names(adsl), spec_variables(spec, "ADSL")$variable)
  # Metadata is attached and records the row count.
  meta <- get_meta(adsl)
  expect_true(is_artoo_meta(meta))
  expect_identical(meta@dataset$records, nrow(adsl))
})

test_that("apply_spec scaffolds missing spec variables as typed NA", {
  spec <- demo_spec()
  raw <- cdisc_adsl[, setdiff(names(cdisc_adsl), "AGE"), drop = FALSE]
  out <- apply_spec(raw, spec, "ADSL", conformance = "off")

  expect_true("AGE" %in% names(out))
  expect_true(all(is.na(out$AGE)))
})

test_that("apply_spec never drops an undeclared column", {
  spec <- demo_spec()
  raw <- cdisc_adsl
  raw$NOTSPEC <- seq_len(nrow(raw))
  out <- apply_spec(raw, spec, "ADSL")

  # The column survives, ordered after the declared variables, and the
  # extra_variable finding reports it.
  expect_true("NOTSPEC" %in% names(out))
  expect_identical(
    names(out),
    c(spec_variables(spec, "ADSL")$variable, "NOTSPEC")
  )
  findings <- conformance(out)
  hit <- findings[findings$check == "extra_variable", , drop = FALSE]
  expect_true("NOTSPEC" %in% hit$variable)
})

test_that("an undeclared column round-trips through write/read (no-drop gate)", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$DERIVED <- seq_len(nrow(raw)) + 0.5
  out <- apply_spec(raw, spec, "DM", conformance = "off")

  for (ext in c(".json", ".parquet", ".rds")) {
    p <- withr::local_tempfile(fileext = ext)
    write_dataset(out, p)
    back <- read_dataset(p)
    expect_true("DERIVED" %in% names(back))
    expect_identical(as.vector(back$DERIVED), as.vector(out$DERIVED))
    # The codec inferred metadata for the undeclared column.
    expect_true("DERIVED" %in% names(get_meta(back)@columns))
  }
})

test_that("apply_spec realizes date columns to Date with the SAS epoch (bug guard)", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")

  expect_s3_class(adsl$TRTSDT, "Date")
  # Deflating to SAS days must use the 1960 epoch, not the R 1970 epoch:
  # the two differ by 3653 days, the historical bug.
  sas_days <- artoo:::.deflate_temporal(adsl$TRTSDT, "date")
  r_epoch_days <- as.numeric(unclass(adsl$TRTSDT))
  ok <- !is.na(sas_days)
  expect_equal(sas_days[ok], r_epoch_days[ok] + 3653)
})

test_that("a scaffolded date variable without targetDataType is ISO-text NA", {
  # The spec types TRTSDT "date" with no targetDataType: by the CDISC
  # storage rule that is ISO 8601 text, so the scaffold is character NA.
  spec <- demo_spec()
  raw <- cdisc_adsl[, setdiff(names(cdisc_adsl), "TRTSDT"), drop = FALSE]
  out <- apply_spec(raw, spec, "ADSL", conformance = "off")
  expect_type(out$TRTSDT, "character")
  expect_true(all(is.na(out$TRTSDT)))
})

test_that("apply_spec does not mutate its input (transactional)", {
  spec <- demo_spec()
  before <- cdisc_adsl
  apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  expect_identical(cdisc_adsl, before)
})

test_that("apply_spec validates x and dataset", {
  spec <- demo_spec()
  expect_error(
    apply_spec(list(1), spec, "ADSL"),
    class = "artoo_error_input"
  )
  expect_error(
    apply_spec(cdisc_adsl, spec, "NOPE"),
    class = "artoo_error_input"
  )
  expect_snapshot(apply_spec(list(1), spec, "ADSL"), error = TRUE)
  expect_snapshot(apply_spec(cdisc_adsl, spec, "NOPE"), error = TRUE)
})

test_that("apply_spec keeps coded values untouched (decode is its own verb)", {
  spec <- demo_spec()
  out <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  expect_setequal(unique(out$SEX), unique(cdisc_dm$SEX))
})

# ---- check_spec -------------------------------------------------------------

test_that("check_spec returns the canonical empty shape on conformance", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  res <- check_spec(adsl, spec, "ADSL")
  expect_identical(
    names(res),
    c("check", "dimension", "severity", "dataset", "variable", "message")
  )
})

test_that("check_spec flags an extra variable as a warning", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$NOTSPEC <- 1
  res <- check_spec(raw, spec, "DM")
  hit <- res[res$check == "extra_variable", , drop = FALSE]
  expect_true("NOTSPEC" %in% hit$variable)
  expect_identical(unique(hit$severity), "warning")
})

test_that("check_spec flags a missing variable as an error", {
  spec <- demo_spec()
  raw <- cdisc_dm[, setdiff(names(cdisc_dm), "USUBJID"), drop = FALSE]
  res <- check_spec(raw, spec, "DM")
  hit <- res[res$check == "missing_variable", , drop = FALSE]
  expect_true("USUBJID" %in% hit$variable)
  expect_identical(unique(hit$severity), "error")
})

test_that("conformance = 'abort' aborts on an error finding", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "X9" # not in codelist C66731 -> error-severity finding
  expect_error(
    apply_spec(raw, spec, "DM", conformance = "abort"),
    class = "artoo_error_conformance"
  )
})

# ---- review 2026-06: strict-gate injection + lossy coercion -----------------

test_that("a brace in a data value cannot break the strict gate (review B5)", {
  # check_spec findings embed raw data values; a "{" must render literally in
  # the abort, not be parsed as cli interpolation (which crashed with a raw
  # glue error and lost the conformance report and error class).
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z{oops"
  expect_error(
    apply_spec(raw, spec, "DM", conformance = "abort"),
    class = "artoo_error_conformance"
  )
})

test_that("truncating integer coercion always aborts (lossless or abort)", {
  vars <- cdisc_variables
  vars$data_type[vars$dataset == "DM" & vars$variable == "AGE"] <- "integer"
  spec <- artoo_spec(cdisc_datasets, vars, codelists = cdisc_codelists)
  raw <- cdisc_dm
  raw$AGE[1] <- raw$AGE[1] + 0.7
  expect_error(
    apply_spec(raw, spec, "DM", conformance = "off"),
    class = "artoo_error_type"
  )
  expect_snapshot(
    error = TRUE,
    apply_spec(raw, spec, "DM", conformance = "off")
  )
})

test_that("integer overflow under coercion is named precisely and aborts", {
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "SUBJN",
      label = "Subject Number",
      data_type = "integer",
      stringsAsFactors = FALSE
    )
  )
  df <- data.frame(SUBJN = c(1, 9999999999))
  # Overflow is lossy (values become NA): always abort, named precisely.
  expect_error(
    apply_spec(df, spec, "DM", conformance = "off"),
    class = "artoo_error_type",
    regexp = "overflow"
  )
})
