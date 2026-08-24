# Pinnacle 21 workbook -> define.xml, end to end.
#
# Three workbooks x two versions x four gates. This is the test that says the
# feature works on real input rather than on the CDISC reference documents,
# which are unrepresentatively complete.
#
# The four gates:
#   1. the write succeeds, or refuses for a reason the schema forces
#   2. the document is schema-valid against the bundled CDISC schemas
#   3. define_lint() reports zero DANGLING references -- orphans are allowed,
#      because a workbook routinely defines codelists and comments nothing
#      uses, and dropping them would lose the author's work
#   4. a structural digest is snapshotted, so a change to what artoo emits
#      shows up as a three-line diff naming the element that moved
#
# Plus the degradation contract: a workbook missing submission-grade columns
# still produces a valid document, and the write names every column nothing
# fills.

FROZEN_P21 <- "2020-01-01 00:00:00"

p21_workbooks <- function() {
  c(
    adam = system.file("extdata", "adam-spec.xlsx", package = "artoo"),
    sdtm = system.file("extdata", "sdtm-spec.xlsx", package = "artoo"),
    partial = testthat::test_path("fixtures", "p21_adam_spec.xlsx")
  )
}

# Element census plus the reference-integrity table: enough to notice a
# structural change, small enough to read.
define_digest <- function(path) {
  doc <- xml2::read_xml(path)
  nodes <- xml2::xml_find_all(doc, "//*")
  census <- table(vapply(nodes, xml2::xml_name, character(1)))
  findings <- define_lint(path)@findings
  list(
    elements = as.list(census[order(names(census))]),
    lint = as.list(sort(table(findings$check)))
  )
}

test_that("every workbook writes a valid Define-XML with no dangling reference", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("readxl")
  for (name in names(p21_workbooks())) {
    workbook <- p21_workbooks()[[name]]
    skip_if(!nzchar(workbook) || !file.exists(workbook), "workbook not bundled")
    spec <- suppressWarnings(read_spec(workbook))
    for (version in c("2.0", "2.1")) {
      label <- paste(name, version)
      out <- file.path(withr::local_tempdir(), "define.xml")
      # The one refusal the schema forces: Define-XML 2.0 requires a standard
      # name and version on MetaDataVersion, and the partial workbook names
      # none. There is nothing to derive it from, so artoo refuses rather
      # than inventing a standard the sponsor never claimed.
      if (identical(name, "partial") && identical(version, "2.0")) {
        expect_error(
          write_spec(spec, out, version = version, created = FROZEN_P21),
          class = "artoo_error_define"
        )
        next
      }
      suppressWarnings(
        write_spec(spec, out, version = version, created = FROZEN_P21)
      )
      report <- validate_define(out)
      expect_true(report@summary$valid, info = label)
      expect_identical(report@summary$define_version, version, info = label)
      checks <- define_lint(out)@findings$check
      expect_false(any(grepl("dangling", checks)), info = label)
    }
  }
})

test_that("a workbook reaches a fixed point after one canonicalisation", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("readxl")
  # Identity is the wrong invariant twice over. A workbook carries less than
  # a define.xml, so the writer fills schema-required fields it left out; and
  # a workbook's physical ROW order is not its OrderNumber order, which is
  # the order the writer emits in. The first write therefore canonicalises.
  # What must hold is that it converges: after that one pass, writing again
  # changes nothing.
  for (name in c("adam", "sdtm")) {
    workbook <- p21_workbooks()[[name]]
    skip_if(!nzchar(workbook) || !file.exists(workbook), "workbook not bundled")
    dir <- withr::local_tempdir()
    out <- file.path(dir, paste0("pass", 1:3, ".xml"))
    spec <- suppressWarnings(read_spec(workbook))
    for (i in seq_along(out)) {
      suppressWarnings(write_spec(spec, out[[i]], created = FROZEN_P21))
      spec <- read_define_path(out[[i]])
    }
    expect_identical(
      readLines(out[[2]], warn = FALSE),
      readLines(out[[3]], warn = FALSE),
      info = name
    )
    # ...and the canonicalisation moves rows, it does not lose them.
    expect_equal(
      read_define_path(out[[3]]),
      read_define_path(out[[2]]),
      info = name
    )
  }
})

