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
  # Gated on CRAN: a breadth loop over the bundled CDISC corpora, which is
  # where the Windows check time goes. It runs in full on CI, on every
  # platform, so the coverage is not lost -- only CRAN's clock is spared.
  skip_on_cran()
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

test_that("the older shape's Analysis Criteria sheet is read (#p12-P3)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # The older workbook generation keeps an analysis result's datasets on
  # their own sheet instead of packing them into one cell, at exactly
  # artoo's grain. artoo had the sheet alias and never read the sheet, so a
  # result authored this way reached the writer naming no analysis dataset
  # and the write refused it -- telling the author to fill a slot their
  # workbook shape has no column for.
  dir <- withr::local_tempdir()
  book <- file.path(dir, "old.xlsx")
  writexl::write_xlsx(
    list(
      Study = data.frame(
        Attribute = c("StudyName", "StandardName", "StandardVersion"),
        Value = c("CDISC01", "ADaM-IG", "1.1"),
        stringsAsFactors = FALSE
      ),
      Datasets = data.frame(
        Dataset = c("ADAE", "ADSL"),
        Description = c("Adverse Events", "Subject Level"),
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = c("ADAE", "ADAE", "ADSL"),
        Variable = c("AESER", "AEBODSYS", "SAFFL"),
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = "RD.1",
        Title = "Table 1",
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = "RD.1",
        ID = "AR.1",
        Description = "Adverse events by system organ class",
        Reason = "SPECIFIED IN PROTOCOL",
        Purpose = "PRIMARY OUTCOME MEASURE",
        stringsAsFactors = FALSE
      ),
      `Analysis Criteria` = data.frame(
        Display = "RD.1",
        Result = "AR.1",
        Dataset = c("ADAE", "ADSL"),
        Variables = c("AEBODSYS", ""),
        `Where Clause` = c("AESER EQ Y", "SAFFL EQ Y"),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  # One result, two analysis datasets, each with its own condition.
  expect_identical(nrow(spec@arm_results), 2L)
  expect_identical(spec@arm_results$dataset, c("ADAE", "ADSL"))
  expect_identical(spec@arm_results$variables[[1]], "AEBODSYS")
  # The cell holds a condition, not an id; it is parsed into a real clause
  # by the same parser the ValueLevel column goes through.
  expect_true(all(
    spec@arm_results$where_clause_id %in% spec@where_clauses$where_clause_id
  ))
  expect_setequal(spec@where_clauses$variable, c("AESER", "SAFFL"))

  path <- file.path(dir, "define.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_P21, stylesheet = FALSE)
  ))
  expect_true(validate_define(path)@summary$valid)
  doc <- xml2::read_xml(path)
  expect_length(
    xml2::xml_find_all(
      doc,
      "//*[local-name()='AnalysisDataset']",
      ns = character()
    ),
    2L
  )
  # ...and every clause the result names is defined in the same document.
  expect_false(any(grepl(
    "^define_dangling",
    lint_define(path)@findings$check
  )))
})

test_that("the criteria sheet's edges are handled (#p12-P3)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  base <- function(criteria) {
    dir <- withr::local_tempdir(.local_envir = parent.frame())
    path <- file.path(dir, "old.xlsx")
    writexl::write_xlsx(
      list(
        Study = data.frame(
          Attribute = c("StudyName", "StandardName", "StandardVersion"),
          Value = c("CDISC01", "ADaM-IG", "1.1"),
          stringsAsFactors = FALSE
        ),
        Datasets = data.frame(
          Dataset = c("ADAE", "ADSL"),
          Description = "x",
          Structure = "One record per subject",
          stringsAsFactors = FALSE
        ),
        Variables = data.frame(
          Dataset = c("ADAE", "ADAE", "ADSL"),
          Variable = c("AESER", "AEBODSYS", "SAFFL"),
          `Data Type` = "text",
          check.names = FALSE,
          stringsAsFactors = FALSE
        ),
        `Analysis Displays` = data.frame(
          ID = "RD.1",
          Title = "Table 1",
          stringsAsFactors = FALSE
        ),
        `Analysis Results` = data.frame(
          Display = "RD.1",
          ID = "AR.1",
          Description = "d",
          Reason = "SPECIFIED IN PROTOCOL",
          Purpose = "PRIMARY OUTCOME MEASURE",
          stringsAsFactors = FALSE
        ),
        `Analysis Criteria` = criteria
      ),
      path
    )
    path
  }

  # A criteria row naming a result that does not exist belongs to nothing,
  # so the result it does not name keeps its own single row.
  orphan <- base(data.frame(
    Display = "RD.1",
    Result = c("AR.1", "AR.NOPE"),
    Dataset = c("ADAE", "ADSL"),
    Variables = c("AEBODSYS", ""),
    `Where Clause` = c("AESER EQ Y", "SAFFL EQ Y"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  ))
  spec <- suppressWarnings(read_spec(orphan))
  expect_identical(nrow(spec@arm_results), 1L)
  expect_identical(spec@arm_results$dataset, "ADAE")

  # A cell already naming a defined clause is left as the reference it is,
  # rather than parsed as a condition.
  keyed <- base(data.frame(
    Display = "RD.1",
    Result = "AR.1",
    Dataset = "ADAE",
    Variables = "AEBODSYS",
    `Where Clause` = "AESER EQ Y",
    check.names = FALSE,
    stringsAsFactors = FALSE
  ))
  spec2 <- suppressWarnings(read_spec(keyed))
  expect_true(
    spec2@arm_results$where_clause_id %in% spec2@where_clauses$where_clause_id
  )

  # Every record: a dataset with no condition at all.
  every <- base(data.frame(
    Display = "RD.1",
    Result = "AR.1",
    Dataset = "ADSL",
    Variables = "SAFFL",
    `Where Clause` = NA_character_,
    check.names = FALSE,
    stringsAsFactors = FALSE
  ))
  spec3 <- suppressWarnings(read_spec(every))
  expect_identical(spec3@arm_results$dataset, "ADSL")
  expect_true(is.na(spec3@arm_results$where_clause_id))
  path <- file.path(withr::local_tempdir(), "define.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec3, path, created = FROZEN_P21, stylesheet = FALSE)
  ))
  expect_true(validate_define(path)@summary$valid)
})

