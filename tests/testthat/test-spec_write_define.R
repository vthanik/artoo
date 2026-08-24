# Define-XML 2.1 writing.
#
# Four gates, in the order a failure is most useful:
#
#   1. the Tier-1 golden -- a small but COMPLETE spec, ~200 lines, the tier a
#      human reads. Regenerate it only after the other three are green.
#   2. schema validation, against the bundled CDISC schemas.
#   3. reference integrity, via define_lint().
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

  lint <- define_lint(path)
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
    "2020-01-01T00:00:00"
  )
})

test_that("the two official CDISC 2.1 examples round-trip to an identical spec", {
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

test_that("Define-XML 2.0 output is refused, for now, by name", {
  skip_if_not_installed("xml2")
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(small_spec(), path, version = "2.0", created = FROZEN),
    class = "artoo_error_define"
  )
  expect_snapshot(
    write_spec(small_spec(), path, version = "2.0", created = FROZEN),
    error = TRUE
  )
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
    title = "dm.xpt",
    stringsAsFactors = FALSE
  )
  expect_null(artoo:::.dx_archive_leaf(docs, "LF.MISSING"))
  expect_null(artoo:::.dx_archive_leaf(docs, NA_character_))
  expect_null(artoo:::.dx_archive_leaf(NULL, "LF.dm"))
  expect_identical(artoo:::.dx_archive_leaf(docs, "LF.dm")$attrs$ID, "LF.dm")
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

test_that("a spec read as 2.0 resolves to 2.0 and is refused without asking", {
  skip_if_not_installed("xml2")
  spec <- read_define("define20-sdtm.xml")
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN),
    class = "artoo_error_define"
  )
  # ...and writes as 2.1 when asked to.
  write_spec(spec, path, version = "2.1", created = FROZEN)
  expect_true(validate_define(path)@summary$valid)
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

test_that("a codelist that decodes only some of its terms is refused (#p4-review)", {
  skip_if_not_installed("xml2")
  # R writes NA into a string as the literal "NA", so an unguarded decode put
  # the characters N, A into a submission document as a sponsor assertion.
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
  expect_error(
    write_spec(spec, path, created = FROZEN),
    class = "artoo_error_codelist"
  )
  expect_snapshot(write_spec(spec, path, created = FROZEN), error = TRUE)
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
  src <- file.path(withr::local_tempdir(), "src.xml")
  base <- readLines(
    system.file("extdata", "define-minimal.xml", package = "artoo"),
    warn = FALSE
  )
  writeLines(
    sub(
      "<def:CommentDef OID=\"COM.SEX\">",
      paste0(
        "<def:CommentDef OID=\"COM.SEX\">"
      ),
      base
    ),
    src
  )
  spec <- read_spec(src)
  spec@comments$document_id <- "LF.dm"
  spec@comments$pages <- "Section_9_1"
  spec@comments$page_type <- "NamedDestination"
  out <- file.path(dirname(src), "out.xml")
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
  expect_error(suppressWarnings(read_spec(src)), class = "artoo_error_input")
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
