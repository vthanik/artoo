# Branch coverage for the apply_spec steps and check_spec dimensions:
# coercion aborts/warnings, key sorting, the conformance findings, and the
# shared codelist mapper through decode_column(). Driven by bundled CDISC
# demo data.

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

# spec with DM sort keys declared, to exercise .sort_keys().
keyed_spec <- function() {
  ds <- cdisc_sdtm_datasets
  ds$keys <- "STUDYID USUBJID"
  artoo_spec(ds, cdisc_sdtm_variables, codelists = cdisc_codelists)
}

# ---- coerce_types -----------------------------------------------------------

test_that("coercion that introduces NA warns with artoo_warning_coercion", {
  spec <- demo_adam_spec()
  raw <- cdisc_adsl
  raw$AGE <- as.character(raw$AGE)
  raw$AGE[1] <- "not-a-number"
  expect_warning(
    apply_spec(raw, spec, "ADSL", conformance = "off"),
    class = "artoo_warning_coercion"
  )
})

# ---- sort_keys --------------------------------------------------------------

test_that("sort_keys orders rows by the dataset keys and records them", {
  spec <- keyed_spec()
  raw <- cdisc_dm[sample.int(nrow(cdisc_dm)), , drop = FALSE]
  out <- apply_spec(raw, spec, "DM", conformance = "off")
  expect_identical(attr(out, "artoo.sort"), c("STUDYID", "USUBJID"))
  expect_false(is.unsorted(out$USUBJID))
})

test_that("sort_keys na_position controls where missing keys land (C1)", {
  x <- data.frame(K = c("B", NA, "A"), v = 1:3, stringsAsFactors = FALSE)
  # Default / "first": SAS PROC SORT + FDA convention -> NA leads.
  first <- artoo:::.sort_keys(x, list(keys = "K"))
  expect_identical(first$K, c(NA, "A", "B"))
  expect_identical(first$v, c(2L, 3L, 1L))
  expect_identical(
    artoo:::.sort_keys(x, list(keys = "K"), "first")$v,
    c(2L, 3L, 1L)
  )
  # "last": R / pandas / Polars convention -> NA trails.
  last <- artoo:::.sort_keys(x, list(keys = "K"), "last")
  expect_identical(last$K, c("A", "B", NA))
  expect_identical(last$v, c(3L, 1L, 2L))
})

test_that("apply_spec exposes na_position to the user", {
  spec <- keyed_spec()
  raw <- cdisc_dm
  raw$USUBJID[1] <- NA
  first <- apply_spec(
    raw,
    spec,
    "DM",
    conformance = "off",
    na_position = "first"
  )
  last <- apply_spec(raw, spec, "DM", conformance = "off", na_position = "last")
  expect_true(is.na(first$USUBJID[1])) # missing leads
  expect_true(is.na(last$USUBJID[nrow(last)])) # missing trails
})

# ---- .apply_info ------------------------------------------------------------

test_that("a partial variables$order warns and trails the unnumbered vars", {
  v <- cdisc_sdtm_variables
  # Blank one DM variable's order so the column is only partially numbered.
  v$order[v$dataset == "DM" & v$variable == "DOMAIN"] <- NA_integer_
  spec <- artoo_spec(cdisc_sdtm_datasets, v, codelists = cdisc_codelists)
  expect_warning(
    out <- apply_spec(cdisc_dm, spec, "DM", conformance = "off"),
    class = "artoo_warning_order"
  )
  # DOMAIN lost its order, so it now trails the still-numbered USUBJID.
  expect_gt(match("DOMAIN", names(out)), match("USUBJID", names(out)))
})

test_that("a fully numbered order does not warn", {
  spec <- demo_sdtm_spec()
  expect_no_warning(
    suppressMessages(apply_spec(cdisc_dm, spec, "DM", conformance = "off"))
  )
})

test_that("the missing-variable heads-up carries class artoo_message_apply", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$AGE <- NULL # declared by the spec, now absent -> reported, not added
  expect_message(
    apply_spec(raw, spec, "DM", conformance = "off"),
    class = "artoo_message_apply"
  )
})

test_that("a duplicated spec variable aborts at construction, with the rows", {
  # Fail fast, fail locatably: the duplicate surfaces when the spec is
  # built, naming the offending rows, not deep inside apply_spec() after
  # every derivation has already run.
  vars <- cdisc_sdtm_variables
  dup <- vars[vars$dataset == "DM" & vars$variable == "SEX", , drop = FALSE]
  vars2 <- rbind(vars, dup)
  expect_error(
    artoo_spec(cdisc_sdtm_datasets, vars2, codelists = cdisc_codelists),
    class = "artoo_error_spec"
  )
  expect_snapshot(
    error = TRUE,
    artoo_spec(cdisc_sdtm_datasets, vars2, codelists = cdisc_codelists)
  )
})

