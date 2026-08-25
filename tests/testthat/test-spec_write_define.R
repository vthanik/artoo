# THE BYTE GOLDENS UNDER _snaps/spec_write_define/ ARE FRAGILE. Their tests
# carry skip_on_cran(), so ANY run in CRAN mode -- `Sys.unsetenv("NOT_CRAN")`
# then test_dir(), which is how the Windows check time gets profiled -- leaves
# testthat with a snapshot file whose test did not run, and it PRUNES it. The
# files then look like an intentional deletion to `git add -A`, and that is
# exactly how they were lost once. After any CRAN-mode run, check
# `git status` before staging.
# Define-XML 2.1 writing.
#
# Four gates, in the order a failure is most useful:
#
#   1. the Tier-1 golden -- a small but COMPLETE spec, ~200 lines, the tier a
#      human reads. Regenerate it only after the other three are green.
#   2. schema validation, against the bundled CDISC schemas.
#   3. reference integrity, via lint_define().
#   4. round trip: read -> write -> read reconstructs an identical spec, on
#      the two official CDISC 2.1 examples.
#
# A fifth test re-derives the profile's child order from the bundled XSDs, so
# a future CDISC revision fails HERE rather than in a submission.

# A deliberately small but complete spec: two datasets, twelve variables, a
# codelist with an NCI alias, one value-level entry behind a two-condition
# where clause, a method with a FormalExpression, a comment, and a document.
small_spec <- function() {
  artoo_spec(
    standard = "SDTMIG 3.4",
    study = data.frame(
      study_name = "ARTOO-01",
      study_description = "artoo writer example",
      protocol_name = "ARTOO-01",
      stringsAsFactors = FALSE
    ),
    datasets = data.frame(
      dataset = c("DM", "VS"),
      label = c("Demographics", "Vital Signs"),
      class = c("SPECIAL PURPOSE", "FINDINGS"),
      structure = c("One record per subject", NA),
      keys = c("STUDYID USUBJID", "STUDYID USUBJID VSTESTCD VSSEQ"),
      domain = c("DM", "VS"),
      purpose = "Tabulation",
      repeating = c(FALSE, TRUE),
      archive_location_id = c("LF.dm", NA),
      standard_id = c("STD.1", "STD.1"),
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = c(rep("DM", 5), rep("VS", 7)),
      variable = c(
        "STUDYID",
        "USUBJID",
        "SEX",
        "AGE",
        "COUNTRY",
        "STUDYID",
        "USUBJID",
        "VSSEQ",
        "VSTESTCD",
        "VSORRES",
        "VSORRESU",
        "VSDTC"
      ),
      label = c(
        "Study Identifier",
        "Unique Subject Identifier",
        "Sex",
        "Age",
        "Country",
        "Study Identifier",
        "Unique Subject Identifier",
        "Sequence Number",
        "Vital Signs Test Short Name",
        "Result or Finding in Original Units",
        "Original Units",
        "Date/Time of Measurements"
      ),
      data_type = c(
        "string",
        "string",
        "string",
        "integer",
        "string",
        "string",
        "string",
        "integer",
        "string",
        "string",
        "string",
        "datetime"
      ),
      length = c(20L, 30L, 1L, 8L, 3L, 20L, 30L, 8L, 8L, 20L, 5L, 19L),
      order = c(1:5, 1:7),
      key_sequence = c(1L, 2L, NA, NA, NA, 1L, 2L, 4L, 3L, NA, NA, NA),
      mandatory = c(
        TRUE,
        TRUE,
        FALSE,
        FALSE,
        FALSE,
        rep(TRUE, 4),
        rep(FALSE, 3)
      ),
      codelist_id = c(NA, NA, "CL.SEX", NA, NA, NA, NA, NA, NA, NA, NA, NA),
      origin = c(
        "Protocol",
        "Derived",
        "Collected",
        "Collected",
        "Collected",
        "Protocol",
        "Derived",
        "Derived",
        "Collected",
        "Collected",
        "Collected",
        "Collected"
      ),
      source = c(
        NA,
        NA,
        "Investigator",
        "Investigator",
        "Investigator",
        NA,
        NA,
        NA,
        "Investigator",
        "Investigator",
        "Investigator",
        "Investigator"
      ),
      method_id = c(
        NA,
        "MT.USUBJID",
        NA,
        NA,
        NA,
        NA,
        "MT.USUBJID",
        NA,
        NA,
        NA,
        NA,
        NA
      ),
      comment_id = c(NA, NA, "COM.SEX", NA, NA, NA, NA, NA, NA, NA, NA, NA),
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL.SEX",
      term = c("F", "M"),
      decode = c("Female", "Male"),
      order = 1:2,
      name = "Sex",
      data_type = "text",
      nci_code = "C66731",
      term_nci_code = c("C16576", "C20197"),
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause_id = "WC.VS.HEIGHT.CM",
      label = "Height in centimetres",
      data_type = "float",
      length = 5L,
      significant_digits = 1L,
      order = 1L,
      mandatory = TRUE,
      origin = "Collected",
      source = "Investigator",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.VS.HEIGHT.CM",
      check_order = c(1L, 2L),
      dataset = "VS",
      variable = c("VSTESTCD", "VSORRESU"),
      comparator = c("EQ", "IN"),
      soft_hard = "Soft",
      value = c("HEIGHT", "cm"),
      value_order = 1L,
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = "MT.USUBJID",
      name = "Derive USUBJID",
      type = "Computation",
      description = "Concatenate STUDYID and SUBJID.",
      stringsAsFactors = FALSE
    ),
    method_expressions = data.frame(
      method_id = "MT.USUBJID",
      order = 1L,
      context = "SAS",
      code = "usubjid = catx('-', studyid, subjid);",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "COM.SEX",
      description = "Sex is collected once at screening.",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "LF.dm",
      title = "dm.xpt",
      href = "dm.xpt",
      role = "archive",
      stringsAsFactors = FALSE
    ),
    standards = data.frame(
      standard_id = "STD.1",
      name = "SDTMIG",
      type = "IG",
      version = "3.4",
      status = "Final",
      is_primary = TRUE,
      order = 1L,
      stringsAsFactors = FALSE
    )
  )
}

# A frozen timestamp, so the golden is a property of the spec and not of the
# clock. Same argument as the XPT writer's `created`.
FROZEN <- "2020-01-01 00:00:00"

write_small <- function(...) {
  path <- file.path(
    withr::local_tempdir(.local_envir = parent.frame()),
    "define.xml"
  )
  write_spec(small_spec(), path, created = FROZEN, ...)
  path
}

test_that("the Tier-1 golden is stable", {
  skip_if_not_installed("xml2")
  skip_on_cran()
  path <- write_small()
  # A fixed basename, because the snapshot must not embed a temp directory.
  expect_snapshot_file(path, "define21-small.xml")
})

