# Regression tests for the Define-XML metadata that read_spec() carries.
#
# Phase 2.5 widened the spec slots and taught the reader to fill them. Every
# number below was measured against the official CDISC examples at the time,
# and pinning them is what stops a later refactor quietly dropping metadata
# again — which is exactly how the 2.0 `class` gap survived unnoticed.

skip_if_not_installed("xml2")

fx <- function(name) {
  p <- testthat::test_path("fixtures", name)
  skip_if(!file.exists(p), paste(name, "fixture is unavailable"))
  p
}

test_that("def:Class is read from the 2.0 ATTRIBUTE, not just the 2.1 element", {
  # The regression that motivated this file. def:Class is a child element in
  # 2.1 but an attribute in 2.0; reading only the element left `class` all-NA
  # on every Define-XML 2.0 document, silently.
  spec <- read_define("define20-sdtm.xml")
  expect_identical(sum(!is.na(spec@datasets$class)), nrow(spec@datasets))
  expect_true("SPECIAL PURPOSE" %in% toupper(spec@datasets$class))

  # ...and the 2.1 element path still works.
  spec21 <- read_define("define21-sdtm.xml")
  expect_identical(sum(!is.na(spec21@datasets$class)), nrow(spec21@datasets))
})

test_that("ItemGroupDef submission attributes are carried", {
  spec <- read_define("define21-sdtm.xml")
  n <- nrow(spec@datasets)
  for (col in c("itemgroupoid", "domain", "sas_dataset_name", "purpose")) {
    expect_identical(sum(!is.na(spec@datasets[[col]])), n, info = col)
  }
  expect_type(spec@datasets$repeating, "logical")
  expect_type(spec@datasets$has_no_data, "logical")

  # def:ArchiveLocationID is absent exactly where def:HasNoData is set: a
  # dataset with no data legitimately has no file to point at, and the 2.1
  # spec makes the attribute conditional on precisely that.
  no_data <- !is.na(spec@datasets$has_no_data) & spec@datasets$has_no_data
  expect_gt(sum(no_data), 0L)
  expect_true(all(is.na(spec@datasets$archive_location_id[no_data])))
  expect_true(all(!is.na(spec@datasets$archive_location_id[!no_data])))
})

test_that("ItemDef and Origin detail are carried", {
  spec <- read_define("define21-sdtm.xml")
  expect_identical(
    sum(!is.na(spec@variables$sas_field_name)),
    nrow(spec@variables)
  )
  # def:Origin/@Source is 2.1-only and was never read before.
  expect_gt(sum(!is.na(spec@variables$source)), 100L)
  # pages is meaningless without the leaf it hangs off, so both arrive together.
  expect_identical(
    sum(!is.na(spec@variables$pages)),
    sum(!is.na(spec@variables$origin_document_id))
  )
})

test_that("NCI controlled-terminology codes are carried at both levels", {
  spec <- read_define("define21-sdtm.xml")
  expect_gt(length(unique(stats::na.omit(spec@codelists$nci_code))), 10L)
  expect_gt(sum(!is.na(spec@codelists$term_nci_code)), 100L)
  # CodeList/@Name and @DataType are schema-required, so a define cannot be
  # written back without them.
  expect_identical(
    sum(!is.na(spec@codelists$name)),
    nrow(spec@codelists)
  )
  expect_identical(
    sum(!is.na(spec@codelists$data_type)),
    nrow(spec@codelists)
  )
})

test_that("each document leaf records the container that owns it", {
  # Read off the container, never guessed from the filename: a leaf referenced
  # only from def:Origin sits in no container at all, so a title regex would
  # invent a def:AnnotatedCRF the source does not have.
  spec <- read_define("define21-sdtm.xml")
  expect_true(all(
    spec@documents$role %in%
      c("annotated_crf", "supplemental", "archive", "other")
  ))
  expect_true("archive" %in% spec@documents$role)
  expect_true("supplemental" %in% spec@documents$role)
})

test_that("the three structural slots are populated from Define-XML", {
  spec <- read_define("define21-sdtm.xml")

  # def:Standards used to collapse to a single scalar, losing which standard
  # each dataset and codelist actually claims.
  expect_identical(nrow(spec@standards), 6L)
  expect_identical(sum(spec@standards$is_primary, na.rm = TRUE), 1L)
  expect_true(all(c("IG", "CT") %in% spec@standards$type))

  # One row per CheckValue: a check value is free text and may contain a
  # comma, so a collapsed encoding would be lossy.
  expect_identical(nrow(spec@where_clauses), 52L)
  expect_identical(
    length(unique(paste(
      spec@where_clauses$where_clause_id,
      spec@where_clauses$check_order
    ))),
    46L
  )
  expect_true(all(!is.na(spec@where_clauses$comparator)))

  # The columns existed before but the reader never filled them.
  expect_identical(nrow(spec@method_expressions), 5L)
  expect_true(all(!is.na(spec@method_expressions$context)))
})

