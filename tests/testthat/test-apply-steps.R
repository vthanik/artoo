# Branch coverage for the apply_spec steps and check_spec dimensions:
# decode directions + no-match policy, coercion warnings, key sorting, and
# each conformance finding. Driven by bundled CDISC demo data.

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

# spec with DM sort keys declared, to exercise .sort_keys().
keyed_spec <- function() {
  ds <- cdisc_datasets
  ds$keys <- NA_character_
  ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
  vport_spec(ds, cdisc_variables, codelists = cdisc_codelists)
}

# ---- decode_codelists -------------------------------------------------------

test_that("decode = to_decode maps codes to their decodes", {
  spec <- demo_spec()
  out <- apply_spec(cdisc_dm, spec, "DM", decode = "to_decode", check = "off")
  # F -> Female, M -> Male (codelist C66731).
  expect_setequal(unique(out$SEX), c("Female", "Male"))
})

test_that("decode = to_code reverses to_decode", {
  spec <- demo_spec()
  dec <- apply_spec(cdisc_dm, spec, "DM", decode = "to_decode", check = "off")
  back <- apply_spec(dec, spec, "DM", decode = "to_code", check = "off")
  plain <- apply_spec(cdisc_dm, spec, "DM", check = "off")
  expect_identical(back$SEX, plain$SEX)
})

test_that("decode no_match = error aborts on an unknown coded value", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z"
  expect_error(
    apply_spec(raw, spec, "DM", decode = "to_decode", no_match = "error"),
    class = "vport_error_codelist"
  )
})

test_that("decode no_match = keep retains the unmatched value", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z"
  out <- apply_spec(
    raw,
    spec,
    "DM",
    decode = "to_decode",
    no_match = "keep",
    check = "off"
  )
  expect_identical(out$SEX[1], "Z")
})

test_that("decode no_match = na blanks the unmatched value", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z"
  out <- apply_spec(
    raw,
    spec,
    "DM",
    decode = "to_decode",
    no_match = "na",
    check = "off"
  )
  expect_true(is.na(out$SEX[1]))
})

# ---- coerce_types -----------------------------------------------------------

test_that("coercion that introduces NA warns with vport_warning_coercion", {
  spec <- demo_spec()
  raw <- cdisc_adsl
  raw$AGE <- as.character(raw$AGE)
  raw$AGE[1] <- "not-a-number"
  expect_warning(
    apply_spec(raw, spec, "ADSL", check = "off"),
    class = "vport_warning_coercion"
  )
})

# ---- sort_keys --------------------------------------------------------------

test_that("sort_keys orders rows by the dataset keys and records them", {
  spec <- keyed_spec()
  raw <- cdisc_dm[sample.int(nrow(cdisc_dm)), , drop = FALSE]
  out <- apply_spec(raw, spec, "DM", check = "off")
  expect_identical(attr(out, "vport.sort"), c("STUDYID", "USUBJID"))
  expect_false(is.unsorted(out$USUBJID))
})

# ---- .apply_info ------------------------------------------------------------

test_that("a duplicated spec variable aborts with vport_error_spec", {
  vars <- cdisc_variables
  dup <- vars[vars$dataset == "DM" & vars$variable == "SEX", , drop = FALSE]
  vars2 <- rbind(vars, dup)
  spec <- vport_spec(cdisc_datasets, vars2, codelists = cdisc_codelists)
  expect_error(
    apply_spec(cdisc_dm, spec, "DM", check = "off"),
    class = "vport_error_spec"
  )
})

# ---- check_spec dimensions --------------------------------------------------

test_that("check_spec flags type_mismatch", {
  spec <- demo_spec()
  raw <- cdisc_adsl
  raw$AGE <- as.character(raw$AGE) # spec wants integer storage
  res <- check_spec(raw, spec, "ADSL")
  expect_true("AGE" %in% res$variable[res$check == "type_mismatch"])
})

test_that("check_spec flags length_overflow", {
  spec <- demo_spec()
  raw <- cdisc_adsl
  raw$SUBJID <- paste0(raw$SUBJID, "EXTRALONG") # spec length is 4
  res <- check_spec(raw, spec, "ADSL")
  expect_true("SUBJID" %in% res$variable[res$check == "length_overflow"])
})

test_that("check_spec flags codelist_membership", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z" # not in C66731
  res <- check_spec(raw, spec, "DM")
  hit <- res[res$check == "codelist_membership", , drop = FALSE]
  expect_true("SEX" %in% hit$variable)
  expect_identical(unique(hit$severity), "error")
})

test_that("apply_spec check = warn attaches findings and warns on errors", {
  spec <- demo_spec()
  raw <- cdisc_dm
  raw$SEX[1] <- "Z"
  expect_warning(
    out <- apply_spec(
      raw,
      spec,
      "DM",
      decode = "none",
      no_match = "error",
      check = "warn"
    ),
    class = "vport_warning_conformance"
  )
  findings <- attr(out, "vport.conformance")
  expect_true(any(findings$check == "codelist_membership"))
})

test_that("apply_spec rejects a non-character steps argument", {
  spec <- demo_spec()
  expect_error(
    apply_spec(cdisc_dm, spec, "DM", steps = 1L),
    class = "vport_error_input"
  )
})

test_that("check_spec rejects a non-data-frame x", {
  spec <- demo_spec()
  expect_error(check_spec(list(1), spec, "DM"), class = "vport_error_input")
})

test_that(".storage_of recognises integer and logical columns", {
  expect_identical(vport:::.storage_of(1L:3L), "integer")
  expect_identical(vport:::.storage_of(c(TRUE, FALSE)), "logical")
  expect_identical(vport:::.storage_of(complex(1)), NA_character_)
})