test_that("the written document is schema-valid and reference-clean", {
  skip_if_not_installed("xml2")
  path <- write_small()

  report <- validate_define(path)
  expect_true(report@summary$valid)
  expect_identical(report@summary$define_version, "2.1")

  lint <- lint_define(path)
  expect_identical(nrow(lint@findings), 0L)
})

test_that("write_spec() emits the stylesheet PI and copies the stylesheet", {
  skip_if_not_installed("xml2")
  path <- write_small()
  lines <- readLines(path, n = 2L)
  expect_match(
    lines[[2]],
    '^<\\?xml-stylesheet type="text/xsl" href="define2-1.xsl"\\?>$'
  )
  expect_true(file.exists(file.path(dirname(path), "define2-1.xsl")))
})

test_that("stylesheet = FALSE writes no PI and copies nothing", {
  skip_if_not_installed("xml2")
  path <- write_small(stylesheet = FALSE)
  expect_false(any(grepl("xml-stylesheet", readLines(path, n = 3L))))
  expect_false(file.exists(file.path(dirname(path), "define2-1.xsl")))
})

test_that("stylesheet = <href> names that file without copying one", {
  skip_if_not_installed("xml2")
  path <- write_small(stylesheet = "../style/define.xsl")
  expect_match(readLines(path, n = 2L)[[2]], 'href="\\.\\./style/define\\.xsl"')
  expect_false(file.exists(file.path(dirname(path), "define2-1.xsl")))
})

test_that("output is byte-stable for a frozen timestamp", {
  skip_if_not_installed("xml2")
  a <- write_small()
  b <- write_small()
  expect_identical(
    readBin(a, "raw", file.size(a)),
    readBin(b, "raw", file.size(b))
  )
})

test_that("CreationDateTime is UTC and comes from `created`", {
  skip_if_not_installed("xml2")
  path <- write_small()
  doc <- xml2::read_xml(path)
  expect_identical(
    xml2::xml_attr(xml2::xml_root(doc), "CreationDateTime"),
    "2020-01-01T00:00:00Z"
  )
})

test_that("the two official CDISC 2.1 examples round-trip to an identical spec", {
  # Gated on CRAN: a breadth loop over the bundled CDISC corpora, which is
  # where the Windows check time goes. It runs in full on CI, on every
  # platform, so the coverage is not lost -- only CRAN's clock is spared.
  skip_on_cran()
  skip_if_not_installed("xml2")
  for (f in c("define21-sdtm.xml", "define21-adam.xml")) {
    spec <- read_define(f)
    out <- file.path(withr::local_tempdir(), f)
    write_spec(spec, out, created = FROZEN)
    expect_equal(read_spec(out), spec, info = f)
    expect_true(validate_define(out)@summary$valid, info = f)
  }
})

test_that("value-level metadata emits all five artefacts", {
  skip_if_not_installed("xml2")
  doc <- xml2::read_xml(write_small())
  find <- function(x) {
    xml2::xml_find_all(doc, sprintf("//*[local-name()='%s']", x))
  }

  # 1. the parent's def:ValueListRef, 2. the def:ValueListDef they name
  vlref <- find("ValueListRef")
  vldef <- find("ValueListDef")
  expect_length(vlref, 1L)
  expect_identical(
    xml2::xml_attr(vlref, "ValueListOID"),
    xml2::xml_attr(vldef, "OID")
  )

  # 3. a real ItemDef for the value-level row, with its OWN type
  ref <- xml2::xml_find_first(vldef, "./*[local-name()='ItemRef']")
  item <- xml2::xml_find_first(
    doc,
    sprintf(
      "//*[local-name()='ItemDef'][@OID='%s']",
      xml2::xml_attr(ref, "ItemOID")
    )
  )
  expect_false(is.na(item))
  expect_identical(xml2::xml_attr(item, "DataType"), "float")

  # 4. the def:WhereClauseRef inside that ItemRef, 5. the clause it names
  wcref <- xml2::xml_find_first(ref, "./*[local-name()='WhereClauseRef']")
  expect_identical(xml2::xml_attr(wcref, "WhereClauseOID"), "WC.VS.HEIGHT.CM")
  wcdef <- find("WhereClauseDef")
  expect_length(wcdef, 1L)
  # Both conditions survive, in order, as separate RangeChecks.
  checks <- xml2::xml_find_all(wcdef, "./*[local-name()='RangeCheck']")
  expect_length(checks, 2L)
  expect_identical(xml2::xml_attr(checks, "Comparator"), c("EQ", "IN"))
})

test_that("a shared ItemDef OID is emitted once", {
  skip_if_not_installed("xml2")
  spec <- read_define("define21-sdtm.xml")
  out <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, out, created = FROZEN)
  doc <- xml2::read_xml(out)
  oids <- xml2::xml_attr(
    xml2::xml_find_all(doc, "//*[local-name()='ItemDef']"),
    "OID"
  )
  expect_identical(anyDuplicated(oids), 0L)
  # ...and it is still referenced more than once, so the pooling is real.
  refs <- xml2::xml_attr(
    xml2::xml_find_all(doc, "//*[local-name()='ItemRef']"),
    "ItemOID"
  )
  expect_gt(length(refs), length(oids))
})

test_that("def:Structure falls back to the dataset keys", {
  skip_if_not_installed("xml2")
  doc <- xml2::read_xml(write_small())
  vs <- xml2::xml_find_first(
    doc,
    "//*[local-name()='ItemGroupDef'][@Name='VS']"
  )
  expect_identical(
    xml2::xml_attr(vs, "Structure"),
    "One record per STUDYID, USUBJID, VSTESTCD, VSSEQ"
  )
})

test_that("a dataset with neither structure nor keys is refused", {
  skip_if_not_installed("xml2")
  spec <- artoo_spec(
    datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN), error = TRUE)
  expect_false(file.exists(path))
})

test_that("a value-level row qualifying an absent variable is refused", {
  skip_if_not_installed("xml2")
  # artoo_spec() refuses a blank variables$data_type outright, so the only
  # way a required ItemDef/@DataType can go missing is a value-level row
  # qualifying a variable the spec does not carry.
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per subject per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN), error = TRUE)
  expect_false(file.exists(path))
})

test_that("a value-level row with no data type inherits the parent's", {
  skip_if_not_installed("xml2")
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per subject per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = c("USUBJID", "VSORRES"),
      data_type = c("string", "float"),
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = NA_character_,
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
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = FROZEN)
  types <- xml2::xml_attr(
    xml2::xml_find_all(
      xml2::read_xml(path),
      "//*[local-name()='ItemDef'][@Name='VSORRES']"
    ),
    "DataType"
  )
  expect_identical(unique(types), "float")
})

