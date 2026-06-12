# Tests for apply_spec() and check_spec(): the transactional conform
# pipeline and the thin conformance check, on bundled CDISC demo data.

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

# ---- apply_spec surface -----------------------------------------------------

test_that("apply_spec exposes exactly the load-bearing arguments", {
  # extra= joined 2026-06-12 (consumer feedback 4.2); on_coercion_loss= joined
  # 2026-06-12 as the governed opt-out of the lossy-coercion gate.
  expect_named(
    formals(apply_spec),
    c(
      "x",
      "spec",
      "dataset",
      "conformance",
      "na_position",
      "extra",
      "on_coercion_loss"
    )
  )
})

# ---- apply_spec core --------------------------------------------------------

test_that("apply_spec conforms ADSL and stamps metadata", {
  spec <- demo_adam_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")

  expect_s3_class(adsl, "data.frame")
  # Columns are exactly the spec variables, in spec order.
  expect_identical(names(adsl), spec_variables(spec, "ADSL")$variable)
  # Metadata is attached and records the row count.
  meta <- get_meta(adsl)
  expect_true(is_artoo_meta(meta))
  expect_identical(meta@dataset$records, nrow(adsl))
})

test_that("apply_spec reports a missing spec variable instead of fabricating it", {
  spec <- demo_adam_spec()
  raw <- cdisc_adsl[, setdiff(names(cdisc_adsl), "AGE"), drop = FALSE]
  out <- suppressMessages(apply_spec(raw, spec, "ADSL", conformance = "off"))

  # The variable the data lacks is left absent (artoo is a carrier, not a
  # deriver), and surfaces as a conformance finding instead of an empty column.
  expect_false("AGE" %in% names(out))
  f <- check_spec(out, spec, "ADSL")
  expect_true(
    "AGE" %in%
      f$variable[
        f$check %in% c("missing_variable", "missing_permissible")
      ]
  )
  # Dropping AGE does not change how the columns the data DID carry conform:
  # each is identical to the same column from the full-data run.
  full <- suppressMessages(apply_spec(
    cdisc_adsl,
    spec,
    "ADSL",
    conformance = "off"
  ))
  for (nm in intersect(names(out), names(full))) {
    expect_identical(out[[nm]], full[[nm]], info = nm)
  }
})

test_that("a missing mandatory spec variable is an error finding and warns", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm[, setdiff(names(cdisc_dm), "USUBJID"), drop = FALSE]
  out <- NULL
  suppressMessages(
    expect_warning(
      out <- apply_spec(raw, spec, "DM"),
      class = "artoo_warning_conformance"
    )
  )
  expect_false("USUBJID" %in% names(out))
  mv <- conformance(out)
  mv <- mv[mv$check == "missing_variable", , drop = FALSE]
  expect_true("USUBJID" %in% mv$variable)
  expect_identical(unique(mv$severity), "error")
})

test_that("missing permissible variables surface as warnings without aborting", {
  # The bundled adam_spec declares six ADSL variables this extract never
  # derived; all are permissible, so the default call attaches them as
  # warning-severity findings and emits no conformance warning.
  out <- NULL
  expect_no_warning(
    out <- suppressMessages(apply_spec(cdisc_adsl, adam_spec, "ADSL"))
  )
  gaps <- c("TRTDURD", "DISONDT", "EOSSTT", "DCSREAS", "EOSDISP", "MMS1TSBL")
  expect_false(any(gaps %in% names(out)))
  mp <- conformance(out)
  mp <- mp[mp$check == "missing_permissible", , drop = FALSE]
  expect_setequal(intersect(gaps, mp$variable), gaps)
  expect_identical(unique(mp$severity), "warning")
})

test_that("the missing-variable heads-up fires even under conformance = off", {
  expect_message(
    apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off"),
    class = "artoo_message_apply"
  )
})

test_that("the conformed frame's meta columns equal its frame columns (no phantom)", {
  out <- suppressMessages(
    apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off")
  )
  expect_identical(names(get_meta(out)@columns), names(out))
})

