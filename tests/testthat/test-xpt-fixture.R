# Real-SAS fixture: a genuine SAS-written xpt (CDISC pilot DM, committed under
# fixtures/) proves artoo reads real SAS bytes, not just its own round-trips.
# Provenance + SHA pin: data-raw/download-fixtures.R.

fixture_dm <- function() {
  test_path("fixtures", "sas-dm.xpt")
}

test_that("artoo reads a real SAS-written xpt (values + labels)", {
  skip_if_not(file.exists(fixture_dm()), "SAS fixture not present")
  dm <- read_xpt(fixture_dm())

  expect_identical(nrow(dm), 306L)
  expect_true(all(c("STUDYID", "USUBJID", "AGE", "SEX") %in% names(dm)))
  expect_identical(dm$USUBJID[1], "01-701-1015")
  expect_equal(dm$AGE[1], 63)
  expect_setequal(unique(dm$SEX), c("F", "M"))

  m <- get_meta(dm)
  expect_identical(m@dataset$name, "DM")
  expect_identical(m@dataset$records, 306L)
  expect_identical(m@columns$STUDYID$label, "Study Identifier")
  expect_identical(m@columns$AGE$label, "Age")
})

test_that("partial reads work on the real SAS fixture", {
  skip_if_not(file.exists(fixture_dm()), "SAS fixture not present")
  head5 <- read_xpt(fixture_dm(), col_select = c("AGE", "USUBJID"), n_max = 5)
  expect_identical(names(head5), c("USUBJID", "AGE")) # file order
  expect_identical(nrow(head5), 5L)
  expect_identical(get_meta(head5)@dataset$records, 5L)
})

test_that("pyreadstat agrees with artoo on the real SAS fixture", {
  skip_on_cran()
  skip_if_not(file.exists(fixture_dm()), "SAS fixture not present")
  py <- py_with_pyreadstat()
  skip_if(py == "", "python3 + pyreadstat not available")

  dm <- read_xpt(fixture_dm())
  script <- withr::local_tempfile(fileext = ".py")
  writeLines(
    c(
      "import sys, json, pyreadstat",
      "df, meta = pyreadstat.read_xport(sys.argv[1])",
      "out = {",
      "  'nrow': int(df.shape[0]),",
      "  'usubjid': [str(x) for x in df['USUBJID']],",
      "  'age': [float(x) for x in df['AGE']],",
      "  'studyid_label': meta.column_names_to_labels.get('STUDYID', ''),",
      "}",
      "print(json.dumps(out))"
    ),
    script
  )
  res <- system2(
    py,
    shQuote(c(script, fixture_dm())),
    stdout = TRUE,
    stderr = TRUE
  )
  parsed <- jsonlite::fromJSON(paste(res, collapse = "\n"))

  expect_identical(parsed$nrow, nrow(dm))
  expect_identical(parsed$usubjid, as.character(dm$USUBJID))
  expect_equal(parsed$age, as.numeric(dm$AGE))
  expect_identical(parsed$studyid_label, "Study Identifier")
})