test_that("an unknown version is refused as input", {
  skip_if_not_installed("xml2")
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(small_spec(), path, version = "3.0", created = FROZEN),
    class = "artoo_error_input"
  )
})

test_that("the spec's own def:DefineVersion revision survives a round trip", {
  skip_if_not_installed("xml2")
  spec <- read_define("define21-sdtm.xml")
  expect_identical(spec@study$define_version, "2.1.10")
  out <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, out, created = FROZEN)
  mdv <- xml2::xml_find_first(
    xml2::read_xml(out),
    "//*[local-name()='MetaDataVersion']"
  )
  expect_identical(xml2::xml_attr(mdv, "DefineVersion"), "2.1.10")
})

test_that("an archive leaf lands inside its ItemGroupDef, others on the MDV", {
  skip_if_not_installed("xml2")
  doc <- xml2::read_xml(write_small())
  dm <- xml2::xml_find_first(
    doc,
    "//*[local-name()='ItemGroupDef'][@Name='DM']"
  )
  expect_length(xml2::xml_find_all(dm, "./*[local-name()='leaf']"), 1L)
  mdv <- xml2::xml_find_first(doc, "//*[local-name()='MetaDataVersion']")
  expect_length(xml2::xml_find_all(mdv, "./*[local-name()='leaf']"), 0L)
})

test_that("the profile's child order still matches the bundled schemas", {
  skip_if_not_installed("xml2")
  # Re-derive every xs:sequence artoo relies on straight from the XSDs, so a
  # future CDISC revision fails HERE and not in a submission.
  for (version in c("2.0", "2.1")) {
    p <- artoo:::.define_profile(version)
    derived <- .dx_schema_order(version)
    for (element in names(derived)) {
      declared <- p$order[[element]]
      if (is.null(declared)) {
        next
      }
      # artoo emits a subset of each sequence; what must hold is that the
      # subset appears in the schema's order.
      expect_identical(
        declared[declared %in% derived[[element]]],
        intersect(derived[[element]], declared),
        info = paste(version, element)
      )
    }
  }
})

test_that("the MetaDataVersion name follows the standard, or the spec", {
  bare <- artoo_spec(
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  expect_identical(artoo:::.dx_mdv_name(bare), "Data Definitions")
  expect_identical(
    artoo:::.dx_mdv_name(small_spec()),
    "SDTMIG 3.4 Data Definitions"
  )

  named <- artoo_spec(
    study = data.frame(
      metadata_version_name = "Version 3, amended",
      stringsAsFactors = FALSE
    ),
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  expect_identical(artoo:::.dx_mdv_name(named), "Version 3, amended")
})

test_that("an archive location naming no document emits no leaf", {
  docs <- data.frame(
    document_id = "LF.dm",
    href = "dm.xpt",
    title = "dm transport file",
    stringsAsFactors = FALSE
  )
  expect_null(artoo:::.dx_archive_leaf(docs, "LF.MISSING"))
  expect_null(artoo:::.dx_archive_leaf(docs, NA_character_))
  expect_null(artoo:::.dx_archive_leaf(NULL, "LF.dm"))
  expect_identical(artoo:::.dx_archive_leaf(docs, "LF.dm")$attrs$ID, "LF.dm")
  # A STATED id that resolves to nothing stays a dangle for lint_define()
  # to report, even when a dataset name is at hand: minting a leaf here
  # would pair a def:ArchiveLocationID of one name with a leaf of another.
  expect_null(artoo:::.dx_archive_leaf(docs, "LF.MISSING", "DM", FALSE))
  # A DERIVED id prefers the document already carrying it -- title and all
  # -- and mints the conventional leaf only when no document does.
  reused <- artoo:::.dx_archive_leaf(docs, NA_character_, "dm", FALSE)
  expect_identical(reused$attrs$ID, "LF.dm")
  expect_identical(reused$kids[["def:title"]]$text, "dm transport file")
  minted <- artoo:::.dx_archive_leaf(docs, NA_character_, "AE", FALSE)
  expect_identical(minted$attrs$ID, "LF.AE")
  expect_identical(minted$attrs[["xlink:href"]], "ae.xpt")
})

test_that("a derived archive location reuses the document carrying its id (#p12-final-1)", {
  skip_if_not_installed("xml2")
  # A define read through a workbook keeps its leaves on the documents
  # table and loses only the pointer -- the workbook has no
  # archive-location column. Deriving LF.<DATASET> then minted a SECOND
  # leaf beside the one the documents table already carried, and an xs:ID
  # may appear once, so the write refused its own round trip.
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
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "LF.DM",
      title = "dm transport file",
      href = "dm.xpt",
      role = "other",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "define.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN, stylesheet = FALSE)
  ))
  doc <- xml2::read_xml(path)
  leaves <- xml2::xml_find_all(
    doc,
    "//*[local-name()='leaf'][@ID='LF.DM']",
    ns = character()
  )
  expect_length(leaves, 1L)
  # ...and the one leaf sits inside the ItemGroupDef that references it,
  # wearing the document's own title rather than a minted one.
  expect_identical(
    xml2::xml_name(xml2::xml_parent(leaves[[1L]])),
    "ItemGroupDef"
  )
  ig <- xml2::xml_find_first(
    doc,
    "//*[local-name()='ItemGroupDef'][@Name='DM']",
    ns = character()
  )
  expect_identical(xml2::xml_attr(ig, "ArchiveLocationID"), "LF.DM")
  expect_identical(
    xml2::xml_text(xml2::xml_find_first(
      leaves[[1L]],
      ".//*[local-name()='title']"
    )),
    "dm transport file"
  )
})

test_that("a leaf with no title falls back to its id", {
  expect_identical(
    artoo:::.dx_leaf("LF.1", "a.pdf", NA_character_)$kids[["def:title"]]$text,
    "LF.1"
  )
})

