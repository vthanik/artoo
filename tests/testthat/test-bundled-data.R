# The bundled spec/data contract: every shipped demo dataset conforms to
# its shipped spec in abort mode, and the shipped P21 workbooks are the
# write_spec() images of the bundled spec objects.

test_that("every bundled dataset conforms to its bundled spec (abort mode)", {
  pairs <- list(
    list(data = cdisc_adsl, spec = adam_spec, ds = "ADSL"),
    list(data = cdisc_adae, spec = adam_spec, ds = "ADAE"),
    list(data = cdisc_dm, spec = sdtm_spec, ds = "DM"),
    list(data = cdisc_vs, spec = sdtm_spec, ds = "VS"),
    list(data = cdisc_ts, spec = sdtm_spec, ds = "TS"),
    list(data = cdisc_suppdm, spec = sdtm_spec, ds = "SUPPDM")
  )
  for (p in pairs) {
    out <- suppressMessages(suppressWarnings(
      apply_spec(p$data, p$spec, p$ds, conformance = "abort")
    ))
    expect_s3_class(out, "data.frame")
    expect_true(is_artoo_meta(get_meta(out)), label = p$ds)
  }
})

test_that("the bundled specs are single-standard and validated", {
  expect_identical(spec_standard(adam_spec), "ADaMIG 1.1")
  expect_identical(spec_standard(sdtm_spec), "SDTMIG 3.1.2")
  expect_setequal(spec_datasets(adam_spec), c("ADSL", "ADAE"))
  expect_setequal(spec_datasets(sdtm_spec), c("TS", "DM", "VS", "SUPPDM"))
})

test_that("the shipped P21 workbooks read back to the bundled specs", {
  skip_if_not_installed("readxl")
  for (nm in c("adam", "sdtm")) {
    p <- system.file(
      "extdata",
      sprintf("%s-spec.xlsx", nm),
      package = "artoo"
    )
    skip_if_not(nzchar(p))
    spec <- get(paste0(nm, "_spec"))
    back <- read_spec(p)
    expect_identical(spec_standard(back), spec_standard(spec))
    expect_setequal(spec_datasets(back), spec_datasets(spec))
    expect_identical(back@variables$variable, spec@variables$variable)
    expect_identical(back@variables$data_type, spec@variables$data_type)
  }
})

test_that("the bundled specs carry the Define study block (canonical fields)", {
  # Regression: adam_spec printed "Study: (unspecified)" because the
  # Define-XML reader's study_name never reached the print/meta consumers.
  expect_identical(spec_study(adam_spec, "study_name"), "CDISC-Sample")
  expect_identical(spec_study(adam_spec, "protocol_name"), "CDISC-Sample")
  expect_identical(
    spec_study(adam_spec, "study_description"),
    "CDISC-Sample Data Definition"
  )
  expect_identical(spec_study(sdtm_spec, "study_name"), "CDISC01_1")
  expect_true(any(grepl(
    "Study: CDISC-Sample",
    artoo:::.format_spec(adam_spec),
    fixed = TRUE
  )))
})

test_that("the shipped P21 workbooks carry the study through their Define sheet", {
  skip_if_not_installed("readxl")
  p <- system.file("extdata", "adam-spec.xlsx", package = "artoo")
  skip_if_not(nzchar(p))
  expect_true("Define" %in% readxl::excel_sheets(p))
  back <- read_spec(p)
  expect_identical(spec_study(back, "study_name"), "CDISC-Sample")
})