test_that("apply_spec never drops an undeclared column", {
  spec <- demo_adam_spec()
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
  spec <- demo_sdtm_spec()
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
  spec <- demo_adam_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")

  expect_s3_class(adsl$TRTSDT, "Date")
  # Deflating to SAS days must use the 1960 epoch, not the R 1970 epoch:
  # the two differ by 3653 days, the historical bug.
  sas_days <- artoo:::.deflate_temporal(adsl$TRTSDT, "date")
  r_epoch_days <- as.numeric(unclass(adsl$TRTSDT))
  ok <- !is.na(sas_days)
  expect_equal(sas_days[ok], r_epoch_days[ok] + 3653)
})

test_that("apply_spec does not mutate its input (transactional)", {
  spec <- demo_adam_spec()
  before <- cdisc_adsl
  apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  expect_identical(cdisc_adsl, before)
})

test_that("apply_spec validates x and dataset", {
  spec <- demo_adam_spec()
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
  spec <- demo_sdtm_spec()
  out <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  expect_setequal(unique(out$SEX), unique(cdisc_dm$SEX))
})

# ---- check_spec -------------------------------------------------------------

test_that("check_spec returns the canonical empty shape on conformance", {
  spec <- demo_adam_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  res <- check_spec(adsl, spec, "ADSL")
  expect_identical(
    names(res),
    c("check", "dimension", "severity", "dataset", "variable", "message")
  )
})

test_that("check_spec flags an extra variable as a warning", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$NOTSPEC <- 1
  res <- check_spec(raw, spec, "DM")
  hit <- res[res$check == "extra_variable", , drop = FALSE]
  expect_true("NOTSPEC" %in% hit$variable)
  expect_identical(unique(hit$severity), "warning")
})

test_that("check_spec flags a missing variable as an error", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm[, setdiff(names(cdisc_dm), "USUBJID"), drop = FALSE]
  res <- check_spec(raw, spec, "DM")
  hit <- res[res$check == "missing_variable", , drop = FALSE]
  expect_true("USUBJID" %in% hit$variable)
  expect_identical(unique(hit$severity), "error")
})