test_that("GlobalVariables falls back along study name, protocol, then a placeholder", {
  build <- function(...) {
    artoo_spec(
      study = data.frame(..., stringsAsFactors = FALSE),
      datasets = data.frame(
        dataset = "DM",
        structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      variables = data.frame(
        dataset = "DM",
        variable = "USUBJID",
        data_type = "string",
        stringsAsFactors = FALSE
      )
    )
  }
  text_of <- function(node, name) node$kids[[name]]$text

  only_protocol <- artoo:::.dx_global_variables(build(protocol_name = "P-01"))
  expect_identical(text_of(only_protocol, "StudyName"), "P-01")
  expect_identical(text_of(only_protocol, "StudyDescription"), "P-01")

  nothing <- artoo:::.dx_global_variables(build(other = "x"))
  expect_identical(text_of(nothing, "StudyName"), "Unspecified")
  expect_identical(text_of(nothing, "ProtocolName"), "Unspecified")
})

test_that("a missing bundled stylesheet is not an error", {
  skip_if_not_installed("xml2")
  testthat::local_mocked_bindings(.artoo_extdata = function(...) "")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  # `validate` is off because the schema tree is mocked away with the sheet.
  # The document still names the stylesheet in its processing instruction, so
  # a silent failure would hand the user a conformance finding to discover
  # later; it warns instead.
  expect_warning(
    write_spec(small_spec(), path, created = FROZEN, validate = FALSE),
    class = "artoo_warning_define"
  )
  expect_true(file.exists(path))
  expect_false(file.exists(file.path(dir, "define2-1.xsl")))
})

test_that("an invalid document never replaces the target file", {
  skip_if_not_installed("xml2")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  writeLines("PRIOR GOOD FILE", path)

  # Force the schema gate to fail, standing in for a writer defect.
  testthat::local_mocked_bindings(
    validate_define = function(path, version = NULL) {
      artoo:::artoo_check_class(
        findings = artoo:::.finding(
          "define_schema_invalid",
          dataset = NA_character_,
          variable = NA_character_,
          message = "Element 'ItemDef': something is wrong."
        ),
        summary = list(define_version = "2.1", valid = FALSE, n_errors = 1L)
      )
    }
  )
  expect_error(
    write_spec(small_spec(), path, created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(
    write_spec(small_spec(), path, created = FROZEN),
    error = TRUE,
    transform = function(x) sub("'.*/define\\.xml'", "'<tmp>/define.xml'", x)
  )
  expect_identical(readLines(path), "PRIOR GOOD FILE")
})

test_that("a spec read as 2.0 is written as 2.0 without being asked", {
  # Gated on CRAN: a breadth loop over the bundled CDISC corpora, which is
  # where the Windows check time goes. It runs in full on CI, on every
  # platform, so the coverage is not lost -- only CRAN's clock is spared.
  skip_on_cran()
  skip_if_not_installed("xml2")
  spec <- read_define("define20-sdtm.xml")
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = FROZEN)
  expect_identical(validate_define(path)@summary$define_version, "2.0")
  # ...and as 2.1 when asked to.
  write_spec(spec, path, version = "2.1", created = FROZEN)
  expect_identical(validate_define(path)@summary$define_version, "2.1")
})

test_that("a PDF page RANGE survives a round trip (#p5)", {
  skip_if_not_installed("xml2")
  # def:PDFPageRef states its pages as EITHER a @PageRefs list or a
  # @FirstPage/@LastPage range, and reading only the list dropped every range
  # silently. The CDISC 2.0 SDTM example annotates most of its CRF that way.
  spec <- read_define("define20-sdtm.xml")
  ranges <- spec@variables$pages[grepl("^[0-9]+-[0-9]+$", spec@variables$pages)]
  expect_gt(length(ranges), 0L)
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = FROZEN)
  pg <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='PDFPageRef'][@FirstPage]"
  )
  expect_false(is.na(pg))
  expect_true(is.na(xml2::xml_attr(pg, "PageRefs")))
  expect_identical(read_define_path(path)@variables$pages, spec@variables$pages)
})

test_that("variables emit in the order column's order (#p4-review)", {
  skip_if_not_installed("xml2")
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = c("A", "B", "C"),
      data_type = "string",
      order = c(2L, 3L, 1L),
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = FROZEN)
  refs <- xml2::xml_find_all(
    xml2::read_xml(path),
    "//*[local-name()='ItemRef']"
  )
  expect_identical(
    xml2::xml_attr(refs, "ItemOID"),
    c("IT.DM.C", "IT.DM.A", "IT.DM.B")
  )
  expect_identical(xml2::xml_attr(refs, "OrderNumber"), c("1", "2", "3"))
})

test_that("a document's own identity survives a round trip (#p4-review)", {
  skip_if_not_installed("xml2")
  # Minting fresh identifiers from the study name breaks every external
  # reference into the document: a reviewer's bookmark, a prior submission,
  # a tracking system.
  src <- system.file("extdata", "define-minimal.xml", package = "artoo")
  out <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(read_spec(src), out, created = FROZEN)
  a <- xml2::read_xml(src)
  b <- xml2::read_xml(out)
  at <- function(doc, el, name) {
    xml2::xml_attr(
      xml2::xml_find_first(doc, sprintf("//*[local-name()='%s']", el)),
      name
    )
  }
  expect_identical(at(b, "Study", "OID"), at(a, "Study", "OID"))
  expect_identical(
    at(b, "MetaDataVersion", "OID"),
    at(a, "MetaDataVersion", "OID")
  )
  expect_identical(
    at(b, "MetaDataVersion", "Name"),
    at(a, "MetaDataVersion", "Name")
  )
  expect_identical(
    xml2::xml_attr(xml2::xml_root(b), "FileOID"),
    xml2::xml_attr(xml2::xml_root(a), "FileOID")
  )
  # ...including the ODM context, which artoo has no standing to assert.
  expect_identical(
    xml2::xml_attr(xml2::xml_root(b), "Context"),
    xml2::xml_attr(xml2::xml_root(a), "Context")
  )
})

test_that("a codelist that decodes only some of its terms writes an empty Decode (#p4-review)", {
  skip_if_not_installed("xml2")
  # R writes NA into a string as the literal "NA", so an unguarded decode put
  # the characters N, A into a submission document as a sponsor assertion.
  # Refusing the whole list was the first guard, and it was stricter than
  # the standard: partly-decoded lists are ordinary sponsor input, and the
  # term the author left blank gets <Decode><TranslatedText/></Decode> --
  # decoded, nothing to say -- never the string "NA".
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "SEX",
      data_type = "string",
      codelist_id = "CL.SEX",
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL.SEX",
      term = c("M", "F", "U"),
      decode = c("Male", "Female", NA),
      name = "Sex",
      data_type = "text",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN, stylesheet = FALSE)
  ))
  doc <- xml2::read_xml(path)
  items <- xml2::xml_find_all(doc, "//*[local-name()='CodeListItem']")
  expect_length(items, 3L)
  decodes <- vapply(
    items,
    function(n) {
      xml2::xml_text(xml2::xml_find_first(
        n,
        ".//*[local-name()='TranslatedText']"
      ))
    },
    character(1)
  )
  expect_identical(decodes, c("Male", "Female", ""))
})

test_that("NA text is refused rather than written as the string NA (#p4-review)", {
  skip_if_not_installed("xml2")
  doc <- xml2::xml_new_root(
    "ODM",
    "xmlns" = "http://www.cdisc.org/ns/odm/v1.3"
  )
  node <- artoo:::.dx_node("StudyName", text = NA_character_)
  expect_error(
    artoo:::.dx_emit(doc, node, artoo:::.define_profile("2.1")),
    class = "artoo_error_define"
  )
})