test_that("the structural digest of each workbook's output is stable", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("readxl")
  skip_on_cran()
  for (name in c("adam", "sdtm")) {
    workbook <- p21_workbooks()[[name]]
    skip_if(!nzchar(workbook) || !file.exists(workbook), "workbook not bundled")
    for (version in c("2.0", "2.1")) {
      out <- file.path(withr::local_tempdir(), "define.xml")
      suppressWarnings(
        write_spec(
          suppressWarnings(read_spec(workbook)),
          out,
          version = version,
          created = FROZEN_P21
        )
      )
      expect_snapshot({
        cat(name, version, "\n")
        str(define_digest(out), max.level = 2)
      })
    }
  }
})

test_that("an incomplete workbook is written, and every gap is named", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("readxl")
  # The degradation contract. A spec is often incomplete on purpose partway
  # through a study, so refusing to write it would make the tool useless
  # exactly when it is most wanted.
  workbook <- p21_workbooks()[["partial"]]
  spec <- suppressWarnings(read_spec(workbook))
  out <- file.path(withr::local_tempdir(), "define.xml")
  expect_warning(
    write_spec(spec, out, version = "2.1", created = FROZEN_P21),
    class = "artoo_warning_spec_incomplete"
  )
  expect_true(validate_define(out)@summary$valid)
  expect_false(any(grepl("dangling", define_lint(out)@findings$check)))
  expect_snapshot(
    spec <- write_spec(spec, out, version = "2.1", created = FROZEN_P21)
  )
})

test_that("a complete spec draws no incompleteness warning", {
  skip_if_not_installed("xml2")
  # The notice has to be silent on a submission-grade source, or it is noise
  # nobody reads.
  out <- file.path(withr::local_tempdir(), "define.xml")
  expect_no_warning(
    write_spec(
      read_define("define21-sdtm.xml"),
      out,
      version = "2.1",
      created = FROZEN_P21
    )
  )
})

test_that("a where clause may qualify a variable in another dataset", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("readxl")
  # The bundled SDTM workbook conditions a VS value-level definition on
  # DM.COUNTRY. The free-text parser stamps the value-level row's own dataset
  # onto every condition, because at parse time there is no spec to check
  # against, so the writer has to resolve the name across datasets.
  workbook <- p21_workbooks()[["sdtm"]]
  skip_if(!nzchar(workbook) || !file.exists(workbook), "workbook not bundled")
  spec <- suppressWarnings(read_spec(workbook))
  clause <- spec@where_clauses[
    spec@where_clauses$where_clause_id == "WC.VS.VSORRESU",
    ,
    drop = FALSE
  ]
  expect_true("COUNTRY" %in% clause$variable)
  # ...and the reader really did stamp the wrong dataset on it.
  expect_identical(unique(clause$dataset), "VS")
  expect_false(
    "COUNTRY" %in% spec@variables$variable[spec@variables$dataset == "VS"]
  )

  out <- file.path(withr::local_tempdir(), "define.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN_P21))
  checks <- xml2::xml_find_all(
    xml2::read_xml(out),
    "//*[local-name()='WhereClauseDef'][@OID='WC.VS.VSORRESU']/*[local-name()='RangeCheck']"
  )
  expect_identical(
    xml2::xml_attr(checks, "ItemOID"),
    c("IT.VS.VSTESTCD", "IT.DM.COUNTRY")
  )
})

test_that("a variable named by two datasets is refused, not guessed", {
  skip_if_not_installed("xml2")
  # Picking one would silently change which rows the value-level definition
  # applies to.
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = c("VS", "LB"),
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = c("VS", "VS", "LB"),
      variable = c("VSORRES", "USUBJID", "USUBJID"),
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause_id = "WC.1",
      data_type = "float",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.1",
      check_order = 1L,
      dataset = "NOWHERE",
      variable = "USUBJID",
      comparator = "EQ",
      value = "X",
      value_order = 1L,
      stringsAsFactors = FALSE
    )
  )
  out <- file.path(withr::local_tempdir(), "define.xml")
  expect_error(
    write_spec(spec, out, created = FROZEN_P21),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, out, created = FROZEN_P21), error = TRUE)
})

