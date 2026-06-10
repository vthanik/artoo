# Tests for read_spec() (native JSON + Pinnacle 21 Excel).

# ---- Native JSON round-trip (F1) ----------------------------------------

test_that("read_spec() round-trips a spec through JSON identically (F1)", {
  skip_if_not_installed("jsonlite")
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  expect_identical(read_spec(p), spec)
})

test_that("read_spec() round-trips value-level and study slots (F1)", {
  skip_if_not_installed("jsonlite")
  vlm <- data.frame(
    dataset = "ADSL",
    variable = "PARAMCD",
    where_clause = "PARAMCD EQ HEIGHT",
    label = "Height",
    stringsAsFactors = FALSE
  )
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = "CDISCPILOT01", standard = "ADaMIG 1.1"),
    values = vlm
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  back <- read_spec(p)
  expect_identical(back, spec)
  expect_s3_class(back@values, "data.frame")
})

test_that("vport_spec() demotes a tibble value-level table to plain df (H2)", {
  skip_if_not_installed("tibble")
  vlm <- tibble::tibble(dataset = "ADSL", variable = "PARAMCD", label = "L")
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists,
    values = vlm
  )
  expect_s3_class(spec@values, "data.frame")
  expect_false(inherits(spec@values, "tbl_df"))
})

test_that("read_spec() preserves non-ASCII labels and empty strings (H8)", {
  skip_if_not_installed("jsonlite")
  vars <- data.frame(
    dataset = "DM",
    variable = c("A", "B"),
    data_type = c("string", "string"),
    label = c("Naïve label", ""),
    stringsAsFactors = FALSE
  )
  spec <- vport_spec(data.frame(dataset = "DM"), vars)
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  back <- read_spec(p)
  lbl <- back@variables$label
  expect_identical(lbl[back@variables$variable == "A"], "Naïve label")
  expect_identical(lbl[back@variables$variable == "B"], "")
})

test_that("read_spec() reconstructs empty optional slots", {
  skip_if_not_installed("jsonlite")
  spec <- vport_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  back <- read_spec(p)
  expect_identical(back, spec)
  expect_null(back@values)
  expect_equal(nrow(back@codelists), 0L)
})

test_that("read_spec() warns on an unrecognised version but still reads (H10)", {
  skip_if_not_installed("jsonlite")
  spec <- vport_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  txt <- gsub(
    '("vport_spec_version":\\s*)"1"',
    '\\1"99"',
    readLines(p)
  )
  writeLines(txt, p)
  expect_warning(s <- read_spec(p), class = "vport_warning_spec")
  expect_true(is_vport_spec(s))
})

test_that("read_spec() rejects bad paths and unsupported extensions", {
  expect_error(read_spec(42), class = "vport_error_input")
  expect_error(read_spec("does-not-exist.json"), class = "vport_error_input")
  tmp <- withr::local_tempfile(fileext = ".csv")
  file.create(tmp)
  expect_error(read_spec(tmp), class = "vport_error_input")
  expect_snapshot(read_spec(tmp), error = TRUE)
})

# ---- Pinnacle 21 Excel (integration, committed fixture) -----------------

test_that("read_spec() ingests a P21 Excel spec with merged cells", {
  skip_if_not_installed("readxl")
  spec <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))
  expect_true(is_vport_spec(spec))
  expect_setequal(spec_datasets(spec), c("ADSL", "DM"))

  v <- spec_variables(spec)
  # H4: the merged Dataset column is forward-filled to continuation rows.
  expect_identical(v$dataset[v$variable == "AGE"], "ADSL")
  expect_identical(
    unique(v$dataset[v$variable == "USUBJID" & v$dataset == "DM"]),
    "DM"
  )
  # H1: a Define-XML partialDatetime canonicalises to datetime.
  expect_identical(v$data_type[v$variable == "TRTSDTM"], "datetime")
  # H6: a space-padded codelist id is trimmed and resolves.
  expect_identical(
    v$codelist_id[v$variable == "SEX" & v$dataset == "ADSL"],
    "C66731"
  )
  # Mandatory "Yes" coerces to TRUE.
  expect_true(v$mandatory[v$variable == "STUDYID"][1])
})