test_that("a comment's page type is not rewritten as a physical page (#p4-review)", {
  skip_if_not_installed("xml2")
  spec <- read_spec(
    system.file("extdata", "define-minimal.xml", package = "artoo")
  )
  spec@comments$document_id <- "LF.dm"
  spec@comments$pages <- "Section_9_1"
  spec@comments$page_type <- "NamedDestination"
  out <- file.path(withr::local_tempdir(), "out.xml")
  write_spec(spec, out, created = FROZEN)
  pg <- xml2::xml_find_first(
    xml2::read_xml(out),
    "//*[local-name()='CommentDef']//*[local-name()='PDFPageRef']"
  )
  expect_identical(xml2::xml_attr(pg, "Type"), "NamedDestination")
  expect_identical(read_spec(out)@comments$page_type, "NamedDestination")
})

test_that("several def:WhereClauseRefs on one item are refused, not narrowed", {
  skip_if_not_installed("xml2")
  # Define-XML combines them with OR. Keeping the first silently changes which
  # rows the value-level definition applies to.
  src <- file.path(withr::local_tempdir(), "or.xml")
  base <- readLines(test_path("fixtures", "define21-adam.xml"), warn = FALSE)
  hit <- grep("<def:WhereClauseRef", base)[[1]]
  base[[hit]] <- paste0(base[[hit]], "\n", base[[hit]])
  writeLines(base, src)
  expect_error(suppressWarnings(read_spec(src)), class = "artoo_error_spec")
  expect_snapshot(
    suppressWarnings(read_spec(src)),
    error = TRUE,
    transform = function(x) sub("'.*/or\\.xml'", "'<tmp>/or.xml'", x)
  )
})

test_that("a spec declaring a version artoo cannot write is refused", {
  spec <- artoo_spec(
    study = data.frame(define_version = "1.0.0", stringsAsFactors = FALSE),
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  expect_error(
    artoo:::.dx_target_version(NULL, spec),
    class = "artoo_error_input"
  )
  expect_snapshot(artoo:::.dx_target_version(NULL, spec), error = TRUE)
})

# ---- Define-XML 2.0 -------------------------------------------------------

test_that("the 2.0 golden is stable", {
  skip_if_not_installed("xml2")
  skip_on_cran()
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  suppressWarnings(
    write_spec(small_spec(), path, version = "2.0", created = FROZEN)
  )
  expect_snapshot_file(path, "define20-small.xml")
})

test_that("both official CDISC 2.0 examples reach a fixed point", {
  # Gated on CRAN: a breadth loop over the bundled CDISC corpora, which is
  # where the Windows check time goes. It runs in full on CI, on every
  # platform, so the coverage is not lost -- only CRAN's clock is spared.
  skip_on_cran()
  skip_if_not_installed("xml2")
  # Identity is the wrong invariant here, and deliberately so: the writer
  # emits in OrderNumber order, and define20-sdtm.xml carries codelist terms
  # whose physical order disagrees with their OrderNumber. The round trip
  # therefore returns a CANONICALISED spec, not the source's row order. What
  # must hold is that writing it again changes nothing.
  for (f in c("define20-sdtm.xml", "define20-adam.xml")) {
    dir <- withr::local_tempdir()
    first <- file.path(dir, "first.xml")
    second <- file.path(dir, "second.xml")
    suppressWarnings(write_spec(read_define(f), first, created = FROZEN))
    suppressWarnings(
      write_spec(read_define_path(first), second, created = FROZEN)
    )
    expect_identical(
      readLines(first, warn = FALSE),
      readLines(second, warn = FALSE),
      info = f
    )
    expect_equal(read_define_path(second), read_define_path(first), info = f)
    expect_true(validate_define(first)@summary$valid, info = f)
  }
})

test_that("a source already in OrderNumber order round-trips to an identical spec", {
  skip_if_not_installed("xml2")
  # The stronger claim, where the source admits it: nothing is normalised
  # away, so read -> write -> read reconstructs the spec exactly.
  for (f in c("define20-adam.xml", "define21-sdtm.xml", "define21-adam.xml")) {
    spec <- read_define(f)
    out <- file.path(withr::local_tempdir(), f)
    suppressWarnings(write_spec(spec, out, created = FROZEN))
    expect_equal(read_define_path(out), spec, info = f)
  }
})

test_that("every spec converts to the other version and stays valid", {
  # Gated on CRAN: a breadth loop over the bundled CDISC corpora, which is
  # where the Windows check time goes. It runs in full on CI, on every
  # platform, so the coverage is not lost -- only CRAN's clock is spared.
  skip_on_cran()
  skip_if_not_installed("xml2")
  # The eight-way matrix: each example written as each version.
  for (f in c(
    "define20-sdtm.xml",
    "define20-adam.xml",
    "define21-sdtm.xml",
    "define21-adam.xml"
  )) {
    spec <- read_define(f)
    for (version in c("2.0", "2.1")) {
      out <- file.path(withr::local_tempdir(), paste0(version, "-", f))
      suppressWarnings(write_spec(
        spec,
        out,
        version = version,
        created = FROZEN
      ))
      report <- validate_define(out)
      expect_true(report@summary$valid, info = paste(f, "->", version))
      expect_identical(report@summary$define_version, version, info = f)
    }
  }
})

test_that("the version switch is exactly the set of things the standards renamed", {
  skip_if_not_installed("xml2")
  # Pins the switch as DELIBERATE. Anything else that starts differing between
  # the two outputs of one spec is an accident until this list says otherwise.
  dir <- withr::local_tempdir()
  a <- file.path(dir, "v21.xml")
  b <- file.path(dir, "v20.xml")
  spec <- small_spec()
  write_spec(spec, a, version = "2.1", created = FROZEN, stylesheet = FALSE)
  suppressWarnings(
    write_spec(spec, b, version = "2.0", created = FROZEN, stylesheet = FALSE)
  )

  census <- function(path) {
    nodes <- xml2::xml_find_all(xml2::read_xml(path), "//*")
    list(
      elements = unique(vapply(nodes, xml2::xml_name, character(1))),
      attributes = unique(unlist(lapply(nodes, function(n) {
        paste0(xml2::xml_name(n), "@", names(xml2::xml_attrs(n)))
      })))
    )
  }
  v21 <- census(a)
  v20 <- census(b)

  expect_setequal(
    setdiff(v21$elements, v20$elements),
    c("Standards", "Standard", "Class")
  )
  expect_identical(setdiff(v20$elements, v21$elements), character(0))
  expect_setequal(
    setdiff(v21$attributes, v20$attributes),
    c(
      "Standards@",
      "Standard@OID",
      "Standard@Name",
      "Standard@Type",
      "Standard@Version",
      "Standard@Status",
      "Class@Name",
      "ItemGroupDef@StandardOID",
      "ODM@Context",
      "Origin@Source"
    )
  )
  expect_setequal(
    setdiff(v20$attributes, v21$attributes),
    c(
      "ItemGroupDef@Class",
      "MetaDataVersion@StandardName",
      "MetaDataVersion@StandardVersion"
    )
  )
})

test_that("a downgrade says once what it cannot carry", {
  skip_if_not_installed("xml2")
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_warning(
    write_spec(
      read_define("define21-sdtm.xml"),
      path,
      version = "2.0",
      created = FROZEN
    ),
    class = "artoo_warning_define"
  )
  expect_snapshot(
    spec <- write_spec(
      read_define("define21-sdtm.xml"),
      path,
      version = "2.0",
      created = FROZEN
    )
  )
  # ...and says nothing when there is nothing to say.
  expect_no_condition(
    write_spec(small_spec(), path, version = "2.1", created = FROZEN),
    class = "artoo_warning_define"
  )
})

test_that("2.0 asserts def:DefineVersion rather than echoing the spec", {
  skip_if_not_installed("xml2")
  # 2.0 fixes the value at 2.0.0, and libxml2 drops `fixed` through
  # xs:redefine, so the schema gate cannot catch a wrong one.
  spec <- read_define("define21-sdtm.xml")
  expect_identical(spec@study$define_version, "2.1.10")
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(write_spec(spec, path, version = "2.0", created = FROZEN))
  mdv <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='MetaDataVersion']"
  )
  expect_identical(xml2::xml_attr(mdv, "DefineVersion"), "2.0.0")
})

