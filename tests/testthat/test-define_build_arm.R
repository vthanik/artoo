# Analysis Results Metadata, both Define-XML versions.
#
# The 2.0 and 2.1 ARM schemas are byte-identical apart from the def: namespace
# they import, so there is one writer path. The 2.0 case is synthesised here
# because CDISC never published a 2.0 example carrying ARM -- these are the
# only tests of that combination anywhere.

FROZEN_ARM <- "2020-01-01 00:00:00"

arm_spec <- function(displays = NULL, results = NULL) {
  artoo_spec(
    standard = "ADaMIG 1.1",
    datasets = data.frame(
      dataset = c("ADSL", "ADQSADAS"),
      label = c("Subject Level", "ADAS-Cog"),
      class = c("SUBJECT LEVEL ANALYSIS DATASET", "BASIC DATA STRUCTURE"),
      domain = c("ADSL", "ADQSADAS"),
      purpose = "Analysis",
      repeating = c(FALSE, TRUE),
      archive_location_id = c("LF.adsl", "LF.adqsadas"),
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = c("LF.adsl", "LF.adqsadas"),
      title = c("adsl.xpt", "adqsadas.xpt"),
      href = c("adsl.xpt", "adqsadas.xpt"),
      role = "archive",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = c("ADSL", "ADSL", "ADQSADAS", "ADQSADAS"),
      variable = c("USUBJID", "TRT01P", "CHG", "PARAMCD"),
      label = c("Subject", "Planned Treatment", "Change", "Parameter Code"),
      data_type = "string",
      length = 20L,
      origin = "Derived",
      stringsAsFactors = FALSE
    ),
    arm_displays = displays %||%
      data.frame(
        display_id = "RD.T1",
        name = "Table 1",
        description = "Primary endpoint",
        stringsAsFactors = FALSE
      ),
    arm_results = results %||%
      data.frame(
        display_id = "RD.T1",
        result_id = "AR.T1.R1",
        description = "Dose response",
        reason = "SPECIFIED IN SAP",
        purpose = "PRIMARY OUTCOME MEASURE",
        dataset = "ADQSADAS",
        variables = "CHG",
        stringsAsFactors = FALSE
      )
  )
}

write_arm <- function(spec = arm_spec(), version = "2.1") {
  path <- file.path(
    withr::local_tempdir(.local_envir = parent.frame()),
    "d.xml"
  )
  suppressWarnings(
    write_spec(spec, path, version = version, created = FROZEN_ARM)
  )
  path
}

test_that("the CDISC 2.1 ADaM example round-trips its arm: elements", {
  skip_if_not_installed("xml2")
  spec <- read_define("define21-adam.xml")
  expect_identical(nrow(spec@arm_displays), 2L)
  expect_identical(nrow(spec@arm_results), 4L)
  out <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN_ARM))
  expect_equal(read_define_path(out), spec)
  expect_true(validate_define(out)@summary$valid)
})

test_that("reading the ADaM example leaves no dangling ARM reference", {
  skip_if_not_installed("xml2")
  # Before the ARM reader existed, writing this spec back orphaned the two
  # leaves, four where clauses and one comment that only ARM referenced.
  out <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(
    write_spec(read_define("define21-adam.xml"), out, created = FROZEN_ARM)
  )
  checks <- define_lint(out)@findings$check
  expect_false(any(checks == "define_orphan_leaf"))
  expect_false(any(checks == "define_orphan_where_clause"))
  expect_false(any(checks == "define_orphan_comment"))
})

test_that("ARM writes into a Define-XML 2.0 document", {
  skip_if_not_installed("xml2")
  # CDISC published no 2.0 example carrying ARM, so this document exists
  # nowhere else. The ARM schemas differ only in the def: namespace they
  # import, which is the claim being tested.
  out <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(
    write_spec(
      read_define("define21-adam.xml"),
      out,
      version = "2.0",
      created = FROZEN_ARM
    )
  )
  report <- validate_define(out)
  expect_true(report@summary$valid)
  expect_identical(report@summary$define_version, "2.0")
  doc <- xml2::read_xml(out)
  expect_length(
    xml2::xml_find_all(doc, "//*[local-name()='ResultDisplay']"),
    2L
  )
  # def:PDFPageRef/@Title is 2.1-only and every ARM page reference in the
  # source carries one, so this is where a version leak would show.
  expect_length(
    xml2::xml_find_all(doc, "//*[local-name()='PDFPageRef'][@Title]"),
    0L
  )
  back <- read_define_path(out)
  expect_identical(nrow(back@arm_displays), 2L)
  expect_identical(nrow(back@arm_results), 4L)
})

