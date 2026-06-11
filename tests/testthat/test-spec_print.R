# Tests for the artoo_spec / artoo_meta print + format methods.
# The S7 print dispatch only fires in an installed build; the renderers
# (.format_spec / .format_meta) are plain functions, so they are snapshot-
# tested directly here (mirrors test-spec_check_report.R).

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

test_that(".format_spec renders counts and a dataset preview", {
  expect_snapshot(cat(artoo:::.format_spec(demo_adam_spec()), sep = "\n"))
})

test_that(".format_meta renders dataset, records, columns, keys, preview", {
  spec <- demo_adam_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  expect_snapshot(cat(artoo:::.format_meta(get_meta(adsl)), sep = "\n"))
})

test_that(".preview_names truncates a long list and handles the empty case", {
  expect_identical(artoo:::.preview_names(character(0)), "(none)")
  expect_identical(artoo:::.preview_names(c("A", "B")), "A, B")
  expect_match(
    artoo:::.preview_names(LETTERS[1:10], n = 3L),
    "^A, B, C \\(\\+7 more\\)$"
  )
})

test_that(".format_spec surfaces study, support metadata, and value-level", {
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = "CDISCPILOT01", stringsAsFactors = FALSE),
    methods = data.frame(method_id = "MT.AGE", stringsAsFactors = FALSE),
    comments = data.frame(comment_id = "C1", stringsAsFactors = FALSE),
    documents = data.frame(document_id = "D1", stringsAsFactors = FALSE),
    values = data.frame(
      dataset = "ADSL",
      variable = "AVAL",
      stringsAsFactors = FALSE
    )
  )
  out <- artoo:::.format_spec(spec)
  expect_true(any(grepl("Study: CDISCPILOT01", out)))
  expect_true(any(grepl("^Methods: 1", out)))
  expect_true(any(grepl("^Comments: 1", out)))
  expect_true(any(grepl("^Documents: 1", out)))
  expect_true(any(grepl("^Value-level: 1", out)))
})

test_that(".format_spec shows the study from a Define-sourced study frame", {
  # Regression: a spec read from Define-XML carries study_name, and the
  # bundled adam_spec printed "Study: (unspecified)" despite holding
  # "CDISC-Sample" — print must read the canonical field.
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists,
    study = data.frame(
      study_name = "CDISC-Sample",
      protocol_name = "CDISC-Sample",
      stringsAsFactors = FALSE
    )
  )
  expect_true(any(grepl(
    "Study: CDISC-Sample",
    artoo:::.format_spec(spec),
    fixed = TRUE
  )))
})

test_that(".format_spec treats a blank studyid as unspecified", {
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = NA_character_, stringsAsFactors = FALSE)
  )
  expect_true(any(grepl(
    "Study: \\(unspecified\\)",
    artoo:::.format_spec(spec)
  )))
})

test_that(".format_meta handles a keyed, label-less dataset", {
  meta <- artoo:::artoo_meta_class(
    dataset = list(name = "DM", keys = c("STUDYID", "USUBJID")),
    columns = list(
      STUDYID = list(name = "STUDYID", dataType = "string"),
      USUBJID = list(name = "USUBJID", dataType = "string")
    )
  )
  out <- artoo:::.format_meta(meta)
  expect_identical(out[2], "Dataset: DM") # no label, no parenthetical
  expect_true(any(grepl("^Keys:    STUDYID, USUBJID", out)))
  # No records field when the meta carries none.
  expect_false(any(grepl("^Records:", out)))
})

test_that("the S7 print and format methods run", {
  spec <- demo_sdtm_spec()
  meta <- get_meta(apply_spec(cdisc_dm, spec, "DM", conformance = "off"))
  # Dispatch fires under an installed build (covr); harmless under load_all.
  expect_output(print(spec))
  expect_output(print(meta))
  expect_no_error(format(spec))
  expect_no_error(format(meta))
})