test_that("2.0 takes its single standard from the primary row, or the scalar", {
  skip_if_not_installed("xml2")
  p20 <- artoo:::.define_profile("2.0")
  # From the standards table's is_primary row.
  expect_identical(
    artoo:::.dx_standard_attrs(read_define("define21-sdtm.xml"), p20),
    list(`def:StandardName` = "SDTMIG", `def:StandardVersion` = "3.1.2")
  )
  # From the scalar @standard when there is no standards table -- the shape a
  # spec built from a workbook has.
  expect_identical(
    artoo:::.dx_standard_attrs(small_spec(), p20),
    list(`def:StandardName` = "SDTMIG", `def:StandardVersion` = "3.4")
  )
})

test_that("2.0 refuses a spec that names no standard at all", {
  skip_if_not_installed("xml2")
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, version = "2.0", created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(
    write_spec(spec, path, version = "2.0", created = FROZEN),
    error = TRUE
  )
})

# ---- phase 5 review ------------------------------------------------------

test_that("a define naming no standard never writes StandardName=\"NA\" (#p5-review-1)", {
  skip_if_not_installed("xml2")
  # def:Standards is minOccurs="0", so a 2.1 document may name no standard.
  # Pasting its two absent halves into one scalar produced "NA NA", which the
  # 2.0 writer then split back into two attributes reading "NA" -- valid
  # against the schema, and asserting to a reviewer that the standard is
  # literally NA.
  src <- file.path(withr::local_tempdir(), "nostd.xml")
  base <- readLines(
    system.file("extdata", "define-minimal.xml", package = "artoo"),
    warn = FALSE
  )
  from <- grep("<def:Standards>", base, fixed = TRUE)
  to <- grep("</def:Standards>", base, fixed = TRUE)
  expect_length(from, 1L)
  writeLines(base[-(from:to)], src)

  spec <- read_define_path(src)
  expect_true(is.na(spec@standard))
  expect_identical(nrow(spec@standards), 0L)

  out <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, out, version = "2.0", created = FROZEN),
    class = "artoo_error_define"
  )
  expect_false(file.exists(out))
})

test_that("a standard version containing a space survives (#p5-review-2)", {
  # Gated on CRAN: a breadth loop over the bundled CDISC corpora, which is
  # where the Windows check time goes. It runs in full on CI, on every
  # platform, so the coverage is not lost -- only CRAN's clock is spared.
  skip_on_cran()
  skip_if_not_installed("xml2")
  # "3.1.2 Amendment 1" is a real published IG version. Concatenating the
  # name and version into one scalar and splitting it back on whitespace
  # moved half the version into the name.
  src <- file.path(withr::local_tempdir(), "amended.xml")
  base <- readLines(test_path("fixtures", "define20-sdtm.xml"), warn = FALSE)
  hit <- grep('def:StandardVersion="3.1.2"', base, fixed = TRUE)
  expect_length(hit, 1L)
  base[[hit]] <- sub(
    'def:StandardVersion="3.1.2"',
    'def:StandardVersion="3.1.2 Amendment 1"',
    base[[hit]],
    fixed = TRUE
  )
  writeLines(base, src)

  spec <- read_define_path(src)
  expect_identical(spec@standards$name, "SDTM-IG")
  expect_identical(spec@standards$version, "3.1.2 Amendment 1")

  out <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN))
  mdv <- xml2::xml_find_first(
    xml2::read_xml(out),
    "//*[local-name()='MetaDataVersion']"
  )
  expect_identical(xml2::xml_attr(mdv, "StandardName"), "SDTM-IG")
  expect_identical(xml2::xml_attr(mdv, "StandardVersion"), "3.1.2 Amendment 1")
})

