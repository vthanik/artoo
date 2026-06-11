# Tests for apply_spec() and check_spec(): the transactional conform
# pipeline and the thin conformance check, on bundled CDISC demo data.

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

# ---- apply_spec core --------------------------------------------------------

test_that("apply_spec conforms ADSL and stamps metadata", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")

  expect_s3_class(adsl, "data.frame")
  # Columns are exactly the spec variables, in spec order.
  expect_identical(names(adsl), spec_variables(spec, "ADSL")$variable)
  # Metadata is attached and records the row count.
  meta <- get_meta(adsl)
  expect_true(is_vport_meta(meta))
  expect_identical(meta@dataset$records, nrow(adsl))
})

test_that("apply_spec scaffolds missing spec variables as typed NA", {
  spec <- demo_spec()
  raw <- cdisc_adsl[, setdiff(names(cdisc_adsl), "AGE"), drop = FALSE]
  out <- apply_spec(raw, spec, "ADSL", on_error = "off")

  expect_true("AGE" %in% names(out))
  expect_true(all(is.na(out$AGE)))
})

test_that("apply_spec drops columns the spec does not declare", {
  spec <- demo_spec()
  raw <- cdisc_adsl
  raw$NOTSPEC <- 1
  out <- apply_spec(raw, spec, "ADSL", on_error = "off")
  expect_false("NOTSPEC" %in% names(out))
})

test_that("apply_spec realizes date columns to Date with the SAS epoch (bug guard)", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")

  expect_s3_class(adsl$TRTSDT, "Date")
  # Deflating to SAS days must use the 1960 epoch, not the R 1970 epoch:
  # the two differ by 3653 days, the historical bug.
  sas_days <- vport:::.deflate_temporal(adsl$TRTSDT, "date")
  r_epoch_days <- as.numeric(unclass(adsl$TRTSDT))
  ok <- !is.na(sas_days)
  expect_equal(sas_days[ok], r_epoch_days[ok] + 3653)
})

test_that("a scaffolded date variable without targetDataType is ISO-text NA", {
  # The spec types TRTSDT "date" with no targetDataType: by the CDISC
  # storage rule that is ISO 8601 text, so the scaffold is character NA.
  spec <- demo_spec()
  raw <- cdisc_adsl[, setdiff(names(cdisc_adsl), "TRTSDT"), drop = FALSE]
  out <- apply_spec(raw, spec, "ADSL", on_error = "off")
  expect_type(out$TRTSDT, "character")
  expect_true(all(is.na(out$TRTSDT)))
})

test_that("apply_spec does not mutate its input (transactional)", {
  spec <- demo_spec()
  before <- cdisc_adsl
  apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
  expect_identical(cdisc_adsl, before)
})

test_that("apply_spec steps= runs only the requested steps", {
  spec <- demo_spec()
  # No "stamp" -> no metadata attached.
  out <- apply_spec(cdisc_dm, spec, "DM", steps = c("coerce", "order"))
  expect_null(attr(out, "metadata_json"))
})

test_that("apply_spec rejects an unknown step", {
  spec <- demo_spec()
  expect_error(
    apply_spec(cdisc_adsl, spec, "ADSL", steps = "nope"),
    class = "vport_error_input"
  )
  expect_snapshot(
    apply_spec(cdisc_adsl, spec, "ADSL", steps = "nope"),
    error = TRUE
  )
})

test_that("apply_spec validates x and dataset", {
  spec <- demo_spec()
  expect_error(
    apply_spec(list(1), spec, "ADSL"),
    class = "vport_error_input"
  )
  expect_error(
    apply_spec(cdisc_adsl, spec, "NOPE"),
    class = "vport_error_input"
  )
  expect_snapshot(apply_spec(list(1), spec, "ADSL"), error = TRUE)
  expect_snapshot(apply_spec(cdisc_adsl, spec, "NOPE"), error = TRUE)
})

test_that("decode = none leaves coded values untouched", {
  spec <- demo_spec()
  out <- apply_spec(cdisc_dm, spec, "DM", decode = "none", on_error = "off")
  raw_sorted <- apply_spec(
    cdisc_dm,
    spec,
    "DM",
    steps = c("scaffold", "drop", "coerce", "order", "sort")
  )
  expect_identical(out$SEX, raw_sorted$SEX)
})

# ---- check_spec -------------------------------------------------------------

test_that("check_spec returns the canonical empty shape on conformance", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
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

test_that("apply_spec check = strict aborts on an error finding", {
  spec <- demo_spec()
  # USUBJID coerces fine, but inject an out-of-codelist value if SEX is coded.
  raw <- cdisc_dm
  raw$USUBJID <- NULL # forces a missing_variable error
  expect_error(
    apply_spec(raw, spec, "DM", on_error = "abort", steps = c("coerce")),
    class = "vport_error_conformance"
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
    apply_spec(raw, spec, "DM", on_error = "abort"),
    class = "vport_error_conformance"
  )
})

test_that("truncating integer coercion aborts by default, warns under on_lossy (review B6)", {
  vars <- cdisc_variables
  vars$data_type[vars$dataset == "DM" & vars$variable == "AGE"] <- "integer"
  spec <- vport_spec(cdisc_datasets, vars, codelists = cdisc_codelists)
  raw <- cdisc_dm
  raw$AGE[1] <- raw$AGE[1] + 0.7
  expect_error(
    apply_spec(raw, spec, "DM", on_error = "off"),
    class = "vport_error_type"
  )
  expect_warning(
    apply_spec(raw, spec, "DM", on_error = "off", on_lossy = "warn"),
    class = "vport_warning_coercion"
  )
})

# ---- decode flag validation + overflow warning (checks expansion) -----------

test_that("apply_spec validates trim and ignore_case as single flags", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "USUBJID",
      label = "Subject",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  df <- data.frame(USUBJID = "01-001", stringsAsFactors = FALSE)
  expect_error(
    apply_spec(df, spec, "DM", trim = "yes"),
    class = "vport_error_input"
  )
  expect_error(
    apply_spec(df, spec, "DM", ignore_case = NA),
    class = "vport_error_input"
  )
})

test_that("integer overflow under coercion is named precisely", {
  spec <- vport_spec(
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
  # Overflow is lossy (values become NA): abort by default, named precisely.
  expect_error(
    apply_spec(df, spec, "DM", on_error = "off"),
    class = "vport_error_type",
    regexp = "overflow"
  )
  # Opting out keeps the old two-warning behavior (lossy + NA-introduction).
  expect_warning(
    expect_warning(
      out <- apply_spec(df, spec, "DM", on_error = "off", on_lossy = "warn"),
      class = "vport_warning_coercion"
    ),
    class = "vport_warning_coercion"
  )
  expect_identical(as.vector(out$SUBJN), c(1L, NA))
})