test_that("a comment with no description still writes a valid document", {
  skip_if_not_installed("xml2")
  # def:CommentDef requires a Description, and a workbook carrying a comment
  # id with no text is an ordinary input.
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      comment_id = "COM.1",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "COM.1",
      description = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  out <- file.path(withr::local_tempdir(), "define.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN_P21))
  expect_true(validate_define(out)@summary$valid)
  expect_identical(
    xml2::xml_text(xml2::xml_find_first(
      xml2::read_xml(out),
      "//*[local-name()='CommentDef']//*[local-name()='TranslatedText']"
    )),
    "COM.1"
  )
})

test_that("merged ARM cells are filled down like every other sheet (#p6-review)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # A P21 workbook merges the display cell across a display's results and the
  # result id across a result's analysis-dataset rows, exactly as it merges
  # the dataset cell on the Variables sheet. Without the same forward fill,
  # the continuation rows arrive with a blank key and are deleted -- silently,
  # and most of the ARM with them.
  book <- file.path(withr::local_tempdir(), "arm.xlsx")
  writexl::write_xlsx(
    list(
      Datasets = data.frame(
        Dataset = c("ADSL", "ADAE"),
        Description = c("Subject Level", "Adverse Events"),
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = c("ADSL", "ADAE"),
        Variable = c("USUBJID", "AEDECOD"),
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = c("RD.T1", NA),
        Name = c("Table 1", NA),
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = c("RD.T1", NA, NA),
        ID = c("AR.R1", NA, "AR.R2"),
        Description = c("First", NA, "Second"),
        Reason = c("SPECIFIED IN SAP", NA, "DATA DRIVEN"),
        Purpose = c("PRIMARY OUTCOME MEASURE", NA, "SECONDARY OUTCOME MEASURE"),
        Dataset = c("ADSL", "ADAE", "ADSL"),
        Variables = c("USUBJID", "AEDECOD", "USUBJID"),
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  # Three analysis-dataset rows survive, not one.
  expect_identical(nrow(spec@arm_results), 3L)
  expect_identical(unique(spec@arm_results$display_id), "RD.T1")
  expect_identical(spec@arm_results$result_id, c("AR.R1", "AR.R1", "AR.R2"))

  out <- file.path(withr::local_tempdir(), "define.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN_P21))
  expect_true(validate_define(out)@summary$valid)
  doc <- xml2::read_xml(out)
  expect_length(
    xml2::xml_find_all(doc, "//*[local-name()='AnalysisResult']"),
    2L
  )
  expect_length(
    xml2::xml_find_all(doc, "//*[local-name()='AnalysisDataset']"),
    3L
  )
})

test_that("a merged display id does not become two displays (#p7-review-1)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # Forward-filling the display id gave every continuation row the same id,
  # and the writer emitted one arm:ResultDisplay per ROW -- two elements with
  # one OID. Schema-valid, because an OID is odm:oidref rather than xs:ID,
  # and invisible to define_lint().
  book <- file.path(withr::local_tempdir(), "merged.xlsx")
  writexl::write_xlsx(
    list(
      Datasets = data.frame(
        Dataset = "ADSL",
        Description = "Subject Level",
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = "ADSL",
        Variable = "USUBJID",
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = c("RD.T1", NA),
        Name = c("Table 1", NA),
        Title = c("Demographics", NA),
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = "RD.T1",
        ID = "AR.R1",
        Description = "First",
        Reason = "SPECIFIED IN SAP",
        Purpose = "PRIMARY OUTCOME MEASURE",
        Dataset = "ADSL",
        Variables = "USUBJID",
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  expect_identical(nrow(spec@arm_displays), 1L)
  out <- file.path(withr::local_tempdir(), "define.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN_P21))
  doc <- xml2::read_xml(out)
  expect_identical(
    xml2::xml_attr(
      xml2::xml_find_all(doc, "//*[local-name()='ResultDisplay']"),
      "OID"
    ),
    "RD.T1"
  )
  expect_identical(
    xml2::xml_attr(
      xml2::xml_find_all(doc, "//*[local-name()='AnalysisResult']"),
      "OID"
    ),
    "AR.R1"
  )
})

test_that("a trailing note row is dropped, not absorbed (#p7-review-2)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # Filling `result_id` and then dropping on a blank `result_id` makes the
  # drop unreachable for every row below the first, so a "Note: see SAP" row
  # was absorbed as a continuation of the last result and then refused.
  book <- file.path(withr::local_tempdir(), "note.xlsx")
  writexl::write_xlsx(
    list(
      Datasets = data.frame(
        Dataset = "ADSL",
        Description = "Subject Level",
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = "ADSL",
        Variable = "USUBJID",
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = "RD.T1",
        Name = "Table 1",
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = c("RD.T1", NA),
        ID = c("AR.R1", NA),
        Description = c("First", "Note: see SAP section 9.1"),
        Reason = c("SPECIFIED IN SAP", NA),
        Purpose = c("PRIMARY OUTCOME MEASURE", NA),
        Dataset = c("ADSL", NA),
        Variables = c("USUBJID", NA),
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  expect_identical(nrow(spec@arm_results), 1L)
  out <- file.path(withr::local_tempdir(), "define.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN_P21))
  expect_true(validate_define(out)@summary$valid)
})

test_that("a display described two ways is refused (#p7-review-1)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  book <- file.path(withr::local_tempdir(), "split.xlsx")
  writexl::write_xlsx(
    list(
      Datasets = data.frame(
        Dataset = "ADSL",
        Description = "x",
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = "ADSL",
        Variable = "USUBJID",
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = c("RD.T1", NA),
        Name = c("Table 1", "Table 1 (draft)"),
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = "RD.T1",
        ID = "AR.R1",
        Description = "First",
        Reason = "SPECIFIED IN SAP",
        Purpose = "PRIMARY OUTCOME MEASURE",
        Dataset = "ADSL",
        Variables = "USUBJID",
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  expect_error(read_spec(book), class = "artoo_error_p21_sheet")
  expect_snapshot(read_spec(book), error = TRUE)
})

test_that("a document with no location is refused, not blamed on artoo (#p7-review-3)", {
  skip_if_not_installed("xml2")
  # xlink:href is required on def:leaf; a blank one was dropped and the
  # schema gate then reported "This is an artoo defect".
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      archive_location_id = "LF.dm",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "LF.dm",
      title = "dm.xpt",
      href = NA_character_,
      role = "archive",
      stringsAsFactors = FALSE
    )
  )
  out <- file.path(withr::local_tempdir(), "define.xml")
  expect_error(
    write_spec(spec, out, created = FROZEN_P21),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, out, created = FROZEN_P21), error = TRUE)
})

test_that("the incompleteness notice covers value-level rows (#p7-review-4)", {
  skip_if_not_installed("xml2")
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "VS",
      label = "Vital Signs",
      class = "FINDINGS",
      domain = "VS",
      purpose = "Tabulation",
      repeating = TRUE,
      archive_location_id = "LF.vs",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "LF.vs",
      title = "vs.xpt",
      href = "vs.xpt",
      role = "archive",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      label = "Result",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "float",
      stringsAsFactors = FALSE
    )
  )
  out <- file.path(withr::local_tempdir(), "define.xml")
  gaps <- NULL
  withCallingHandlers(
    write_spec(spec, out, created = FROZEN_P21),
    warning = function(w) {
      if (inherits(w, "artoo_warning_spec_incomplete")) {
        gaps <<- conditionMessage(w)
      }
      invokeRestart("muffleWarning")
    }
  )
  expect_match(gaps, "values$origin", fixed = TRUE)
  expect_match(gaps, "values$length", fixed = TRUE)
})