test_that("the arm: namespace is declared only when ARM is present", {
  skip_if_not_installed("xml2")
  with_arm <- xml2::xml_root(xml2::read_xml(write_arm()))
  expect_identical(
    xml2::xml_attr(with_arm, "xmlns:arm"),
    "http://www.cdisc.org/ns/arm/v1.0"
  )
  spec <- arm_spec()
  spec <- artoo_spec(
    standard = "ADaMIG 1.1",
    datasets = spec@datasets,
    variables = spec@variables
  )
  without <- xml2::xml_root(xml2::read_xml(write_arm(spec)))
  expect_true(is.na(xml2::xml_attr(without, "xmlns:arm")))
})

test_that("one result over two datasets emits two arm:AnalysisDataset", {
  skip_if_not_installed("xml2")
  # The grain that forces one row per (result x dataset): each analysis
  # dataset carries its OWN where clause and its own analysis variables, and
  # a delimited string cannot express that.
  spec <- arm_spec(
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      description = "Adverse events by treatment",
      reason = "SPECIFIED IN SAP",
      purpose = "PRIMARY OUTCOME MEASURE",
      dataset = c("ADQSADAS", "ADSL"),
      variables = c("CHG PARAMCD", "TRT01P"),
      where_clause_id = c("WC.A", "WC.B"),
      order = 1L,
      stringsAsFactors = FALSE
    )
  )
  doc <- xml2::read_xml(write_arm(spec))
  expect_length(
    xml2::xml_find_all(doc, "//*[local-name()='AnalysisResult']"),
    1L
  )
  sets <- xml2::xml_find_all(doc, "//*[local-name()='AnalysisDataset']")
  expect_length(sets, 2L)
  expect_identical(
    xml2::xml_attr(sets, "ItemGroupOID"),
    c("IG.ADQSADAS", "IG.ADSL")
  )
  expect_identical(
    vapply(
      sets,
      function(s) {
        xml2::xml_attr(
          xml2::xml_find_first(s, "./*[local-name()='WhereClauseRef']"),
          "WhereClauseOID"
        )
      },
      character(1)
    ),
    c("WC.A", "WC.B")
  )
  # ...and the analysis variables resolve from names to ItemOIDs.
  expect_identical(
    xml2::xml_attr(
      xml2::xml_find_all(sets[[1]], "./*[local-name()='AnalysisVariable']"),
      "ItemOID"
    ),
    c("IT.ADQSADAS.CHG", "IT.ADQSADAS.PARAMCD")
  )
})

test_that("an analysis variable artoo cannot resolve is kept verbatim", {
  skip_if_not_installed("xml2")
  # A spec read from a document whose ARM references an item the spec does
  # not carry keeps the OID rather than losing the reference; define_lint()
  # reports it as dangling.
  spec <- arm_spec(
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      description = "x",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = "ADQSADAS",
      variables = "IT.SOMEWHERE.ELSE",
      stringsAsFactors = FALSE
    )
  )
  path <- write_arm(spec)
  expect_identical(
    xml2::xml_attr(
      xml2::xml_find_first(
        xml2::read_xml(path),
        "//*[local-name()='AnalysisVariable']"
      ),
      "ItemOID"
    ),
    "IT.SOMEWHERE.ELSE"
  )
})

test_that("a result with no reason or purpose is refused", {
  skip_if_not_installed("xml2")
  # Both are schema-required, and both are sponsor assertions about why an
  # analysis was run. A default would put a claim in the document that
  # nobody made.
  spec <- arm_spec(
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      description = "x",
      dataset = "ADSL",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_ARM),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN_ARM), error = TRUE)
})

test_that("a display with no results is refused", {
  skip_if_not_installed("xml2")
  spec <- arm_spec(
    displays = data.frame(
      display_id = c("RD.T1", "RD.ORPHAN"),
      name = c("Table 1", "Table 2"),
      order = 1:2,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_ARM),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN_ARM), error = TRUE)
})

test_that("documentation that references a page but says nothing is refused", {
  skip_if_not_installed("xml2")
  spec <- arm_spec(
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      description = "x",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = "ADSL",
      documentation_document_id = "LF.CSR",
      documentation_pages = "4",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_ARM),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN_ARM), error = TRUE)
})