test_that("codelist list-level attributes must agree within a codelist", {
  # They are denormalised across term rows, so nothing about the rectangle
  # stops two rows disagreeing and the writer taking the first.
  consistent <- data.frame(
    codelist_id = c("CL.A", "CL.A"),
    term = c("F", "M"),
    name = c("Sex", "Sex"),
    stringsAsFactors = FALSE
  )
  expect_length(artoo:::.validate_codelist_headers(consistent), 0L)

  drifted <- consistent
  drifted$name <- c("Sex", "SEX")
  issues <- artoo:::.validate_codelist_headers(drifted)
  expect_length(issues, 1L)
  expect_match(issues, "disagrees within codelist CL.A")
})

test_that("an external codelist is read as a dictionary (#p12-P4)", {
  skip_if_not_installed("xml2")
  # It used to be dropped, along with every reference to it, and the writer
  # dropped it too -- so no round trip could see the loss. Now the list
  # becomes a `dictionaries` row and the references to it stand.
  spec <- suppressWarnings(read_spec(test_path(
    "fixtures",
    "define20-sdtm.xml"
  )))
  expect_gt(nrow(spec@dictionaries), 0L)
  expect_true(all(c("dictionary", "version") %in% names(spec@dictionaries)))
  expect_true(any(!is.na(spec@dictionaries$dictionary)))
  # Whatever names one keeps the reference; the two kinds of terminology
  # share the column because a workbook has only one. In this document it
  # is the value-level rows that point at the dictionaries.
  named <- c(spec@variables$codelist_id, spec@values$codelist_id)
  expect_true(any(named %in% spec@dictionaries$dictionary_id))
  # ...and writing it back emits the ExternalCodeList the reference needs,
  # so artoo's own check finds nothing dangling.
  path <- file.path(withr::local_tempdir(), "define.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = "2020-01-01 00:00:00", stylesheet = FALSE)
  ))
  expect_length(
    xml2::xml_find_all(
      xml2::read_xml(path),
      "//*[local-name()='ExternalCodeList']",
      ns = character()
    ),
    nrow(spec@dictionaries)
  )
  expect_false(any(grepl(
    "^define_dangling",
    lint_define(path)@findings$check
  )))
})

test_that("dropping a second def:Origin is reported, not silent (#p4-review)", {
  skip_if_not_installed("xml2")
  # Accumulating into a list from inside an lapply binds a LOCAL copy, and
  # the first version of this warning never fired for exactly that reason.
  src <- file.path(withr::local_tempdir(), "two-origins.xml")
  base <- readLines(
    system.file("extdata", "define-minimal.xml", package = "artoo"),
    warn = FALSE
  )
  hit <- grep("<def:Origin Type=\"Derived\"/>", base, fixed = FALSE)
  expect_length(hit, 1L)
  base[[hit]] <- paste0(base[[hit]], "\n", base[[hit]])
  writeLines(base, src)
  expect_warning(read_spec(src), class = "artoo_warning_spec")
  expect_snapshot(
    spec <- read_spec(src),
    transform = function(x) sub("'.*/(two-origins.xml)'", "'\\1'", x)
  )
})

test_that("a second def:DocumentRef is reported, not silent (#p5-review-4)", {
  skip_if_not_installed("xml2")
  # Verified against the bundled CDISC ADaM example, whose COM.ADQSADAS
  # points at both a program and the analysis data reviewer's guide. The
  # drop is symmetric with the writer, so no round-trip test can see it.
  for (f in c("define21-adam.xml", "define20-adam.xml")) {
    expect_warning(
      read_spec(test_path("fixtures", f)),
      "more than one .*DocumentRef",
      info = f
    )
  }
  # ...and def:AnnotatedCRF / def:SupplementalDoc are CONTAINERS of document
  # references. artoo reads every one of them, so counting their children
  # here fired on nearly every real submission with a claim that was false.
  # Both SDTM examples carry a multi-reference def:SupplementalDoc and lose
  # nothing, so neither may warn.
  for (f in c("define20-sdtm.xml", "define21-sdtm.xml")) {
    warned <- character(0)
    withCallingHandlers(
      read_spec(test_path("fixtures", f)),
      warning = function(w) {
        warned <<- c(warned, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_false(any(grepl("more than one", warned)), info = f)
  }
})