test_that("a one-token standard is refused, not blamed on artoo (#p5-review-2)", {
  skip_if_not_installed("xml2")
  # The scalar split is only ever reached for a source that never had the two
  # fields apart. One token used to slip through and fail at the schema gate,
  # whose message blames artoo for a defect the input caused.
  spec <- artoo_spec(
    standard = "SDTMIG",
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, version = "2.0", created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(
    write_spec(spec, path, version = "2.0", created = FROZEN),
    error = TRUE
  )
})

test_that("a def:Standards block that cannot be made valid is omitted", {
  skip_if_not_installed("xml2")
  # 2.1 requires a Name from a closed list, a Version, a Type and a Status.
  # A 2.0 document carries only a free-text name and a version, so promoting
  # it wholesale produces an invalid document; omitting it is valid, and the
  # write says so rather than leaving the user to find out from a validator.
  spec <- read_define("define20-sdtm.xml")
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_warning(
    write_spec(spec, path, version = "2.1", created = FROZEN),
    class = "artoo_warning_define"
  )
  expect_true(validate_define(path)@summary$valid)
  expect_length(
    xml2::xml_find_all(
      xml2::read_xml(path),
      "//*[local-name()='Standards']"
    ),
    0L
  )
})

test_that("2.0's standard spellings are normalised to 2.1's", {
  # 2.0's name is free text and 2.1 closed the list, renaming several. That
  # is the same standard under a new spelling, not a different claim.
  p21 <- artoo:::.define_profile("2.1")
  expect_identical(artoo:::.dx_standard_names("SDTM-IG"), "SDTMIG")
  expect_identical(artoo:::.dx_standard_names("ADaM-IG"), "ADaMIG")
  expect_identical(artoo:::.dx_standard_names("SDTMIG"), "SDTMIG")
  expect_identical(artoo:::.dx_standard_name("SDTM-IG", p21), "SDTMIG")
  expect_error(
    artoo:::.dx_standard_name("Something Else", p21),
    class = "artoo_error_define"
  )
})

test_that("the document's build provenance survives a round trip", {
  skip_if_not_installed("xml2")
  spec <- read_define("define21-sdtm.xml")
  expect_identical(spec@study$originator, "CDISC Data Exchange Standards Team")
  out <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(write_spec(spec, out, created = FROZEN))
  root <- xml2::xml_root(xml2::read_xml(out))
  expect_identical(
    xml2::xml_attr(root, "Originator"),
    "CDISC Data Exchange Standards Team"
  )
  expect_identical(xml2::xml_attr(root, "SourceSystem"), "M.Hungria-System")
  expect_identical(xml2::xml_attr(root, "SourceSystemVersion"), "2.1-A1")
})

test_that("a value-level row's origin source counts as a downgrade loss", {
  skip_if_not_installed("xml2")
  # The notice checked `variables` only, so a spec whose @Source lives only
  # on value-level rows was downgraded silently.
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "float",
      origin = "Collected",
      source = "Investigator",
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
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_warning(
    write_spec(spec, path, version = "2.0", created = FROZEN),
    class = "artoo_warning_define"
  )
  expect_snapshot(
    spec <- write_spec(spec, path, version = "2.0", created = FROZEN)
  )
})

test_that("an empty standards table says so on a 2.1 write (#p6-review-5)", {
  skip_if_not_installed("xml2")
  # The partly-filled path warned and the empty path did not, which made the
  # quieter case the more misleading one: every workbook-built 2.1 define
  # shipped with no def:Standards and no mention of it.
  spec <- artoo_spec(
    standard = "ADaMIG 1.1",
    datasets = data.frame(
      dataset = "ADSL",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "ADSL",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_warning(
    write_spec(spec, path, version = "2.1", created = FROZEN),
    class = "artoo_warning_define"
  )
  expect_true(validate_define(path)@summary$valid)
})

test_that("a value-level page title counts as a downgrade loss (#p6-review-6)", {
  skip_if_not_installed("xml2")
  # The notice checked four tables for page_title and artoo carries it on
  # seven, so a spec whose only Title sits on a value-level row or an
  # analysis result was downgraded silently.
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "float",
      origin = "Collected",
      origin_document_id = "LF.acrf",
      pages = "11",
      page_type = "PhysicalRef",
      page_title = "Vital Signs page",
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
    ),
    documents = data.frame(
      document_id = "LF.acrf",
      title = "acrf.pdf",
      href = "acrf.pdf",
      role = "annotated_crf",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  lost <- NULL
  withCallingHandlers(
    write_spec(spec, path, version = "2.0", created = FROZEN),
    warning = function(w) {
      if (inherits(w, "artoo_warning_define")) {
        lost <<- conditionMessage(w)
      }
      invokeRestart("muffleWarning")
    }
  )
  expect_match(lost, "def:PDFPageRef/@Title", fixed = TRUE)
})

# ---- phase 9 review ------------------------------------------------------

test_that("a predecessor reaches the document (#p9-review-1)", {
  skip_if_not_installed("xml2")
  # Define-XML has no attribute for a predecessor: it goes in the Origin's
  # Description, and the official stylesheet renders exactly that after
  # "Predecessor:". artoo read it, stored it, and emitted an EMPTY def:Origin
  # -- so every ADaM define lost its traceability and the reviewer's
  # define.html showed a blank where the source variable belongs.
  spec <- artoo_spec(
    standard = "ADaMIG 1.1",
    datasets = data.frame(
      dataset = "ADSL",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "ADSL",
      variable = c("ARM", "AGEGR1"),
      data_type = "string",
      length = 20L,
      origin = c("Predecessor", "Assigned"),
      predecessor = c("DM.ARM", NA),
      assigned_value = c(NA, "<65"),
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(write_spec(spec, path, created = FROZEN))
  doc <- xml2::read_xml(path)
  text <- function(name) {
    xml2::xml_text(xml2::xml_find_first(
      doc,
      sprintf(
        "//*[local-name()='ItemDef'][@Name='%s']//*[local-name()='Origin']//*[local-name()='TranslatedText']",
        name
      )
    ))
  }
  expect_identical(text("ARM"), "DM.ARM")
  expect_identical(text("AGEGR1"), "<65")
  expect_true(validate_define(path)@summary$valid)
})

test_that("a predecessor that contradicts the origin description is refused", {
  skip_if_not_installed("xml2")
  spec <- artoo_spec(
    standard = "ADaMIG 1.1",
    datasets = data.frame(
      dataset = "ADSL",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "ADSL",
      variable = "ARM",
      data_type = "string",
      origin = "Predecessor",
      predecessor = "DM.ARM",
      origin_description = "Taken from AE.AETERM",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN), error = TRUE)
})

test_that("CRF pages reach the document via the annotated CRF (#p9-review-3)", {
  skip_if_not_installed("xml2")
  # The Variables sheet has a Pages column and no document column, so a page
  # number arrives with nothing to attach it to. The annotated CRF is what
  # those pages are pages OF.
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "SEX",
      data_type = "string",
      origin = "Collected",
      pages = "12",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "LF.acrf",
      title = "Annotated CRF",
      href = "acrf.pdf",
      role = "annotated_crf",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressWarnings(write_spec(spec, path, created = FROZEN))
  doc <- xml2::read_xml(path)
  page <- xml2::xml_find_first(doc, "//*[local-name()='PDFPageRef']")
  expect_identical(xml2::xml_attr(page, "PageRefs"), "12")
  expect_identical(
    xml2::xml_attr(
      xml2::xml_find_first(doc, "//*[local-name()='DocumentRef']"),
      "leafID"
    ),
    "LF.acrf"
  )
  expect_true(validate_define(path)@summary$valid)
  # ...and the container the leaf belongs in is emitted.
  expect_length(
    xml2::xml_find_all(doc, "//*[local-name()='AnnotatedCRF']"),
    1L
  )
})

test_that("pages with no annotated CRF are refused, not dropped", {
  skip_if_not_installed("xml2")
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "SEX",
      data_type = "string",
      origin = "Collected",
      pages = "12",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN), error = TRUE)
})

test_that("a value-level row with no condition is refused (#p9-review-2)", {
  skip_if_not_installed("xml2")
  # Neither other gate can see this: the schema is satisfied (an ItemRef with
  # no children is well-formed) and nothing dangles, because there is no
  # reference to dangle. But the definition then applies to every row of its
  # parent, which is a different claim.
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
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
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN), error = TRUE)
})

test_that("value-level Role survives a round trip (#p12-review-2a)", {
  skip_if_not_installed("xml2")
  # A value-level ItemRef takes Role exactly as a dataset-level one does.
  # Reading only the dataset-level pair dropped all seven Roles in CDISC's
  # own 2.1 SDTM example, and no round-trip test could see it: the reader
  # did not take them and the writer did not emit them, so both documents
  # agreed about their absence.
  spec <- read_define("define21-sdtm.xml")
  expect_gt(sum(!is.na(spec@values$role)), 0L)
  path <- file.path(withr::local_tempdir(), "define.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN, stylesheet = FALSE)
  ))
  back <- suppressWarnings(read_spec(path))
  expect_identical(back@values$role, spec@values$role)
  expect_identical(back@values$role_codelist_id, spec@values$role_codelist_id)
})

