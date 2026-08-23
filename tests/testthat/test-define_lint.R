# Tests for define_lint() — reference integrity of a Define-XML document.
#
# The organising idea: every finding this reports is invisible to
# validate_define(). Several tests therefore assert BOTH — the schema says the
# document is fine, and the lint says it is not. That pairing is the whole
# argument for the function existing.
#
# Mutations are text-level surgery on the serialised file, with the anchor's
# uniqueness asserted, so an edit cannot silently land somewhere else and
# certify the wrong thing.

skip_if_not_installed("xml2")

minimal <- function() {
  p <- system.file("extdata", "define-minimal.xml", package = "artoo")
  skip_if(!nzchar(p), "bundled minimal define is unavailable")
  p
}

fixture <- function(name) {
  p <- testthat::test_path("fixtures", name)
  skip_if(!file.exists(p), paste(name, "fixture is unavailable"))
  p
}

# Replace `old` with `new` in a copy of `path`, asserting `old` occurs exactly
# `n` times first. Returns the new path.
edit_xml <- function(path, old, new, n = 1L) {
  txt <- readLines(path, warn = FALSE)
  hits <- sum(vapply(
    txt,
    function(l) lengths(regmatches(l, gregexpr(old, l, fixed = TRUE))),
    integer(1)
  ))
  expect_identical(hits, n)
  out <- file.path(
    withr::local_tempdir(.local_envir = parent.frame()),
    "edited.xml"
  )
  writeLines(gsub(old, new, txt, fixed = TRUE), out)
  out
}

checks_of <- function(report) sort(unique(report@findings$check))

# ---- the gate: clean documents stay clean -------------------------------

test_that("the bundled minimal document has no reference problems", {
  report <- define_lint(minimal())
  expect_s3_class(report, "artoo::artoo_check")
  expect_identical(nrow(report@findings), 0L)
  expect_gt(report@summary$n_definitions, 0L)
  expect_gt(report@summary$n_references, 0L)
})

test_that("both official Define-XML 2.0 examples are clean", {
  for (f in c("define20-sdtm.xml", "define20-adam.xml")) {
    report <- define_lint(fixture(f))
    expect_identical(nrow(report@findings), 0L, info = f)
  }
})

test_that("the official 2.1 examples report only their one real defect", {
  # Not zero: both 2.1 examples define six def:Standard entries and reference
  # only five, so STD.5 is genuinely unreferenced. This is a true positive in
  # CDISC's own published example -- Pinnacle 21's DD0139 flags it too -- so
  # the expectation pins it rather than suppressing it. If this count ever
  # moves, either the fixture changed or the lint gained a false positive.
  for (f in c("define21-sdtm.xml", "define21-adam.xml")) {
    report <- define_lint(fixture(f))
    expect_identical(nrow(report@findings), 1L, info = f)
    expect_identical(report@findings$check, "define_orphan_standard", info = f)
    expect_match(report@findings$message, "STD\\.5", info = f)
  }
})

# ---- dangling references ------------------------------------------------

test_that("a dangling variable reference is caught, though the schema passes", {
  bad <- edit_xml(minimal(), 'ItemOID="IT.DM.SEX"', 'ItemOID="IT.DM.NOPE"')
  expect_true(validate_define(bad)@summary$valid)

  report <- define_lint(bad)
  expect_true("define_dangling_item" %in% checks_of(report))
  expect_identical(
    report@findings$severity[report@findings$check == "define_dangling_item"],
    "error"
  )
  expect_match(
    report@findings$message[report@findings$check == "define_dangling_item"],
    "IT.DM.NOPE"
  )
})

test_that("a dangling codelist reference is caught", {
  bad <- edit_xml(minimal(), 'CodeListOID="CL.SEX"', 'CodeListOID="CL.NOPE"')
  expect_true(validate_define(bad)@summary$valid)
  expect_true("define_dangling_codelist" %in% checks_of(define_lint(bad)))
})

test_that("a dangling comment reference is caught", {
  bad <- edit_xml(
    minimal(),
    'def:CommentOID="COM.SEX"',
    'def:CommentOID="COM.NOPE"'
  )
  expect_true("define_dangling_comment" %in% checks_of(define_lint(bad)))
})

test_that("a dangling standard reference is caught", {
  bad <- edit_xml(
    minimal(),
    'def:StandardOID="STD.1"',
    'def:StandardOID="STD.NOPE"'
  )
  expect_true("define_dangling_standard" %in% checks_of(define_lint(bad)))
})

test_that("a dangling archive location gets its own finding, not a leaf one", {
  # An ItemGroupDef pointing at a missing leaf is a different problem from a
  # DocumentRef doing so -- one loses the dataset file, the other a PDF -- so
  # they carry different condition ids.
  bad <- edit_xml(
    minimal(),
    'def:ArchiveLocationID="LF.DM"',
    'def:ArchiveLocationID="LF.NOPE"'
  )
  found <- checks_of(define_lint(bad))
  expect_true("define_dangling_archive_location" %in% found)
  expect_false("define_dangling_leaf" %in% found)
})

