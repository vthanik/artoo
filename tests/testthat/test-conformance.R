# conformance(): the documented accessor for the findings apply_spec()
# attaches, plus the vport_findings print method.

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

test_that("conformance() returns the findings apply_spec attached", {
  spec <- demo_spec()
  dm <- suppressWarnings(apply_spec(cdisc_dm, spec, "DM"))
  f <- conformance(dm)
  expect_s3_class(f, "vport_findings")
  expect_s3_class(f, "data.frame")
  expect_named(
    f,
    c("check", "dimension", "severity", "dataset", "variable", "message")
  )
  expect_identical(f, .as_vport_findings(attr(dm, "vport.conformance")))
})

test_that("conformance() aborts with a hint when no findings are attached", {
  spec <- demo_spec()
  off <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  expect_error(conformance(off), class = "vport_error_input")
  expect_snapshot(error = TRUE, conformance(off))
})

test_that("check_spec returns a printable vport_findings frame", {
  spec <- demo_spec()
  f <- check_spec(cdisc_dm, spec, "DM")
  expect_s3_class(f, "vport_findings")
  # Ordinary data frame semantics are intact.
  expect_true(is.data.frame(f[f$severity == "error", ]))
})

test_that("the vport_findings print renders a sectioned report", {
  spec <- demo_spec()
  dm <- suppressWarnings(apply_spec(cdisc_dm, spec, "DM"))
  expect_snapshot(print(conformance(dm)))
  # A conformed frame prints the all-clear.
  clean <- apply_spec(
    cdisc_adsl,
    spec,
    "ADSL",
    conformance = "off"
  )
  expect_snapshot(print(check_spec(clean, spec, "ADSL")))
})
