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

test_that("write_spec(xlsx) preserves foreign columns (no silent drop)", {
  # The reader retains unmapped P21 columns (they ride along as character
  # columns); the writer must re-emit them so an xlsx round-trip does not
  # silently drop user columns. Regression: .p21_sheet_frame previously
  # projected only the mapped columns via intersect() and dropped the rest.
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = c("DM", "DM"),
      variable = c("USUBJID", "AGE"),
      data_type = c("string", "integer"),
      order = 1:2,
      sponsor_note = c("keep me", "and me"), # a column artoo does not model
      stringsAsFactors = FALSE
    )
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)

  vars_sheet <- as.data.frame(readxl::read_excel(p, sheet = "Variables"))
  # The foreign column is written out verbatim under its own header.
  expect_true("sponsor_note" %in% names(vars_sheet))
  # A canonical column with no P21 header (itemoid) stays unemitted.
  expect_false("itemoid" %in% names(vars_sheet))

  # And the foreign column survives a full round-trip back into the spec.
  back <- read_spec(p)
  v <- spec_variables(back)
  expect_identical(
    v$sponsor_note[match(c("USUBJID", "AGE"), v$variable)],
    c("keep me", "and me")
  )
})

test_that("the workbook Data Type column speaks the Define/ODM vocabulary", {
  # P21 / Define-XML have no "string": a character variable is "text". The
  # writer must re-encode the canonical dataType, and a read folds it back.
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      length = 11L,
      order = 1L,
      stringsAsFactors = FALSE
    )
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  vars <- as.data.frame(readxl::read_excel(p, sheet = "Variables"))
  expect_identical(vars[["Data Type"]][vars$Variable == "USUBJID"], "text")
  back <- read_spec(p)
  expect_identical(
    back@variables$data_type[back@variables$variable == "USUBJID"],
    "string"
  )
})

test_that("the dataType re-encoding collapse is locked (decimal/double/boolean/URI)", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("V1", "V2", "V3", "V4"),
      data_type = c("decimal", "double", "boolean", "URI"),
      order = 1:4,
      stringsAsFactors = FALSE
    )
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  vars <- as.data.frame(readxl::read_excel(p, sheet = "Variables"))
  dt <- vars[["Data Type"]][match(c("V1", "V2", "V3", "V4"), vars$Variable)]
  # decimal/double -> float; boolean/URI -> text (ODM has no other spelling).
  expect_identical(dt, c("float", "float", "text", "text"))
})

test_that("a date variable carries no Length cell (Define length rule)", {
  # Define-XML Length is present only for text/integer/float; a date variable
  # with no declared length emits a blank Length cell.
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("USUBJID", "RFSTDTC"),
      data_type = c("string", "date"),
      length = c(11L, NA_integer_),
      order = 1:2,
      stringsAsFactors = FALSE
    )
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  vars <- as.data.frame(readxl::read_excel(p, sheet = "Variables"))
  expect_equal(vars[["Length"]][vars$Variable == "USUBJID"], 11)
  expect_true(is.na(vars[["Length"]][vars$Variable == "RFSTDTC"]))
})

test_that("a codelist comment_id round-trips through the Comment column", {
  # The Codelists "Comment" column is a Comment-ID reference, like the ones
  # on Variables and Datasets: the workbook format documents it as an id
  # matching a row on the Comments sheet, and it becomes
  # `CodeList/@def:CommentOID`. artoo read it as free text and left the
  # column unmapped, which produced a codelist with no comment and a
  # CommentDef with nothing pointing at it.
  spec <- artoo_spec(
    data.frame(dataset = "DM", stringsAsFactors = FALSE),
    data.frame(
      dataset = "DM",
      variable = "SEX",
      data_type = "string",
      codelist_id = "CL.SEX",
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL.SEX",
      name = "Sex",
      data_type = "text",
      term = c("F", "M"),
      decode = c("Female", "Male"),
      comment_id = "COM.SEX",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "COM.SEX",
      description = "Collected on the demography page.",
      stringsAsFactors = FALSE
    )
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  suppressWarnings(write_spec(spec, p))
  cl_sheet <- as.data.frame(readxl::read_excel(p, sheet = "Codelists"))
  expect_true("Comment" %in% names(cl_sheet))
  expect_identical(unique(cl_sheet[["Comment"]]), "COM.SEX")
  back <- suppressWarnings(read_spec(p))
  expect_identical(unique(back@codelists$comment_id), "COM.SEX")
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
  spec <- suppressWarnings(read_spec(define))
  p <- withr::local_tempfile(fileext = ".xlsx")
  # The workbook has no sheet for the structural slots, so this composition
  # legitimately drops them -- and must say so rather than truncating in
  # silence.
  expect_warning(write_spec(spec, p), class = "artoo_warning_spec")
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

test_that("an empty spec cannot become a P21 workbook", {
  empty <- artoo_spec(
    data.frame(dataset = character(0)),
    data.frame(
      dataset = character(0),
      variable = character(0),
      data_type = character(0)
    )
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  expect_error(write_spec(empty, p), class = "artoo_error_spec")
  expect_snapshot(error = TRUE, write_spec(empty, p))
})

test_that("a values slot with no P21-mapped columns omits the sheet", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "USUBJID", data_type = "string"),
    values = data.frame(bespoke = "x", stringsAsFactors = FALSE)
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  expect_false("ValueLevel" %in% readxl::excel_sheets(p))
})

test_that("the study table round-trips through the P21 Define sheet", {
  # The writer emits the study row as a Define sheet (Attribute/Value, P21
  # spellings); the reader pivots it back and the constructor canonicalises
  # the names, so study metadata survives the xlsx interchange.
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    study = data.frame(
      study_name = "CDISC-Sample",
      study_description = "CDISC-Sample Data Definition",
      protocol_name = "CDISC-Sample",
      stringsAsFactors = FALSE
    )
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  expect_true("Define" %in% readxl::excel_sheets(p))
  back <- read_spec(p)
  expect_identical(spec_study(back, "study_name"), "CDISC-Sample")
  expect_identical(
    spec_study(back, "study_description"),
    "CDISC-Sample Data Definition"
  )
  expect_identical(spec_study(back, "protocol_name"), "CDISC-Sample")
})

test_that("a spec with no study row writes no Define sheet", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "USUBJID", data_type = "string")
  )
  p <- withr::local_tempfile(fileext = ".xlsx")
  write_spec(spec, p)
  expect_false("Define" %in% readxl::excel_sheets(p))
})

