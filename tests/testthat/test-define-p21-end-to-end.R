# Pinnacle 21 workbook -> define.xml, end to end.
#
# Three workbooks x two versions x four gates. This is the test that says the
# feature works on real input rather than on the CDISC reference documents,
# which are unrepresentatively complete.
#
# The four gates:
#   1. the write succeeds, or refuses for a reason the schema forces
#   2. the document is schema-valid against the bundled CDISC schemas
#   3. lint_define() reports zero DANGLING references -- orphans are allowed,
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
  findings <- lint_define(path)@findings
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
      # Every bundled workbook now names a standard, including the partial
      # one: its Study sheet states a name and a version, which is what
      # Define-XML 2.0 requires on MetaDataVersion, and the reader resolves
      # the pair rather than leaving it as two unmodelled study fields.
      expect_false(is.na(spec_standard(spec)), info = label)
      suppressWarnings(
        write_spec(spec, out, version = version, created = FROZEN_P21)
      )
      report <- validate_define(out)
      expect_true(report@summary$valid, info = label)
      expect_identical(report@summary$define_version, version, info = label)
      checks <- lint_define(out)@findings$check
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
  expect_false(any(grepl("dangling", lint_define(out)@findings$check)))
  expect_snapshot(
    spec <- write_spec(spec, out, version = "2.1", created = FROZEN_P21)
  )
})

test_that("a complete spec draws no incompleteness warning", {
  skip_if_not_installed("xml2")
  # The notice has to be silent on a submission-grade source, or it is noise
  # nobody reads.
  out <- file.path(withr::local_tempdir(), "define.xml")
  # Scoped to the completeness notice: this fixture also draws a genuine
  # the empty-dataset comment rule warning of its own (SUPPVS is flagged as empty with no comment),
  # which is a property of CDISC's example rather than of the notice.
  expect_no_condition(
    suppressWarnings(
      write_spec(
        read_define("define21-sdtm.xml"),
        out,
        version = "2.1",
        created = FROZEN_P21
      )
    ),
    class = "artoo_warning_spec_incomplete"
  )
})

test_that("a where clause may qualify a variable in another dataset", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("readxl")
  # The bundled SDTM workbook conditions a VS value-level definition on
  # DM.COUNTRY. The workbook now carries the owning dataset on each range
  # check -- a Define-XML read used to leave it NA, so a round trip kept
  # only the variable name and a name two datasets share was unresolvable.
  workbook <- p21_workbooks()[["sdtm"]]
  skip_if(!nzchar(workbook) || !file.exists(workbook), "workbook not bundled")
  spec <- suppressWarnings(read_spec(workbook))
  # Found by what it selects, not by its id: the ids are minted from the
  # expression on each read, so they no longer spell out every variable.
  cross <- spec@where_clauses[
    !is.na(spec@where_clauses$variable) &
      spec@where_clauses$variable == "COUNTRY",
    ,
    drop = FALSE
  ]
  expect_gt(nrow(cross), 0L)
  expect_true("COUNTRY" %in% cross$variable)
  expect_setequal(unique(cross$dataset), "DM")

  out <- file.path(withr::local_tempdir(), "define.xml")
  suppressMessages(suppressWarnings(write_spec(
    spec,
    out,
    created = FROZEN_P21
  )))
  id <- cross$where_clause_id[[1]]
  checks <- xml2::xml_find_all(
    xml2::read_xml(out),
    sprintf(
      "//*[local-name()='WhereClauseDef'][@OID='%s']/*[local-name()='RangeCheck']",
      id
    )
  )
  # Each condition resolves to the ItemDef of its OWN dataset.
  expect_setequal(
    xml2::xml_attr(checks, "ItemOID"),
    c("IT.VS.VSTESTCD", "IT.DM.COUNTRY")
  )
  expect_false(any(grepl("dangling", lint_define(out)@findings$check)))
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
  # and invisible to lint_define().
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
      # The continuation row carries a value, so writexl and readxl cannot
      # erase it before the collapse sees it -- an all-NA row is trimmed on
      # write, which is how the first version of this test could not fail.
      `Analysis Displays` = data.frame(
        ID = c("RD.T1", NA),
        Name = c("Table 1", NA),
        Title = c(NA, "Demographics"),
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
      where_clause_id = "WC.1",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.1",
      check_order = 1L,
      dataset = "VS",
      variable = "VSORRES",
      comparator = "EQ",
      value = "X",
      value_order = 1L,
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

test_that("a result with its own id survives a merged Dataset cell (#p8-review-3)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # The payload columns are exactly the mergeable ones, so judging blankness
  # AFTER the fill deleted a whole result that named itself.
  book <- file.path(withr::local_tempdir(), "merged-dataset.xlsx")
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
        ID = c("AR.R1", "AR.R2"),
        Description = c("First", "Second"),
        Reason = c("SPECIFIED IN SAP", "DATA DRIVEN"),
        Purpose = c("PRIMARY OUTCOME MEASURE", "SECONDARY OUTCOME MEASURE"),
        # Merged in the source: only the first row names the dataset.
        Dataset = c("ADSL", NA),
        Variables = c("USUBJID", NA),
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  expect_identical(nrow(spec@arm_results), 2L)
  expect_identical(spec@arm_results$result_id, c("AR.R1", "AR.R2"))
})

test_that("a display citing two documents is not refused (#p8-review-4)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # def:DocumentRef is maxOccurs="unbounded" on arm:ResultDisplay. artoo
  # models one, which is artoo's limit, not the author's error -- and a
  # foreign column artoo does not model is no reason to refuse at all.
  book <- file.path(withr::local_tempdir(), "two-docs.xlsx")
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
        Name = c("Table 1", NA),
        Document = c("LF.CSR", "LF.SAP"),
        `Reviewer Notes` = c("checked", "re-checked"),
        check.names = FALSE,
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
  expect_identical(spec@arm_displays$display_id, "RD.T1")
})