test_that("a dangling value list reference is caught", {
  src <- fixture("define21-sdtm.xml")
  txt <- readLines(src, warn = FALSE)
  hit <- grep("<def:ValueListRef ", txt, fixed = TRUE)[1]
  skip_if(is.na(hit), "fixture carries no def:ValueListRef")
  txt[hit] <- sub('ValueListOID="[^"]*"', 'ValueListOID="VL.NOPE"', txt[hit])
  out <- file.path(withr::local_tempdir(), "vl.xml")
  writeLines(txt, out)

  expect_true("define_dangling_value_list" %in% checks_of(define_lint(out)))
})

test_that("a dangling where clause reference is caught", {
  src <- fixture("define21-sdtm.xml")
  txt <- readLines(src, warn = FALSE)
  hit <- grep("<def:WhereClauseRef ", txt, fixed = TRUE)[1]
  skip_if(is.na(hit), "fixture carries no def:WhereClauseRef")
  txt[hit] <- sub(
    'WhereClauseOID="[^"]*"',
    'WhereClauseOID="WC.NOPE"',
    txt[hit]
  )
  out <- file.path(withr::local_tempdir(), "wc.xml")
  writeLines(txt, out)

  expect_true("define_dangling_where_clause" %in% checks_of(define_lint(out)))
})

test_that("a dangling method reference is caught", {
  src <- fixture("define21-sdtm.xml")
  txt <- readLines(src, warn = FALSE)
  hit <- grep('MethodOID="', txt, fixed = TRUE)[1]
  skip_if(is.na(hit), "fixture carries no MethodOID")
  txt[hit] <- sub('MethodOID="[^"]*"', 'MethodOID="MT.NOPE"', txt[hit])
  out <- file.path(withr::local_tempdir(), "mt.xml")
  writeLines(txt, out)

  expect_true("define_dangling_method" %in% checks_of(define_lint(out)))
})

test_that("a dangling document reference is caught", {
  src <- fixture("define21-sdtm.xml")
  txt <- readLines(src, warn = FALSE)
  hit <- grep("<def:DocumentRef ", txt, fixed = TRUE)[1]
  skip_if(is.na(hit), "fixture carries no def:DocumentRef")
  txt[hit] <- sub('leafID="[^"]*"', 'leafID="LF.NOPE"', txt[hit])
  out <- file.path(withr::local_tempdir(), "lf.xml")
  writeLines(txt, out)

  expect_true("define_dangling_leaf" %in% checks_of(define_lint(out)))
})

# ---- orphan definitions -------------------------------------------------

test_that("an orphaned value list is an ERROR, not a warning", {
  # This is herald bug (a). Deleting the ValueListRef leaves the
  # def:ValueListDef defined but unreachable, so every value-level definition
  # it holds renders nowhere in a reviewer's tool -- and the document still
  # validates. Silent loss of submission metadata, hence error severity.
  src <- fixture("define21-sdtm.xml")
  txt <- readLines(src, warn = FALSE)
  hit <- grep("<def:ValueListRef ", txt, fixed = TRUE)
  skip_if(length(hit) == 0L, "fixture carries no def:ValueListRef")
  out <- file.path(withr::local_tempdir(), "orphan-vl.xml")
  writeLines(txt[-hit[1]], out)

  expect_true(validate_define(out)@summary$valid)

  report <- define_lint(out)
  rows <- report@findings[report@findings$check == "define_orphan_value_list", ]
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$severity, "error")
})

test_that("an orphaned codelist is reported as a warning", {
  bad <- edit_xml(minimal(), '<CodeListRef CodeListOID="CL.SEX"/>', "")
  report <- define_lint(bad)
  rows <- report@findings[report@findings$check == "define_orphan_codelist", ]
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$severity, "warning")
})

test_that("an orphaned comment is reported", {
  bad <- edit_xml(minimal(), ' def:CommentOID="COM.SEX"', "")
  expect_true("define_orphan_comment" %in% checks_of(define_lint(bad)))
})

test_that("an orphaned document leaf is reported", {
  bad <- edit_xml(minimal(), ' def:ArchiveLocationID="LF.DM"', "")
  expect_true("define_orphan_leaf" %in% checks_of(define_lint(bad)))
})

test_that("an orphaned variable is reported", {
  bad <- edit_xml(
    minimal(),
    '<ItemRef ItemOID="IT.DM.SEX" OrderNumber="3" Mandatory="Yes"/>',
    ""
  )
  expect_true("define_orphan_item" %in% checks_of(define_lint(bad)))
})

# ---- the carve-outs that prevent false positives ------------------------

