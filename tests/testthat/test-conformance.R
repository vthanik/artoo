# conformance(): the documented accessor for the findings apply_spec()
# attaches, plus the artoo_findings print method.

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

test_that("conformance() returns the findings apply_spec attached", {
  spec <- demo_sdtm_spec()
  dm <- suppressWarnings(apply_spec(cdisc_dm, spec, "DM"))
  f <- conformance(dm)
  expect_s3_class(f, "artoo_findings")
  expect_s3_class(f, "data.frame")
  expect_named(
    f,
    c("check", "dimension", "severity", "dataset", "variable", "message")
  )
  expect_identical(f, .as_artoo_findings(attr(dm, "artoo.conformance")))
})

test_that("conformance() aborts with a hint when no findings are attached", {
  spec <- demo_sdtm_spec()
  off <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  expect_error(conformance(off), class = "artoo_error_input")
  expect_snapshot(error = TRUE, conformance(off))
})

test_that("check_spec returns a printable artoo_findings frame", {
  spec <- demo_sdtm_spec()
  f <- check_spec(cdisc_dm, spec, "DM")
  expect_s3_class(f, "artoo_findings")
  # Ordinary data frame semantics are intact.
  expect_true(is.data.frame(f[f$severity == "error", ]))
})

test_that("the artoo_findings print renders a sectioned report", {
  sdtm <- demo_sdtm_spec()
  dm <- suppressWarnings(apply_spec(cdisc_dm, sdtm, "DM"))
  expect_snapshot(print(conformance(dm)))
  # A conformed frame prints the all-clear.
  adam <- demo_adam_spec()
  clean <- apply_spec(
    cdisc_adsl,
    adam,
    "ADSL",
    conformance = "off"
  )
  expect_snapshot(print(check_spec(clean, adam, "ADSL")))
})

test_that("print renders sections when findings exist, and falls back on subsets", {
  spec <- demo_sdtm_spec()
  raw <- cdisc_dm
  raw$NOTSPEC <- 1
  raw$SEX[1] <- "X"
  f <- check_spec(raw, spec, "DM")
  expect_gt(nrow(f), 0L)
  expect_snapshot(print(f))
  # A column subset keeps the class but not the report shape: plain print.
  sub <- f[, c("check", "severity")]
  expect_output(print(sub), "check")
})