test_that("a schema-required ARM text falls back rather than emitting empty", {
  skip_if_not_installed("xml2")
  spec <- arm_spec(
    displays = data.frame(
      display_id = "RD.T1",
      stringsAsFactors = FALSE
    ),
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = "ADSL",
      stringsAsFactors = FALSE
    )
  )
  doc <- xml2::read_xml(write_arm(spec))
  display <- xml2::xml_find_first(doc, "//*[local-name()='ResultDisplay']")
  expect_identical(xml2::xml_attr(display, "Name"), "RD.T1")
  expect_identical(
    xml2::xml_text(
      xml2::xml_find_first(display, ".//*[local-name()='TranslatedText']")
    ),
    "RD.T1"
  )
  expect_true(validate_define(write_arm(spec))@summary$valid)
})

test_that("programming code and its context survive", {
  skip_if_not_installed("xml2")
  spec <- arm_spec(
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      description = "x",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = "ADSL",
      programming_context = "SAS version 9.4",
      programming_code = "proc glm data = ADSL;\nrun;",
      stringsAsFactors = FALSE
    )
  )
  path <- write_arm(spec)
  code <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='ProgrammingCode']"
  )
  expect_identical(xml2::xml_attr(code, "Context"), "SAS version 9.4")
  expect_match(
    xml2::xml_text(xml2::xml_find_first(code, "./*[local-name()='Code']")),
    "proc glm"
  )
  expect_identical(
    read_define_path(path)@arm_results$programming_code,
    "proc glm data = ADSL;\nrun;"
  )
})

test_that(".dx_arm_variables splits on any run of whitespace", {
  expect_identical(artoo:::.dx_arm_variables("A  B\tC"), c("A", "B", "C"))
  expect_identical(artoo:::.dx_arm_variables(NA), character(0))
  expect_identical(artoo:::.dx_arm_variables("  "), character(0))
})

test_that("an unresolvable ItemGroup is kept verbatim, an absent one refused", {
  skip_if_not_installed("xml2")
  # A dataset the spec does not carry is passed through as an OID, so the
  # reference survives for define_lint() to report...
  kept <- arm_spec(
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      description = "x",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = "IG.NOT.IN.THIS.SPEC",
      stringsAsFactors = FALSE
    )
  )
  path <- write_arm(kept)
  expect_identical(
    xml2::xml_attr(
      xml2::xml_find_first(
        xml2::read_xml(path),
        "//*[local-name()='AnalysisDataset']"
      ),
      "ItemGroupOID"
    ),
    "IG.NOT.IN.THIS.SPEC"
  )
  expect_true(any(
    define_lint(path)@findings$check == "define_dangling_arm_item_group"
  ))

  # ...but @ItemGroupOID is required, so naming nothing at all is refused.
  none <- arm_spec(
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      description = "x",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  out <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(none, out, created = FROZEN_ARM),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(none, out, created = FROZEN_ARM), error = TRUE)
})

# ---- phase 6 review ------------------------------------------------------

test_that("a result naming no display is refused, not dropped (#p6-review-1)", {
  skip_if_not_installed("xml2")
  # The writer loops over displays, so a result whose display does not exist
  # was simply never visited. The reader cannot produce that shape, so no
  # round trip could see it -- but a workbook with a mistyped Displays sheet
  # produces exactly it.
  spec <- arm_spec(
    results = data.frame(
      display_id = c("RD.T1", "RD.TYPO"),
      result_id = c("AR.T1.R1", "AR.T1.R2"),
      description = "x",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = "ADSL",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_ARM),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN_ARM), error = TRUE)
})

test_that("results with no displays at all are refused (#p6-review-1)", {
  skip_if_not_installed("xml2")
  spec <- arm_spec(
    displays = data.frame(
      display_id = character(0),
      name = character(0),
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_ARM),
    class = "artoo_error_define"
  )
})

test_that("a result that describes itself two ways is refused (#p6-review-3)", {
  skip_if_not_installed("xml2")
  # The result-level columns repeat across a result's dataset rows. Taking
  # the first non-blank would contradict the refusal to choose a reason at
  # all when none is given.
  spec <- arm_spec(
    results = data.frame(
      display_id = "RD.T1",
      result_id = "AR.T1.R1",
      description = "x",
      reason = c("SPECIFIED IN SAP", "DATA DRIVEN"),
      purpose = "PRIMARY OUTCOME MEASURE",
      dataset = c("ADSL", "ADQSADAS"),
      order = 1L,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_ARM),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN_ARM), error = TRUE)
})