test_that("the newer sheets survive an xlsx round trip (#p8-review-q5)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # The reader learned WhereClauses, Standards and the analysis-results
  # sheets when the Define-XML work landed, and write_template() offers them.
  # A writer that still emitted only the eight classic sheets would lose on
  # its own round trip exactly what artoo had just taught itself to read.
  spec <- read_define("define21-adam.xml")
  book <- file.path(withr::local_tempdir(), "round.xlsx")
  suppressWarnings(write_spec(spec, book))
  back <- suppressWarnings(read_spec(book))
  for (slot in c("standards", "where_clauses", "arm_displays", "arm_results")) {
    expect_identical(
      nrow(S7::prop(back, slot)),
      nrow(S7::prop(spec, slot)),
      info = slot
    )
  }
  # ...and every sheet it writes is one the template offers.
  template <- file.path(withr::local_tempdir(), "template.xlsx")
  write_template(template)
  expect_true(all(
    readxl::excel_sheets(book) %in% readxl::excel_sheets(template)
  ))
})

test_that("what a workbook loses is exactly what it warns about (#p10-review-M6)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # The five sheets the Define-XML work added closed the slot-level gaps and
  # opened column-level ones -- P21 has no column for which standard is
  # primary, or for an ItemOID. The contract is not that nothing is lost; it
  # is that the warning names the loss exactly, so this compares the two.
  spec <- read_define("define21-sdtm.xml")
  book <- file.path(withr::local_tempdir(), "round.xlsx")
  warned <- NULL
  expect_warning(
    {
      warned <- artoo:::.p21_dropped_cols(spec)
      write_spec(spec, book)
    },
    class = "artoo_warning_spec"
  )
  back <- suppressWarnings(read_spec(book))

  # What actually failed to come back: a column the spec populated that the
  # workbook returns absent or empty.
  lost <- lapply(names(artoo:::.p21_slot_maps), function(slot) {
    a <- S7::prop(spec, slot)
    b <- S7::prop(back, slot)
    if (is.null(a) || !nrow(a)) {
      return(character(0))
    }
    held <- names(a)[!vapply(a, function(col) all(is.na(col)), logical(1))]
    held[vapply(
      held,
      function(cl) !cl %in% names(b) || all(is.na(b[[cl]])),
      logical(1)
    )]
  })
  names(lost) <- names(artoo:::.p21_slot_maps)
  lost <- lost[lengths(lost) > 0L]

  expect_identical(names(lost), names(warned))
  for (slot in names(lost)) {
    expect_setequal(lost[[slot]], warned[[slot]])
  }
  # ...and the loss is real, not an empty claim on both sides.
  expect_true("is_primary" %in% warned$standards)
  expect_true("itemoid" %in% warned$variables)
})