test_that("a method's formal expression survives a workbook (#p12-p21)", {
  # The Methods sheet carries one formal expression per method, in its
  # context and code columns. artoo read those two columns into the methods
  # table and then consumed them nowhere -- the Define-XML writer builds
  # FormalExpression only from the separate expressions table -- so a method
  # authored with an expression produced a define.xml with none, silently,
  # while the write in the other direction warned that no sheet could hold
  # what it was in the middle of writing.
  spec <- artoo_spec(
    data.frame(
      dataset = "ADSL",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    data.frame(
      dataset = "ADSL",
      variable = "AGEGR1",
      data_type = "string",
      origin = "Derived",
      method_id = "MT.AGEGR1",
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = "MT.AGEGR1",
      name = "Age group",
      type = "Computation",
      description = "Banded age",
      expression_context = "SAS 9.4",
      expression_code = "if age < 65 then agegr1 = '<65';",
      stringsAsFactors = FALSE
    )
  )
  # The inline pair is folded into the expressions table at construction, so
  # every consumer downstream sees one representation.
  expect_identical(nrow(spec@method_expressions), 1L)
  expect_identical(spec@method_expressions$context, "SAS 9.4")

  path <- file.path(withr::local_tempdir(), "define.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = "2020-01-01 00:00:00", stylesheet = FALSE)
  ))
  expression <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='FormalExpression']"
  )
  expect_identical(xml2::xml_attr(expression, "Context"), "SAS 9.4")
  expect_match(xml2::xml_text(expression), "agegr1", fixed = TRUE)

  # ...and back out to a workbook, in the two columns it came from.
  book <- withr::local_tempfile(fileext = ".xlsx")
  suppressWarnings(write_spec(spec, book))
  sheet <- readxl::read_excel(book, sheet = "Methods")
  expect_identical(sheet[["Expression Context"]], "SAS 9.4")
  expect_match(sheet[["Expression Code"]], "agegr1", fixed = TRUE)
})

test_that("a method with two expressions loses the second, loudly (#p12-p21)", {
  # The sheet has one context and one code column, so a method carrying two
  # formal expressions keeps the first. That is a real loss and it is named.
  spec <- artoo_spec(
    data.frame(
      dataset = "ADSL",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    data.frame(
      dataset = "ADSL",
      variable = "BMI",
      data_type = "float",
      origin = "Derived",
      method_id = "MT.BMI",
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = "MT.BMI",
      name = "BMI",
      type = "Computation",
      description = "Body mass index",
      stringsAsFactors = FALSE
    ),
    method_expressions = data.frame(
      method_id = "MT.BMI",
      order = 1:2,
      context = c("SAS 9.4", "R 4.5"),
      code = c("bmi = wt / ht**2;", "bmi <- wt / ht^2"),
      stringsAsFactors = FALSE
    )
  )
  book <- withr::local_tempfile(fileext = ".xlsx")
  expect_warning(write_spec(spec, book), "MT.BMI")
  back <- suppressWarnings(read_spec(book))
  expect_identical(nrow(back@method_expressions), 1L)
  expect_identical(back@method_expressions$context, "SAS 9.4")
})