test_that("conformance = 'abort' aborts on an error finding", {
  spec <- demo_sdtm_spec()
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
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z{oops"
  expect_error(
    apply_spec(raw, spec, "DM", conformance = "abort"),
    class = "artoo_error_conformance"
  )
})

test_that("truncating integer coercion always aborts (lossless or abort)", {
  vars <- cdisc_sdtm_variables
  vars$data_type[vars$dataset == "DM" & vars$variable == "AGE"] <- "integer"
  spec <- artoo_spec(cdisc_sdtm_datasets, vars, codelists = cdisc_codelists)
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

# ---- structured condition data (consumer feedback 4.3) ----------------------

test_that("the lossy-coercion abort carries the offending rows as cnd$variables", {
  # A pipeline must be able to collect every type mismatch programmatically,
  # not parse the cli message. The condition carries a data frame with one
  # row per (variable, reason).
  vars <- rbind(
    cdisc_sdtm_variables,
    data.frame(
      dataset = "DM",
      variable = c("HEIGHTBL", "SUBJN", "MIXED"),
      label = c("Height", "Subject N", "Mixed failure"),
      data_type = "integer",
      length = 8L,
      order = max(cdisc_sdtm_variables$order, na.rm = TRUE) + 1:3,
      codelist_id = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  spec <- artoo_spec(cdisc_sdtm_datasets, vars, codelists = cdisc_codelists)
  raw <- cdisc_dm
  raw$HEIGHTBL <- 162.5 # truncates in every row
  raw$SUBJN <- 9999999999 # overflows 32-bit in every row
  raw$MIXED <- rep_len(c(1.5, 9999999999), nrow(raw)) # both reasons, one var
  e <- tryCatch(
    apply_spec(raw, spec, "DM", conformance = "off"),
    artoo_error_type = function(e) e
  )
  v <- e$variables
  expect_s3_class(v, "data.frame")
  expect_identical(names(v), c("variable", "data_type", "n", "reason"))
  expect_identical(
    v$reason[v$variable == "HEIGHTBL"],
    "truncated"
  )
  expect_identical(
    v$reason[v$variable == "SUBJN"],
    "overflowed"
  )
  # One variable failing both ways yields two rows, one per reason.
  expect_setequal(v$reason[v$variable == "MIXED"], c("truncated", "overflowed"))
  expect_identical(v$n[v$variable == "HEIGHTBL"], nrow(raw))
  expect_type(v$n, "integer")
})

test_that("the NA-introduction warning carries cnd$variables (na_introduced)", {
  vars <- rbind(
    cdisc_sdtm_variables,
    data.frame(
      dataset = "DM",
      variable = "BADNUM",
      label = "Not numeric",
      data_type = "integer",
      length = 8L,
      order = max(cdisc_sdtm_variables$order, na.rm = TRUE) + 1L,
      codelist_id = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  spec <- artoo_spec(cdisc_sdtm_datasets, vars, codelists = cdisc_codelists)
  raw <- cdisc_dm
  raw$BADNUM <- "not a number"
  w <- NULL
  withCallingHandlers(
    out <- apply_spec(raw, spec, "DM", conformance = "off"),
    artoo_warning_coercion = function(cnd) {
      w <<- cnd
      invokeRestart("muffleWarning")
    }
  )
  expect_identical(w$variables$variable, "BADNUM")
  expect_identical(w$variables$reason, "na_introduced")
  expect_identical(w$variables$n, nrow(raw))
})

# ---- factor inputs coerce through labels, never level codes -----------------

test_that("apply_spec() coerces a factor column through its labels, not codes", {
  # On main, as.integer(<factor>) returned the level codes (1, 2), silently
  # writing the wrong values. The conformed column must carry the authored
  # label values (10, 20).
  vars <- rbind(
    cdisc_sdtm_variables,
    data.frame(
      dataset = "DM",
      variable = "FCTNUM",
      label = "Factor of numeric labels",
      data_type = "integer",
      length = 8L,
      order = max(cdisc_sdtm_variables$order, na.rm = TRUE) + 1L,
      codelist_id = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  spec <- artoo_spec(cdisc_sdtm_datasets, vars, codelists = cdisc_codelists)
  raw <- cdisc_dm
  raw$FCTNUM <- factor(rep_len(c("10", "20"), nrow(raw)))
  out <- apply_spec(raw, spec, "DM", conformance = "off")
  expect_type(out$FCTNUM, "integer")
  # Labels (10, 20), never the codes (1, 2). setequal is order-independent
  # because the sort step reorders rows by key.
  expect_setequal(out$FCTNUM, c(10L, 20L))
})

test_that("apply_spec() surfaces NA from a non-numeric factor in cnd$variables", {
  vars <- rbind(
    cdisc_sdtm_variables,
    data.frame(
      dataset = "DM",
      variable = "FCTBAD",
      label = "Non-numeric factor",
      data_type = "integer",
      length = 8L,
      order = max(cdisc_sdtm_variables$order, na.rm = TRUE) + 1L,
      codelist_id = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  spec <- artoo_spec(cdisc_sdtm_datasets, vars, codelists = cdisc_codelists)
  raw <- cdisc_dm
  raw$FCTBAD <- factor(rep_len(c("M", "F"), nrow(raw)))
  w <- NULL
  withCallingHandlers(
    out <- apply_spec(raw, spec, "DM", conformance = "off"),
    artoo_warning_coercion = function(cnd) {
      w <<- cnd
      invokeRestart("muffleWarning")
    }
  )
  expect_true(all(is.na(out$FCTBAD)))
  expect_identical(
    w$variables$reason[w$variables$variable == "FCTBAD"],
    "na_introduced"
  )
})

test_that("apply_spec() detects 32-bit overflow in a factor's labels", {
  # Proves the apply-path overflow pre-check (which reads x[[v]] directly,
  # before .coerce_to_type) now sees the labels: a factor whose label overflows
  # int range must abort with reason 'overflowed', not pass as level code 1.
  vars <- rbind(
    cdisc_sdtm_variables,
    data.frame(
      dataset = "DM",
      variable = "FBIG",
      label = "Overflowing factor",
      data_type = "integer",
      length = 8L,
      order = max(cdisc_sdtm_variables$order, na.rm = TRUE) + 1L,
      codelist_id = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  spec <- artoo_spec(cdisc_sdtm_datasets, vars, codelists = cdisc_codelists)
  raw <- cdisc_dm
  raw$FBIG <- factor(rep_len("9999999999", nrow(raw)))
  e <- tryCatch(
    apply_spec(raw, spec, "DM", conformance = "off"),
    artoo_error_type = function(e) e
  )
  expect_s3_class(e, "artoo_error_type")
  expect_identical(
    e$variables$reason[e$variables$variable == "FBIG"],
    "overflowed"
  )
})

test_that("the conformance abort carries the full findings frame as cnd$findings", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "X9"
  e <- tryCatch(
    apply_spec(raw, spec, "DM", conformance = "abort"),
    artoo_error_conformance = function(e) e
  )
  f <- e$findings
  expect_s3_class(f, "data.frame")
  expect_identical(
    names(f),
    c("check", "dimension", "severity", "dataset", "variable", "message")
  )
  # The attached frame is the complete report, not just the error rows.
  expect_true(any(f$severity == "error"))
  expect_true(any(f$check == "codelist_membership" | f$variable == "SEX"))
})

# ---- extra = c("keep", "drop") (consumer feedback 4.2, unlocked) ------------

test_that("extra = 'drop' trims to the spec, never silently", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$TMPFLAG <- "x"
  raw$AVAL_RAW <- seq_len(nrow(raw)) + 0.5
  msg <- NULL
  withCallingHandlers(
    out <- suppressWarnings(
      apply_spec(raw, spec, "DM", extra = "drop")
    ),
    artoo_message_apply = function(cnd) {
      if (grepl("Dropped", conditionMessage(cnd))) {
        msg <<- conditionMessage(cnd)
      }
      invokeRestart("muffleMessage")
    }
  )
  expect_false(any(c("TMPFLAG", "AVAL_RAW") %in% names(out)))
  expect_match(msg, "Dropped 2 undeclared variables")
  # Findings describe the returned frame: the dropped columns are gone, so no
  # extra_variable finding names them. The "Dropped ..." message is the audit
  # trail of what was removed.
  f <- conformance(out)
  expect_length(f$variable[f$check == "extra_variable"], 0L)
  # Meta describes exactly the returned frame; the findings attribute is set
  # on the trimmed frame (the check runs after the drop).
  expect_setequal(names(get_meta(out)@columns), names(out))
  expect_false(is.null(attr(out, "artoo.conformance")))
})

test_that("extra = 'drop' findings describe the returned frame, not the dropped columns", {
  # Origin bug: a >8-char derivation temporary dropped via extra = "drop" was
  # still reported by conformance() as extra_variable AND variable_name,
  # because the check ran on the pre-drop frame. The check now runs after the
  # drop, so the returned frame's findings name only what it actually carries.
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$FIRST_RESP_DT <- "2020-01-01" # 13 chars: extra_variable + variable_name

  kept <- suppressMessages(suppressWarnings(
    apply_spec(raw, spec, "DM", extra = "keep")
  ))
  fk <- conformance(kept)
  # With keep, the surviving long column trips both data-column checks.
  expect_true("FIRST_RESP_DT" %in% fk$variable[fk$check == "extra_variable"])
  expect_true("FIRST_RESP_DT" %in% fk$variable[fk$check == "variable_name"])

  dropped <- suppressMessages(suppressWarnings(
    apply_spec(raw, spec, "DM", extra = "drop")
  ))
  fd <- conformance(dropped)
  # With drop, the column is gone, so neither finding names it.
  expect_false("FIRST_RESP_DT" %in% fd$variable)
  expect_length(fd$variable[fd$check == "extra_variable"], 0L)
  expect_length(fd$variable[fd$check == "variable_name"], 0L)
})

test_that("extra = 'drop' output writes only spec columns (round-trip)", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$SCRATCH <- "tmp"
  out <- suppressMessages(suppressWarnings(
    apply_spec(raw, spec, "DM", extra = "drop")
  ))
  p <- withr::local_tempfile(fileext = ".json")
  write_json(out, p)
  back <- read_json(p)
  expect_false("SCRATCH" %in% names(back))
  expect_identical(names(back), names(out))
})

test_that("extra = 'drop' with no extras is a silent no-op", {
  spec <- demo_sdtm_spec()
  kept <- suppressMessages(suppressWarnings(
    apply_spec(cdisc_dm, spec, "DM")
  ))
  expect_no_message(
    out <- suppressWarnings(
      apply_spec(cdisc_dm, spec, "DM", extra = "drop", conformance = "off")
    ),
    message = "Dropped"
  )
  expect_identical(names(out), names(kept))
})

test_that("extra = 'drop' announces even under conformance = 'off'", {
  # With checks off no extra_variable finding exists, so the unconditional
  # message is the only trace of the drop — it must fire.
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$TMPFLAG <- "x"
  expect_message(
    out <- suppressWarnings(
      apply_spec(raw, spec, "DM", conformance = "off", extra = "drop")
    ),
    "Dropped 1 undeclared variable",
    class = "artoo_message_apply"
  )
  expect_false("TMPFLAG" %in% names(out))
})

test_that("conformance = 'abort' with extra = 'drop' aborts and never mutates the input", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "X9" # error-severity finding on a spec-declared column
  raw$TMPFLAG <- "x"
  # The drop now runs before the check (on the working copy); the error
  # finding is on a spec column the drop never touches, so the abort still
  # fires. suppressMessages swallows the unconditional "Dropped" inform.
  expect_error(
    suppressMessages(
      apply_spec(raw, spec, "DM", conformance = "abort", extra = "drop")
    ),
    class = "artoo_error_conformance"
  )
  # Transactional: the input is untouched.
  expect_true("TMPFLAG" %in% names(raw))
})

test_that("the default keeps extras exactly as before", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$NOTSPEC <- "keep me"
  out <- suppressWarnings(apply_spec(raw, spec, "DM"))
  expect_true("NOTSPEC" %in% names(out))
})

# ---- on_coercion_loss = c("error", "keep") ----------------------------------

test_that("on_coercion_loss = 'keep' preserves fractional values and reports them", {
  dat <- cdisc_adsl
  dat$AGE <- dat$AGE + 0.5
  out <- suppressWarnings(
    apply_spec(dat, adam_spec, "ADSL", on_coercion_loss = "keep")
  )
  # The column is kept at its wider source type, values intact (sort reorders
  # rows, so compare as sets).
  expect_type(out$AGE, "double")
  expect_equal(sort(out$AGE), sort(dat$AGE))
  # Not silent: the mismatch is an error-severity integer_fraction finding.
  f <- conformance(out)
  expect_true("AGE" %in% f$variable[f$check == "integer_fraction"])
  expect_true(any(f$severity == "error" & f$check == "integer_fraction"))
})

test_that("on_coercion_loss = 'error' (default) aborts on lossy coercion", {
  dat <- cdisc_adsl
  dat$AGE <- dat$AGE + 0.5
  expect_error(
    apply_spec(dat, adam_spec, "ADSL"),
    class = "artoo_error_type"
  )
  # The gate is separate from conformance: 'off' does not bypass it.
  expect_error(
    apply_spec(dat, adam_spec, "ADSL", conformance = "off"),
    class = "artoo_error_type"
  )
})

test_that("on_coercion_loss = 'keep' preserves overflowing values", {
  dat <- cdisc_adsl
  dat$AGE <- dat$AGE + 3e9 # beyond R's 32-bit integer range
  out <- suppressWarnings(
    apply_spec(dat, adam_spec, "ADSL", on_coercion_loss = "keep")
  )
  expect_type(out$AGE, "double")
  expect_true(any(abs(out$AGE) > .Machine$integer.max))
  f <- conformance(out)
  expect_true("AGE" %in% f$variable[f$check == "integer_overflow"])
})