test_that("every populated column of the newer sheets round-trips (#p10-review-Q4)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # Row counts alone cannot fail on a column that comes back empty, which is
  # how the standards sheet lost `is_primary` unnoticed. This compares
  # content, column by column, for everything the maps say a sheet carries.
  spec <- read_define("define21-adam.xml")
  book <- file.path(withr::local_tempdir(), "round.xlsx")
  suppressWarnings(write_spec(spec, book))
  back <- suppressWarnings(read_spec(book))
  for (slot in c("standards", "where_clauses", "arm_displays", "arm_results")) {
    a <- S7::prop(spec, slot)
    b <- S7::prop(back, slot)
    expect_identical(nrow(b), nrow(a), info = slot)
    mapped <- unname(artoo:::.p21_slot_maps[[slot]][[2]])
    # A where-clause id is minted from the expression on each read, because
    # the workbook format has no sheet to carry the author's own. What the
    # clause SELECTS is compared above; the name it selects under is not a
    # fact the format preserves.
    mapped <- setdiff(mapped, "where_clause_id")
    for (cl in intersect(mapped, names(a))) {
      if (all(is.na(a[[cl]]))) {
        next
      }
      expect_identical(
        as.character(b[[cl]]),
        as.character(a[[cl]]),
        info = paste(slot, cl)
      )
    }
  }
})

test_that("a value-level condition survives as a condition (#p12-review)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # The workbook format carries the condition as an expression in the
  # ValueLevel cell and has no where-clause sheet, so the ids are minted
  # afresh on each read. What has to survive is what the clause SELECTS,
  # not the name it was selected under.
  spec <- read_define("define21-sdtm.xml")
  book <- file.path(withr::local_tempdir(), "round.xlsx")
  suppressWarnings(write_spec(spec, book))
  expect_no_warning(back <- read_spec(book))
  expect_identical(nrow(back@values), nrow(spec@values))
  # Every row still names a clause the same workbook defines.
  expect_true(all(
    back@values$where_clause %in% back@where_clauses$where_clause_id
  ))
  condition <- function(sp, id) {
    rows <- sp@where_clauses[sp@where_clauses$where_clause_id == id, ]
    rows <- rows[order(rows$check_order, rows$value_order), ]
    paste(rows$variable, rows$comparator, rows$value, collapse = " and ")
  }
  before <- vapply(
    spec@values$where_clause_id,
    condition,
    character(1),
    sp = spec
  )
  after <- vapply(back@values$where_clause, condition, character(1), sp = back)
  expect_identical(unname(after), unname(before))
})

test_that("a where clause survives as one range check per row (#p11-review-M2)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # The slot is one row per CheckValue and the sheet is one row per
  # RangeCheck. Projecting row for row makes `IN (A, ..., N)` read back as N
  # ANDed one-value checks, which select nothing -- and it is invisible to a
  # comparison of the mapped columns, because both shapes give the same rows
  # with the same values. Only the two counters tell them apart.
  spec <- read_define("define21-adam.xml")
  book <- file.path(withr::local_tempdir(), "round.xlsx")
  suppressWarnings(write_spec(spec, book))
  back <- suppressWarnings(read_spec(book))
  # The set comparator that motivated it: one check, fourteen values, which
  # a row-for-row projection turns into fourteen ANDed one-value checks.
  wide <- spec@where_clauses[
    spec@where_clauses$where_clause_id == "WC.ADQSADAS.AVAL.ACITM01-ACITM14",
  ]
  skip_if(!nrow(wide), "fixture lost its multi-value clause")
  expect_gt(nrow(wide), 1L)
  expect_identical(length(unique(wide$check_order)), 1L)
  # The ids are minted afresh, so find it again by what it selects.
  back_wide <- back@where_clauses[
    back@where_clauses$value %in% wide$value,
  ]
  expect_identical(nrow(back_wide), nrow(wide))
  expect_identical(length(unique(back_wide$check_order)), 1L)
  expect_setequal(back_wide$value, wide$value)
  expect_identical(sort(back_wide$value_order), sort(wide$value_order))
})

test_that("a clause with ten range checks keeps its order (#p11-review-B)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # The sheet's row order is the only record of check_order, and a composite
  # string key sorts "10" before "2".
  n <- 12L
  spec <- artoo_spec(
    data.frame(dataset = "VS", stringsAsFactors = FALSE),
    data.frame(
      dataset = "VS",
      variable = c("VSORRES", paste0("Q", seq_len(n))),
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause_id = "WC.WIDE",
      data_type = "text",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.WIDE",
      check_order = seq_len(n),
      dataset = "VS",
      variable = paste0("Q", seq_len(n)),
      comparator = "EQ",
      value = paste0("V", seq_len(n)),
      value_order = 1L,
      stringsAsFactors = FALSE
    )
  )
  book <- file.path(withr::local_tempdir(), "wide.xlsx")
  suppressWarnings(write_spec(spec, book))
  back <- suppressWarnings(read_spec(book))
  expect_identical(back@where_clauses$variable, paste0("Q", seq_len(n)))
  expect_identical(back@where_clauses$check_order, seq_len(n))
})