test_that("a 2.0 downgrade names the codelist comments it drops (#p12-review-2e)", {
  skip_if_not_installed("xml2")
  # 2.0 carries def:CommentOID on ItemGroupDef and ItemDef and only CodeList
  # loses it, so the document-wide check said nothing -- and artoo's own
  # linter then reported ten orphan comments against the document artoo had
  # just written.
  spec <- read_define("define21-sdtm.xml")
  expect_gt(sum(!is.na(spec@codelists$comment_id)), 0L)
  path <- file.path(withr::local_tempdir(), "define.xml")
  expect_warning(
    suppressMessages(
      write_spec(
        spec,
        path,
        version = "2.0",
        created = FROZEN,
        stylesheet = FALSE
      )
    ),
    "def:CommentOID on a CodeList"
  )
})

test_that("unmodelled content is named on read, not dropped in silence (#p12-review-2)", {
  skip_if_not_installed("xml2")
  # Four constructs artoo has no column for. Each reaches a reviewer as a
  # blank or a changed assertion, and none is visible to a round-trip test:
  # the reader does not take them and the writer does not emit them, so the
  # two documents agree about their absence.
  dir <- withr::local_tempdir()
  path <- file.path(dir, "probe.xml")
  file.copy(testthat::test_path("fixtures", "define21-sdtm.xml"), path)
  # A Sponsor alias, which CDISC's own example carries eighteen of.
  expect_warning(
    read_spec(path),
    "context artoo does not model"
  )
  # A CodeList Description and a non-English text, injected into the same
  # document so one read reports both.
  doc <- xml2::read_xml(path)
  codelist <- xml2::xml_find_first(
    doc,
    "//*[local-name()='CodeList']",
    ns = character()
  )
  xml2::xml_add_child(
    codelist,
    xml2::read_xml(
      paste0(
        "<Description xmlns='http://www.cdisc.org/ns/odm/v1.3'>",
        "<TranslatedText xml:lang='ja'>The sponsor's own words</TranslatedText>",
        "</Description>"
      )
    ),
    .where = "before"
  )
  xml2::write_xml(doc, path)
  expect_warning(read_spec(path), "carries a `Description`")
  expect_warning(read_spec(path), "other than \"en\"")
})

test_that("a sponsor's repeated coded value and comment write once, out loud (#p12-final-2)", {
  skip_if_not_installed("xml2")
  # The shape a real 18-dataset sponsor specification arrived in: one visit
  # codelist re-listing UNSCHEDULED under each regimen block, and a comment
  # stated twice, identically, once per variable that uses it. Both used to
  # reach the schema gate, which refused the write and blamed artoo.
  spec <- artoo_spec(
    standard = "ADaMIG 1.1",
    datasets = data.frame(
      dataset = "ADSL",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "ADSL",
      variable = "AVISIT",
      data_type = "string",
      codelist_id = "AVISIT",
      comment_id = "COM.1",
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "AVISIT",
      term = c("Visit 3", "UNSCHEDULED", "Visit 7", "UNSCHEDULED"),
      order = c(3L, 3L, 7L, 7L),
      name = "Analysis Visit",
      data_type = "text",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = c("COM.1", "COM.1"),
      description = "Set per the SAP.",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "define.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN, stylesheet = FALSE)
  ))
  doc <- xml2::read_xml(path)
  terms <- xml2::xml_attr(
    xml2::xml_find_all(
      doc,
      "//*[local-name()='EnumeratedItem']",
      ns = character()
    ),
    "CodedValue"
  )
  expect_identical(terms, c("Visit 3", "UNSCHEDULED", "Visit 7"))
  expect_length(
    xml2::xml_find_all(doc, "//*[local-name()='CommentDef']", ns = character()),
    1L
  )
  expect_true(validate_define(path)@summary$valid)
})

test_that("2.0 names the codelist term description and the version comment it drops", {
  skip_if_not_installed("xml2")
  # Two losses the notice knew about but nothing exercised: 2.0 has no
  # CodeListItem/Description, and its MetaDataVersion carries no
  # def:CommentOID. Both are silent data loss if the write says nothing.
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSPOS",
      data_type = "string",
      codelist_id = "CL.POS",
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL.POS",
      name = "Position",
      data_type = "text",
      term = "SUPINE",
      decode = "Supine",
      term_description = "Lying face up",
      stringsAsFactors = FALSE
    ),
    study = list(
      study_name = "S",
      metadata_version_comment_id = "COM.MDV"
    ),
    comments = data.frame(
      comment_id = "COM.MDV",
      description = "Version note",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_warning(
    write_spec(spec, path, version = "2.0", created = FROZEN),
    "CodeListItem/Description"
  )
  expect_warning(
    write_spec(spec, path, version = "2.0", created = FROZEN),
    "MetaDataVersion/@def:CommentOID",
    fixed = TRUE
  )
})

test_that("a dataset with no name and one with no data get no archive leaf", {
  # The leaf is derived, so both carve-outs matter: nothing to name it after,
  # and CDISC's own examples leave a def:HasNoData dataset without a file to
  # point at.
  expect_null(artoo:::.dx_default_archive(NA_character_))
  expect_null(artoo:::.dx_default_archive("DM", empty = TRUE))
  leaf <- artoo:::.dx_default_archive("DM")
  expect_identical(leaf$attrs$ID, "LF.DM")
  expect_identical(leaf$attrs[["xlink:href"]], "dm.xpt")
})

test_that("an unreadable file and a hrefless instruction name no stylesheet", {
  # The renderer reads the href back out of the document rather than
  # rebuilding it, so these two are the paths where there is nothing to read.
  expect_null(
    suppressWarnings(
      artoo:::.dx_pi_href(file.path(tempdir(), "absent-define.xml"))
    )
  )

  path <- file.path(withr::local_tempdir(), "d.xml")
  writeLines(
    c("<?xml version=\"1.0\"?>", "<?xml-stylesheet ?>", "<ODM/>"),
    path
  )
  expect_null(artoo:::.dx_pi_href(path))
})