# ---- check_spec dimensions --------------------------------------------------

test_that("check_spec flags type_mismatch as a note (not a blocking warning)", {
  spec <- demo_adam_spec()
  raw <- cdisc_adsl
  raw$AGE <- as.character(raw$AGE) # spec wants integer storage
  res <- check_spec(raw, spec, "ADSL")
  expect_true("AGE" %in% res$variable[res$check == "type_mismatch"])
  # type_mismatch is informational: storage differs but coerces cleanly. The
  # fatal coercion checks are integer_fraction / integer_overflow.
  expect_identical(
    unique(res$severity[res$check == "type_mismatch"]),
    "note"
  )
})

test_that("check_spec flags length_overflow", {
  spec <- demo_adam_spec()
  raw <- cdisc_adsl
  raw$SUBJID <- paste0(raw$SUBJID, "EXTRALONG") # spec length is 4
  res <- check_spec(raw, spec, "ADSL")
  expect_true("SUBJID" %in% res$variable[res$check == "length_overflow"])
})

test_that("check_spec flags codelist_membership", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z" # not in C66731
  res <- check_spec(raw, spec, "DM")
  hit <- res[res$check == "codelist_membership", , drop = FALSE]
  expect_true("SEX" %in% hit$variable)
  expect_identical(unique(hit$severity), "error")
})

test_that("apply_spec conformance = warn attaches findings and warns on errors", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z"
  expect_warning(
    out <- apply_spec(raw, spec, "DM", conformance = "warn"),
    class = "artoo_warning_conformance"
  )
  findings <- attr(out, "artoo.conformance")
  expect_true(any(findings$check == "codelist_membership"))
})

test_that("check_spec rejects a non-data-frame x", {
  spec <- demo_sdtm_spec()
  expect_error(check_spec(list(1), spec, "DM"), class = "artoo_error_input")
})

test_that(".storage_of recognises integer and logical columns", {
  expect_identical(artoo:::.storage_of(1L:3L), "integer")
  expect_identical(artoo:::.storage_of(c(TRUE, FALSE)), "logical")
  expect_identical(artoo:::.storage_of(complex(1)), NA_character_)
})

# ---- shared codelist mapper: trim + case via decode_column() ----------------

.trim_spec <- function() {
  artoo_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "SEX",
      label = "Sex",
      data_type = "string",
      codelist_id = "CL.SEX",
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL.SEX",
      term = c("M", "F"),
      decode = c("Male", "Female"),
      stringsAsFactors = FALSE
    )
  )
}

test_that("decode_column trims whitespace by default and warns about variants", {
  df <- data.frame(SEX = c("M ", " F", "M"), stringsAsFactors = FALSE)
  expect_warning(
    out <- decode_column(df, .trim_spec(), "DM", from = "SEX"),
    class = "artoo_warning_codelist"
  )
  expect_identical(as.vector(out$SEX), c("Male", "Female", "Male"))
})

test_that("decode_column trim = FALSE restores exact matching", {
  df <- data.frame(SEX = c("M ", "F"), stringsAsFactors = FALSE)
  expect_error(
    decode_column(df, .trim_spec(), "DM", from = "SEX", trim = FALSE),
    class = "artoo_error_codelist"
  )
})

test_that("decode_column ignore_case = TRUE matches case variants and warns", {
  df <- data.frame(SEX = c("m", "F"), stringsAsFactors = FALSE)
  expect_error(
    decode_column(df, .trim_spec(), "DM", from = "SEX"),
    class = "artoo_error_codelist"
  )
  expect_warning(
    out <- decode_column(
      df,
      .trim_spec(),
      "DM",
      from = "SEX",
      ignore_case = TRUE
    ),
    class = "artoo_warning_codelist"
  )
  expect_identical(as.vector(out$SEX), c("Male", "Female"))
})

test_that("decode_column exact matches never warn", {
  df <- data.frame(SEX = c("M", "F"), stringsAsFactors = FALSE)
  expect_no_warning(
    decode_column(df, .trim_spec(), "DM", from = "SEX")
  )
})

# ---- Regression: locale-independent key sort (code review 2026-06-14) ----

test_that(".sort_keys uses radix (C-locale byte) order, not LC_COLLATE", {
  x <- data.frame(
    USUBJID = c("a", "B", "c", "A", "b"),
    V = 1:5,
    stringsAsFactors = FALSE
  )
  out <- artoo:::.sort_keys(x, list(keys = "USUBJID"))
  # Byte order puts uppercase before lowercase, deterministically across
  # locales; pre-fix order() collated by LC_COLLATE (e.g. a, A, b, B, c).
  expect_identical(out$USUBJID, c("A", "B", "a", "b", "c"))
})
