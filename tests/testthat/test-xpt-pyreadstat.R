# External-oracle cross-check: prove vport's xpt bytes are real SAS XPORT by
# reading them with pyreadstat (a third-party readstat-based reader), not just
# round-tripping against vport itself. Skipped on CRAN and wherever python /
# pyreadstat is absent (haven is banned, so this is the only real-SAS oracle).
# py_with_pyreadstat() lives in helper-pyreadstat.R (shared with the fixture).

test_that("a vport-written xpt reads correctly in pyreadstat", {
  skip_on_cran()
  py <- py_with_pyreadstat()
  skip_if(py == "", "python3 + pyreadstat not available")

  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  dm <- apply_spec(cdisc_dm, spec, "DM", on_error = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p, created = as.POSIXct("2020-01-01", tz = "UTC"))

  script <- withr::local_tempfile(fileext = ".py")
  writeLines(
    c(
      "import sys, json, pyreadstat",
      "df, meta = pyreadstat.read_xport(sys.argv[1])",
      "out = {",
      "  'nrow': int(df.shape[0]),",
      "  'cols': list(df.columns),",
      "  'usubjid': [str(x) for x in df['USUBJID']],",
      "  'age': [float(x) for x in df['AGE']],",
      "  'studyid_label': meta.column_names_to_labels.get('STUDYID', ''),",
      "}",
      "print(json.dumps(out))"
    ),
    script
  )
  res <- system2(py, shQuote(c(script, p)), stdout = TRUE, stderr = TRUE)
  parsed <- jsonlite::fromJSON(paste(res, collapse = "\n"))

  expect_identical(parsed$nrow, nrow(dm))
  expect_true(all(c("STUDYID", "USUBJID", "AGE") %in% parsed$cols))
  expect_identical(parsed$usubjid, as.character(dm$USUBJID))
  expect_equal(parsed$age, as.numeric(dm$AGE))
  expect_identical(parsed$studyid_label, "Study Identifier")
})

test_that("a pyreadstat-written xpt reads correctly in vport", {
  skip_on_cran()
  py <- py_with_pyreadstat()
  skip_if(py == "", "python3 + pyreadstat not available")

  xpt <- withr::local_tempfile(fileext = ".xpt")
  script <- withr::local_tempfile(fileext = ".py")
  writeLines(
    c(
      "import sys, pandas as pd, pyreadstat",
      "df = pd.DataFrame({",
      "  'SUBJID': ['001', '002', '003'],",
      "  'AVAL': [1.5, 2.5, 3.5],",
      "})",
      "pyreadstat.write_xport(df, sys.argv[1], column_labels={'SUBJID': 'Subject', 'AVAL': 'Value'})"
    ),
    script
  )
  status <- system2(py, shQuote(c(script, xpt)), stdout = FALSE, stderr = FALSE)
  skip_if(status != 0, "pyreadstat.write_xport failed")

  back <- read_xpt(xpt)
  expect_true(all(c("SUBJID", "AVAL") %in% names(back)))
  expect_identical(as.character(back$SUBJID), c("001", "002", "003"))
  expect_equal(as.numeric(back$AVAL), c(1.5, 2.5, 3.5))
})