test_that("selection criteria assigns variables per dataset (#p12-P3)", {
  # The newer shape packs several datasets into one cell, and each takes
  # only the variables qualified by its own name; an unqualified name
  # belongs to the group only when there is one.
  expect_identical(
    artoo:::.arm_group_variables("ADAE.X, ADSL.Y", "ADAE", 2L),
    "X"
  )
  expect_identical(
    artoo:::.arm_group_variables("ADAE.X, ADSL.Y", "ADSL", 2L),
    "Y"
  )
  expect_true(is.na(artoo:::.arm_group_variables("X Y", "ADAE", 2L)))
  expect_identical(artoo:::.arm_group_variables("X Y", "ADAE", 1L), "X Y")
  expect_true(is.na(artoo:::.arm_group_variables(NA_character_, "ADAE", 1L)))
})

test_that("a criteria sheet may omit its optional columns (#p12-final-3)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # An Analysis Criteria sheet naming only datasets is legitimate -- a
  # result may take every record with no variable list -- and indexing the
  # absent columns died with a bare R error mid-read.
  dir <- withr::local_tempdir()
  book <- file.path(dir, "old.xlsx")
  writexl::write_xlsx(
    list(
      Study = data.frame(
        Attribute = c("StudyName", "StandardName", "StandardVersion"),
        Value = c("CDISC01", "ADaM-IG", "1.1"),
        stringsAsFactors = FALSE
      ),
      Datasets = data.frame(
        Dataset = c("ADAE", "ADSL"),
        Description = "x",
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = c("ADAE", "ADSL"),
        Variable = c("AEBODSYS", "SAFFL"),
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = "RD.1",
        Title = "Table 1",
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = "RD.1",
        ID = "AR.1",
        Description = "d",
        Reason = "SPECIFIED IN PROTOCOL",
        Purpose = "PRIMARY OUTCOME MEASURE",
        stringsAsFactors = FALSE
      ),
      `Analysis Criteria` = data.frame(
        Display = "RD.1",
        Result = "AR.1",
        Dataset = "ADAE",
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  expect_identical(spec@arm_results$dataset, "ADAE")
  expect_true(is.na(spec@arm_results$variables))
  expect_true(is.na(spec@arm_results$where_clause_id))
})

test_that("the criteria sheet overriding a Selection Criteria cell warns (#p12-final-3)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # A hand-authored workbook can name a result's datasets both ways, and
  # they can disagree. The sheet wins -- it is the more precise grain --
  # but the losing cell must not vanish silently.
  dir <- withr::local_tempdir()
  book <- file.path(dir, "both.xlsx")
  writexl::write_xlsx(
    list(
      Study = data.frame(
        Attribute = c("StudyName", "StandardName", "StandardVersion"),
        Value = c("CDISC01", "ADaM-IG", "1.1"),
        stringsAsFactors = FALSE
      ),
      Datasets = data.frame(
        Dataset = c("ADAE", "ADSL"),
        Description = "x",
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = c("ADAE", "ADAE", "ADSL"),
        Variable = c("AESER", "AEBODSYS", "SAFFL"),
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = "RD.1",
        Title = "Table 1",
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = "RD.1",
        ID = "AR.1",
        Description = "d",
        Reason = "SPECIFIED IN PROTOCOL",
        Purpose = "PRIMARY OUTCOME MEASURE",
        `Selection Criteria` = "ADSL[SAFFL EQ Y]",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Criteria` = data.frame(
        Display = "RD.1",
        Result = "AR.1",
        Dataset = "ADAE",
        Variables = "AEBODSYS",
        `Where Clause` = "AESER EQ Y",
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  expect_warning(
    spec <- suppressMessages(read_spec(book)),
    class = "artoo_warning_spec"
  )
  # The sheet's dataset stands; the cell's is gone, and was announced.
  expect_identical(spec@arm_results$dataset, "ADAE")
})

test_that("a Selection Criteria cell expands into per-dataset rows (#p12-final-4)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # The standard shape packs a result's analysis datasets into ONE cell, a
  # bracket group each; artoo's grain is one row per result x dataset. The
  # expansion is what gives the define its arm:AnalysisDataset children.
  dir <- withr::local_tempdir()
  book <- file.path(dir, "packed.xlsx")
  writexl::write_xlsx(
    list(
      Study = data.frame(
        Attribute = c("StudyName", "StandardName", "StandardVersion"),
        Value = c("CDISC01", "ADaM-IG", "1.1"),
        stringsAsFactors = FALSE
      ),
      Datasets = data.frame(
        Dataset = c("ADAE", "ADSL"),
        Description = "x",
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = c("ADAE", "ADAE", "ADSL"),
        Variable = c("AESER", "AEBODSYS", "SAFFL"),
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = "RD.1",
        Title = "Table 1",
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = "RD.1",
        ID = "AR.1",
        Description = "d",
        Reason = "SPECIFIED IN PROTOCOL",
        Purpose = "PRIMARY OUTCOME MEASURE",
        Variables = "ADAE.AEBODSYS ADSL.SAFFL",
        `Selection Criteria` = "ADAE[AESER EQ Y] ADSL[SAFFL EQ Y]",
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  expect_identical(nrow(spec@arm_results), 2L)
  expect_identical(spec@arm_results$dataset, c("ADAE", "ADSL"))
  # Each dataset takes only the variables qualified by its own name.
  expect_identical(spec@arm_results$variables, c("AEBODSYS", "SAFFL"))
  # Each bracket group's condition became a defined clause.
  expect_true(all(
    spec@arm_results$where_clause_id %in% spec@where_clauses$where_clause_id
  ))
  expect_setequal(spec@where_clauses$variable, c("AESER", "SAFFL"))

  # A cell artoo cannot read is refused by name, not expanded wrongly:
  # text outside any bracket group has no dataset to belong to.
  bad <- file.path(dir, "bad.xlsx")
  sheets <- readxl::excel_sheets(book)
  content <- lapply(sheets, function(s) readxl::read_excel(book, sheet = s))
  names(content) <- sheets
  content$`Analysis Results`$`Selection Criteria` <- "AESER EQ Y"
  writexl::write_xlsx(content, bad)
  expect_error(
    suppressWarnings(read_spec(bad)),
    class = "artoo_error_spec"
  )
  expect_snapshot(suppressWarnings(read_spec(bad)), error = TRUE)
})

test_that("an ARM condition cell stacks onto the clauses the workbook defines (#p12-final-4)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # A result's Where Clause cell may hold a CONDITION rather than the id of
  # one. When the workbook also defines clauses on their own sheet, the
  # minted clause joins them -- replacing them lost every value-level
  # clause the moment one result spelled its condition out.
  dir <- withr::local_tempdir()
  book <- file.path(dir, "stack.xlsx")
  writexl::write_xlsx(
    list(
      Study = data.frame(
        Attribute = c("StudyName", "StandardName", "StandardVersion"),
        Value = c("CDISC01", "ADaM-IG", "1.1"),
        stringsAsFactors = FALSE
      ),
      Datasets = data.frame(
        Dataset = c("ADAE", "ADSL"),
        Description = "x",
        Structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = c("ADAE", "ADAE", "ADSL"),
        Variable = c("AESER", "AEBODSYS", "SAFFL"),
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      WhereClauses = data.frame(
        ID = "WC.OTHER",
        Dataset = "ADAE",
        Variable = "AESER",
        Comparator = "EQ",
        Value = "Y",
        stringsAsFactors = FALSE
      ),
      `Analysis Displays` = data.frame(
        ID = "RD.1",
        Title = "Table 1",
        stringsAsFactors = FALSE
      ),
      `Analysis Results` = data.frame(
        Display = "RD.1",
        ID = c("AR.1", "AR.2"),
        Description = "d",
        Reason = "SPECIFIED IN PROTOCOL",
        Purpose = "PRIMARY OUTCOME MEASURE",
        Dataset = c(NA, "ADSL"),
        `Where Clause` = c("WC.OTHER", "SAFFL EQ Y"),
        check.names = FALSE,
        stringsAsFactors = FALSE
      ),
      # A criteria sheet that names only AR.1: AR.2 has no row there, and
      # keeps its own single row untouched.
      `Analysis Criteria` = data.frame(
        Display = "RD.1",
        Result = "AR.1",
        Dataset = "ADAE",
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  expect_identical(nrow(spec@arm_results), 2L)
  expect_identical(spec@arm_results$dataset, c("ADAE", "ADSL"))
  # AR.1 keeps its stated reference; AR.2's condition became a clause that
  # joined WC.OTHER rather than replacing it.
  expect_identical(spec@arm_results$where_clause_id[[1]], "WC.OTHER")
  minted <- spec@arm_results$where_clause_id[[2]]
  expect_false(identical(minted, "SAFFL EQ Y"))
  expect_contains(
    unique(spec@where_clauses$where_clause_id),
    c("WC.OTHER", minted)
  )
})

test_that("a workbook's Standard column reaches def:StandardOID (#p12-final-5)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  # The Datasets sheet states a standard per row; Define-XML states it as
  # def:StandardOID resolving into the def:Standards block, which is what
  # the stylesheet renders in every dataset heading. artoo minted the block
  # and never linked the datasets to it, so every heading rendered bare.
  dir <- withr::local_tempdir()
  book <- file.path(dir, "std.xlsx")
  writexl::write_xlsx(
    list(
      Study = data.frame(
        Attribute = c("StudyName", "StandardName", "StandardVersion"),
        Value = c("CDISC01", "ADaM-IG", "1.1"),
        stringsAsFactors = FALSE
      ),
      Datasets = data.frame(
        Dataset = c("ADSL", "ADAE"),
        Label = c("Subject Level", "Adverse Events"),
        Structure = "One record per subject",
        Standard = "ADaMIG 1.1",
        stringsAsFactors = FALSE
      ),
      Variables = data.frame(
        Dataset = c("ADSL", "ADAE"),
        Variable = c("USUBJID", "AETERM"),
        Label = "x",
        `Data Type` = "text",
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    ),
    book
  )
  spec <- suppressWarnings(read_spec(book))
  expect_false(anyNA(spec@datasets$standard_id))
  expect_true(all(spec@datasets$standard_id %in% spec@standards$standard_id))

  out <- file.path(dir, "define.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN_P21))
  doc <- xml2::read_xml(out)
  igs <- xml2::xml_find_all(
    doc,
    "//*[local-name()='ItemGroupDef']",
    ns = character()
  )
  oids <- xml2::xml_attr(igs, "StandardOID")
  expect_length(igs, 2L)
  expect_false(anyNA(oids))
  # ...and the reference resolves to the block the stylesheet renders from.
  std <- xml2::xml_find_first(
    doc,
    sprintf("//*[local-name()='Standard'][@OID='%s']", oids[[1]]),
    ns = character()
  )
  expect_identical(xml2::xml_attr(std, "Name"), "ADaMIG")
  expect_identical(xml2::xml_attr(std, "Version"), "1.1")
  expect_false(any(grepl("dangling", lint_define(out)@findings$check)))
})

test_that("the criteria sheet's required columns are required (#p12-decision)", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  # Three of the five columns are required and two are not, and the split
  # is the reference importer's own: it declares Display, Result and
  # Dataset required, Variables and Where Clause optional -- and its
  # control workbook carries a row with both optional cells blank, so
  # "every record, no variable list" is ordinary authored data.
  #
  # An absent REQUIRED column used to be tolerated too, and silently: the
  # key matched nothing, the whole sheet was discarded without a word, and
  # the failure surfaced later at write time naming the wrong surface.
  book <- function(criteria) {
    path <- file.path(
      withr::local_tempdir(.local_envir = parent.frame()),
      "w.xlsx"
    )
    writexl::write_xlsx(
      list(
        Study = data.frame(
          Attribute = c("StudyName", "StandardName", "StandardVersion"),
          Value = c("CDISC01", "ADaM-IG", "1.1"),
          stringsAsFactors = FALSE
        ),
        Datasets = data.frame(
          Dataset = "ADAE",
          Description = "Adverse Events",
          Structure = "One record per event",
          stringsAsFactors = FALSE
        ),
        Variables = data.frame(
          Dataset = "ADAE",
          Variable = "AESER",
          `Data Type` = "text",
          check.names = FALSE,
          stringsAsFactors = FALSE
        ),
        `Analysis Displays` = data.frame(
          ID = "RD.1",
          Title = "Table 1",
          stringsAsFactors = FALSE
        ),
        `Analysis Results` = data.frame(
          Display = "RD.1",
          ID = "AR.1",
          Description = "d",
          Reason = "SPECIFIED IN PROTOCOL",
          Purpose = "PRIMARY OUTCOME MEASURE",
          stringsAsFactors = FALSE
        ),
        `Analysis Criteria` = criteria
      ),
      path
    )
    path
  }

  # Optional columns absent: read, with the payload NA and nothing said.
  spec <- suppressWarnings(read_spec(book(data.frame(
    Display = "RD.1",
    Result = "AR.1",
    Dataset = "ADAE",
    stringsAsFactors = FALSE
  ))))
  expect_identical(spec@arm_results$dataset, "ADAE")
  expect_true(is.na(spec@arm_results$variables))
  expect_true(is.na(spec@arm_results$where_clause_id))

  # A required column absent: refused, naming the column by its header.
  for (missing in list(
    list(
      drop = "Result",
      crit = data.frame(
        Display = "RD.1",
        Dataset = "ADAE",
        stringsAsFactors = FALSE
      )
    ),
    list(
      drop = "Display",
      crit = data.frame(
        Result = "AR.1",
        Dataset = "ADAE",
        stringsAsFactors = FALSE
      )
    ),
    list(
      drop = "Dataset",
      crit = data.frame(
        Display = "RD.1",
        Result = "AR.1",
        stringsAsFactors = FALSE
      )
    )
  )) {
    path <- book(missing$crit)
    expect_error(
      read_spec(path),
      class = "artoo_error_p21_sheet",
      info = missing$drop
    )
    expect_error(read_spec(path), missing$drop, info = missing$drop)
  }
})