test_that("read_spec() recovers all terms of a merged-id codelist (H4/H5)", {
  skip_if_not_installed("readxl")
  spec <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))
  cl <- spec_codelists(spec, "C66731")
  expect_setequal(cl$term, c("F", "M", "U"))
  expect_setequal(cl$decode, c("Female", "Male", "Unknown"))
})

test_that("read_spec() populates methods/comments/documents slots", {
  skip_if_not_installed("readxl")
  spec <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))
  # Trailing blank-key method row is dropped (H4): MT.TRTSDTM + MT.DM only.
  expect_setequal(spec_methods(spec)$method_id, c("MT.TRTSDTM", "MT.DM"))
  expect_identical(spec_comments(spec)$comment_id, "C.BLANK")
  expect_identical(spec_documents(spec)$document_id, "DOC.SAP")
  # FK columns mapped onto variables.
  v <- spec_variables(spec)
  expect_identical(v$method_id[v$variable == "TRTSDTM"], "MT.TRTSDTM")
  expect_identical(
    v$method_id[v$variable == "USUBJID" & v$dataset == "DM"],
    "MT.DM"
  )
  # The DM method carries a blank description (a crafted defect).
  m <- spec_methods(spec)
  expect_true(is.na(m$description[m$method_id == "MT.DM"]))
})

test_that("read_spec() round-trips the new slots through JSON (F1)", {
  skip_if_not_installed("jsonlite")
  spec <- vport_spec(
    data.frame(dataset = "ADSL"),
    data.frame(
      dataset = "ADSL",
      variable = "AGEGR1",
      data_type = "string",
      method_id = "MT.AGEGR1",
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = "MT.AGEGR1",
      description = "Age group from AGE.",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "C1",
      description = "A note.",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "SAP",
      title = "SAP",
      href = "sap.pdf",
      stringsAsFactors = FALSE
    )
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  expect_identical(read_spec(p), spec)
})

test_that("read_spec() pivots the P21 Define sheet into a study row", {
  skip_if_not_installed("readxl")
  spec <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))
  expect_identical(spec_study(spec, "StudyName"), "CDISCPILOT01")
})

# ---- P21 internals (fast unit tests of the hardening branches) ----------

test_that(".match_p21_sheet resolves spelling and spacing variants (H3)", {
  al <- vport:::.p21_sheet_aliases$variables
  expect_identical(
    vport:::.match_p21_sheet("Variable Level Metadata", al),
    "Variable Level Metadata"
  )
  expect_identical(vport:::.match_p21_sheet("VARIABLES", al), "VARIABLES")
  expect_null(vport:::.match_p21_sheet("Datasets", al))
})

test_that(".fill_down leaves a leading NA, and .check_filled fails loud (H4)", {
  df <- data.frame(
    dataset = c(NA, "ADSL", NA),
    variable = c("A", "B", "C"),
    stringsAsFactors = FALSE
  )
  filled <- vport:::.fill_down(df, "dataset")
  expect_identical(filled$dataset, c(NA, "ADSL", "ADSL"))
  expect_error(
    vport:::.check_filled(filled, "dataset", "Variables", rlang::current_env()),
    class = "vport_error_spec"
  )
})

test_that(".require_p21_sheet errors on an absent or empty required sheet (H7)", {
  expect_error(
    vport:::.require_p21_sheet(
      NULL,
      NULL,
      "Datasets",
      "X",
      rlang::current_env()
    ),
    class = "vport_error_spec"
  )
  expect_error(
    vport:::.require_p21_sheet(
      data.frame(),
      "Datasets",
      "Datasets",
      "Datasets",
      rlang::current_env()
    ),
    class = "vport_error_spec"
  )
})
