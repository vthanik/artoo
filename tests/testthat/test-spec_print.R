# Tests for the vport_spec / vport_meta print + format methods.
# The S7 print dispatch only fires in an installed build; the renderers
# (.format_spec / .format_meta) are plain functions, so they are snapshot-
# tested directly here (mirrors test-spec_check_report.R).

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

test_that(".format_spec renders counts and a dataset preview", {
  expect_snapshot(cat(vport:::.format_spec(demo_spec()), sep = "\n"))
})

test_that(".format_meta renders dataset, records, columns, keys, preview", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
  expect_snapshot(cat(vport:::.format_meta(get_meta(adsl)), sep = "\n"))
})

test_that(".preview_names truncates a long list and handles the empty case", {
  expect_identical(vport:::.preview_names(character(0)), "(none)")
  expect_identical(vport:::.preview_names(c("A", "B")), "A, B")
  expect_match(
    vport:::.preview_names(LETTERS[1:10], n = 3L),
    "^A, B, C \\(\\+7 more\\)$"
  )
})

test_that(".format_spec surfaces study, support metadata, and value-level", {
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
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
  out <- vport:::.format_spec(spec)
  expect_true(any(grepl("Study: CDISCPILOT01", out)))
  expect_true(any(grepl("^Methods: 1", out)))
  expect_true(any(grepl("^Comments: 1", out)))
  expect_true(any(grepl("^Documents: 1", out)))
  expect_true(any(grepl("^Value-level: 1", out)))
})

test_that(".format_spec treats a blank studyid as unspecified", {
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = NA_character_, stringsAsFactors = FALSE)
  )
  expect_true(any(grepl(
    "Study: \\(unspecified\\)",
    vport:::.format_spec(spec)
  )))
})

test_that(".format_meta handles a keyed, label-less dataset", {
  meta <- vport:::vport_meta_class(
    dataset = list(name = "DM", keys = c("STUDYID", "USUBJID")),
    columns = list(
      STUDYID = list(name = "STUDYID", dataType = "string"),
      USUBJID = list(name = "USUBJID", dataType = "string")
    )
  )
  out <- vport:::.format_meta(meta)
  expect_identical(out[2], "Dataset: DM") # no label, no parenthetical
  expect_true(any(grepl("^Keys:    STUDYID, USUBJID", out)))
  # No records field when the meta carries none.
  expect_false(any(grepl("^Records:", out)))
})

test_that("the S7 print and format methods run", {
  spec <- demo_spec()
  meta <- get_meta(apply_spec(cdisc_dm, spec, "DM", on_error = "off"))
  # Dispatch fires under an installed build (covr); harmless under load_all.
  expect_output(print(spec))
  expect_output(print(meta))
  expect_no_error(format(spec))
  expect_no_error(format(meta))
})
