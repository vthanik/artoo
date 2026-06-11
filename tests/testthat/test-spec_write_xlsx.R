# Tests for the Pinnacle 21 Excel writer (.write_spec_xlsx via write_spec)
# and the Define-XML -> P21 bridge it composes with read_spec().

skip_if_not_installed("writexl")
skip_if_not_installed("readxl")

# A spec exercising every P21-representable slot.
.xlsx_spec <- function() {
  artoo_spec(
    datasets = data.frame(
      dataset = c("ADSL", "ADAE"),
      label = c("Subject-Level Analysis", "Adverse Events Analysis"),
      class = c("ADSL", "OCCDS"),
      structure = c("One record per subject", "One record per event"),
      keys = c("STUDYID USUBJID", "STUDYID USUBJID AETERM"),
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      order = c(1L, 2L, 1L, 2L),
      dataset = c("ADSL", "ADSL", "ADAE", "ADAE"),
      variable = c("USUBJID", "SEX", "USUBJID", "AESEV"),
      label = c("Unique Subject ID", "Sex", "Unique Subject ID", "Severity"),
      data_type = c("string", "string", "string", "string"),
      length = c(20L, 1L, 20L, 8L),
      mandatory = c(TRUE, FALSE, TRUE, NA),
      codelist_id = c(NA, "CL.SEX", NA, "CL.AESEV"),
      method_id = c(NA, NA, NA, "MT.SEV"),
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = c("CL.SEX", "CL.SEX", "CL.AESEV", "CL.AESEV"),
      order = c(1L, 2L, 1L, 2L),
      term = c("M", "F", "MILD", "MODERATE"),
      decode = c("Male", "Female", "Mild", "Moderate"),
      comment_id = c("COM.SEX", NA, NA, NA), # P21-unrepresentable on purpose
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = "MT.SEV",
      name = "Severity mapping",
      type = "Computation",
      description = "Worst severity across events.",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "COM.SEX",
      description = "Collected at screening.",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "DOC.SAP",
      title = "Statistical Analysis Plan",
      href = "sap.pdf",
      stringsAsFactors = FALSE
    ),
    standard = "ADaMIG 1.1"
  )
}

test_that("every emitted sheet name resolves through the reader's alias sets", {
  spec <- .xlsx_spec()
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  sheets <- readxl::excel_sheets(p)
  roles <- c(
    "datasets",
    "variables",
    "codelists",
    "methods",
    "comments",
    "documents"
  )
  for (role in roles) {
    expect_false(
      is.null(artoo:::.match_p21_sheet(
        sheets,
        artoo:::.p21_sheet_aliases[[role]]
      )),
      label = sprintf("role '%s' resolves", role)
    )
  }
})

test_that("a P21 xlsx round-trip preserves the representable surface", {
  spec <- .xlsx_spec()
  p <- withr::local_tempfile(fileext = ".xlsx")
  expect_identical(write_spec(spec, p), p)
  back <- read_spec(p)

  # The one standard rides the Datasets sheet's Standard column.
  expect_identical(spec_standard(back), "ADaMIG 1.1")

  # Datasets: P21-representable columns are identical.
  for (col in c("dataset", "label", "class", "structure", "keys")) {
    expect_identical(back@datasets[[col]], spec@datasets[[col]], label = col)
  }

  # Variables: identity on every P21-mapped column.
  for (col in c(
    "order",
    "dataset",
    "variable",
    "label",
    "data_type",
    "length",
    "mandatory",
    "codelist_id",
    "method_id"
  )) {
    expect_identical(back@variables[[col]], spec@variables[[col]], label = col)
  }

  # Codelists: id/order/term/decode survive.
  for (col in c("codelist_id", "order", "term", "decode")) {
    expect_identical(back@codelists[[col]], spec@codelists[[col]], label = col)
  }

  # Supporting metadata.
  expect_identical(back@methods$description, spec@methods$description)
  expect_identical(back@comments$description, spec@comments$description)
  expect_identical(back@documents$href, spec@documents$href)
})

test_that("a codelist comment_id is never emitted into the Codelists sheet", {
  # The P21 Codelists "Comment" column is free text, not a reference; the
  # writer must not exteriorise comment_id there, and a round-trip must not
  # resurrect it.
  spec <- .xlsx_spec()
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  cl_sheet <- as.data.frame(readxl::read_excel(p, sheet = "Codelists"))
  expect_false("Comment" %in% names(cl_sheet))
  back <- read_spec(p)
  expect_true(all(is.na(back@codelists$comment_id)))
})

test_that("empty optional slots omit their sheets", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "USUBJID", data_type = "string")
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  expect_setequal(readxl::excel_sheets(p), c("Datasets", "Variables"))
})

test_that("keys survive the xlsx round-trip into spec_keys()", {
  spec <- .xlsx_spec()
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  back <- read_spec(p)
  expect_identical(spec_keys(back, "ADAE"), c("STUDYID", "USUBJID", "AETERM"))
})

test_that("Define-XML to P21 is one read_spec |> write_spec composition", {
  skip_if_not_installed("xml2")
  define <- test_path("fixtures", "define21-sdtm.xml")
  skip_if_not(file.exists(define))
  spec <- read_spec(define)
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  back <- read_spec(p)
  expect_identical(spec_standard(back), spec_standard(spec))
  expect_setequal(spec_datasets(back), spec_datasets(spec))
  v_orig <- spec_variables(spec)
  v_back <- spec_variables(back)
  expect_identical(v_back$variable, v_orig$variable)
  expect_identical(v_back$data_type, v_orig$data_type)
  expect_identical(v_back$label, v_orig$label)
})

test_that("write_spec rejects an unknown extension", {
  spec <- .xlsx_spec()
  p <- withr::local_tempfile(fileext = ".csv")
  expect_error(write_spec(spec, p), class = "artoo_error_input")
  expect_snapshot(error = TRUE, write_spec(spec, p))
})