test_that("a dictionary-backed codelist is exempt from the orphan check", {
  # An ExternalCodeList (MedDRA, WHODrug, ISO 3166) names a dictionary rather
  # than enumerating terms, so nothing points at it with a CodeListRef and it
  # is not an orphan. Without this exemption every real AE or CM define
  # reports a spurious finding.
  txt <- readLines(minimal(), warn = FALSE)
  anchor <- grep("</MetaDataVersion>", txt, fixed = TRUE)
  expect_length(anchor, 1L)
  injected <- append(
    txt,
    paste0(
      '      <CodeList OID="CL.MEDDRA" Name="MedDRA" DataType="text">',
      '<ExternalCodeList Dictionary="MedDRA" Version="25.0"/></CodeList>'
    ),
    after = anchor - 1L
  )
  out <- file.path(withr::local_tempdir(), "external.xml")
  writeLines(injected, out)

  report <- define_lint(out)
  expect_identical(report@summary$n_external_codelists, 1L)
  expect_false("define_orphan_codelist" %in% checks_of(report))
})

test_that("a codelist reached through RoleCodeListOID counts as referenced", {
  # It is referenced, just not through CodeListRef. Swapping the reference
  # form must not turn the codelist into an orphan.
  bad <- edit_xml(
    minimal(),
    '<CodeListRef CodeListOID="CL.SEX"/>',
    ""
  )
  txt <- readLines(bad, warn = FALSE)
  hit <- grep('<ItemRef ItemOID="IT.DM.SEX"', txt, fixed = TRUE)
  expect_length(hit, 1L)
  txt[hit] <- sub("/>$", ' RoleCodeListOID="CL.SEX"/>', txt[hit])
  out <- file.path(withr::local_tempdir(), "role.xml")
  writeLines(txt, out)

  expect_false("define_orphan_codelist" %in% checks_of(define_lint(out)))
})

# ---- Origin inheritance, both directions --------------------------------

test_that("a variable with no Origin anywhere is reported", {
  bad <- edit_xml(minimal(), '<def:Origin Type="Derived"/>', "")
  report <- define_lint(bad)
  expect_true("define_missing_origin" %in% checks_of(report))
  expect_match(
    report@findings$message[report@findings$check == "define_missing_origin"],
    "IT.DM.USUBJID"
  )
})

test_that("a parent variable inherits Origin from its value-level items", {
  # define21-sdtm.xml's LBORRES carries no Origin of its own; its value-level
  # items supply one each. Reporting that parent would be a false positive,
  # and it is exactly the mistake the first implementation made.
  report <- define_lint(fixture("define21-sdtm.xml"))
  expect_false("define_missing_origin" %in% checks_of(report))
})

# ---- error paths --------------------------------------------------------

test_that("a non-XML file is refused", {
  bad <- file.path(withr::local_tempdir(), "junk.xml")
  writeLines("not xml <<<", bad)
  expect_error(define_lint(bad), class = "artoo_error_input")
})

test_that("a document with no MetaDataVersion is refused", {
  other <- file.path(withr::local_tempdir(), "no-mdv.xml")
  writeLines("<root><child/></root>", other)
  expect_error(define_lint(other), class = "artoo_error_input")
  expect_snapshot(
    define_lint(other),
    error = TRUE,
    transform = function(x) {
      gsub("'[^']*[/\\\\]([^/\\\\']+\\.xml)'", "'<tmp>/\\1'", x)
    }
  )
})

test_that("a bad path argument is refused", {
  expect_error(define_lint(123), class = "artoo_error_input")
})

test_that("a missing file says so, rather than reporting unparseable XML", {
  expect_error(
    define_lint(file.path(withr::local_tempdir(), "absent.xml")),
    class = "artoo_error_input"
  )
})

test_that("a MetaDataVersion with no definitions or references is handled", {
  # The degenerate document: structurally a define, semantically empty. Every
  # collector must return its typed empty shape rather than failing.
  bare <- file.path(withr::local_tempdir(), "bare.xml")
  writeLines(
    paste0(
      '<ODM xmlns="http://www.cdisc.org/ns/odm/v1.3" ',
      'xmlns:def="http://www.cdisc.org/ns/def/v2.1">',
      "<Study><MetaDataVersion/></Study></ODM>"
    ),
    bare
  )
  report <- define_lint(bare)
  expect_identical(nrow(report@findings), 0L)
  expect_identical(report@summary$n_definitions, 0L)
  expect_identical(report@summary$n_references, 0L)
  expect_identical(report@summary$n_external_codelists, 0L)
})

test_that("the printed reports name what they actually checked", {
  # A Define-XML report must not render the spec-check header: "Datasets: 0
  # Variables: 0" is false for a define document, and the fields that matter
  # (version, verdict, reference counts) would never be shown.
  expect_snapshot(print(validate_define(minimal())))
  expect_snapshot(print(define_lint(minimal())))
})

test_that("the lint report shows the external-codelist exemption count", {
  txt <- readLines(minimal(), warn = FALSE)
  anchor <- grep("</MetaDataVersion>", txt, fixed = TRUE)
  injected <- append(
    txt,
    paste0(
      '      <CodeList OID="CL.MEDDRA" Name="MedDRA" DataType="text">',
      '<ExternalCodeList Dictionary="MedDRA" Version="25.0"/></CodeList>'
    ),
    after = anchor - 1L
  )
  out <- file.path(withr::local_tempdir(), "external-report.xml")
  writeLines(injected, out)
  expect_output(print(define_lint(out)), "External codelists")
})