test_that("one result under two displays is refused (#p6-review-7)", {
  skip_if_not_installed("xml2")
  # ODM requires OID uniqueness and libxml2 does not check it, so this would
  # have shipped two arm:AnalysisResult elements with one OID.
  spec <- arm_spec(
    displays = data.frame(
      display_id = c("RD.T1", "RD.T2"),
      name = c("Table 1", "Table 2"),
      order = 1:2,
      stringsAsFactors = FALSE
    ),
    results = data.frame(
      display_id = c("RD.T1", "RD.T2"),
      result_id = "AR.SHARED",
      description = "x",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = "ADSL",
      order = 1:2,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_ARM),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN_ARM), error = TRUE)
})

test_that("an analysis variable in another dataset is not repointed (#p6-review-2)", {
  skip_if_not_installed("xml2")
  # An ItemOID reduced to a bare name is re-derived from the ANALYSIS
  # dataset's namespace on write, so a cross-dataset reference silently
  # became the sibling of the same name -- a different sponsor assertion,
  # schema-valid and lint-clean.
  src <- file.path(withr::local_tempdir(), "cross.xml")
  base <- readLines(test_path("fixtures", "define21-adam.xml"), warn = FALSE)
  hit <- grep('AnalysisVariable ItemOID="IT.ADQSADAS.CHG"', base, fixed = TRUE)
  expect_gt(length(hit), 0L)
  base[[hit[[1]]]] <- sub(
    "IT.ADQSADAS.CHG",
    "IT.ADSL.USUBJID",
    base[[hit[[1]]]],
    fixed = TRUE
  )
  writeLines(base, src)

  spec <- read_define_path(src)
  expect_true(any(grepl("IT.ADSL.USUBJID", spec@arm_results$variables)))
  out <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN_ARM))
  expect_identical(
    xml2::xml_attr(
      xml2::xml_find_first(
        xml2::read_xml(out),
        "//*[local-name()='AnalysisVariable']"
      ),
      "ItemOID"
    ),
    "IT.ADSL.USUBJID"
  )
  expect_true(validate_define(out)@summary$valid)
})

test_that("the duplicate-result refusal names the id that is shared (#p7-review-5)", {
  skip_if_not_installed("xml2")
  # The check indexed the full results column with a logical vector the
  # length of the deduplicated pairs frame, so R recycled it and the message
  # named a result that was not the problem -- renaming it as instructed did
  # not clear the error.
  spec <- arm_spec(
    displays = data.frame(
      display_id = c("D1", "D2"),
      name = c("One", "Two"),
      order = 1:2,
      stringsAsFactors = FALSE
    ),
    results = data.frame(
      display_id = c("D1", "D2", "D2", "D2"),
      result_id = c("R1", "R2", "R2", "R1"),
      description = "x",
      reason = "DATA DRIVEN",
      purpose = "EXPLORATORY OUTCOME MEASURE",
      dataset = c("ADSL", "ADSL", "ADQSADAS", "ADSL"),
      order = 1:4,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_ARM),
    "\"R1\""
  )
})

test_that("an analysis result orders its rows across the whole display (#p6-review-8)", {
  skip_if_not_installed("xml2")
  # Stamping every dataset row of one result with the result ordinal gave
  # .dx_row_order() duplicated values, which it discards -- so the column
  # could not order anything.
  spec <- read_define("define21-adam.xml")
  expect_identical(
    anyDuplicated(spec@arm_results$order[
      spec@arm_results$display_id == "RD.Table_14-5.02"
    ]),
    0L
  )
})

test_that("a minted value-level OID steps over one the spec supplies (#p6-review-10)", {
  # A supplied VARIABLE itemoid shaped like "<parent>.1" occupies the same
  # namespace a minted ordinal draws from, so the mint could collide with an
  # OID the user chose and the pool would then blame them for it.
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = c("VSORRES", "VSORRESU"),
      itemoid = c(NA, "IT.VS.VSORRES.1"),
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "float",
      stringsAsFactors = FALSE
    )
  )
  expect_identical(artoo:::.dx_oids(spec)$value_item, "IT.VS.VSORRES.2")
})
