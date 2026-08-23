# Tests for validate_define() — Define-XML schema validation.
#
# The most important tests here are the NEGATIVE ones, and specifically the
# two that assert schema validation stays GREEN. Schema validation is blind to
# reference integrity, and that blindness is the entire reason define_lint()
# exists. Pinning it here means nobody can later mistake a green schema run for
# a sound document.
#
# Mutations are text-level surgery on the serialised file with a
# verified-unique anchor, never xml2 node surgery: xml2::xml_ns() binds the ODM
# default namespace as "d1", so hand-written XPaths silently match nothing and
# a mutation that never applied reports a false green.

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

# Rewrite `file` with `old` replaced by `new`, asserting the anchor is unique
# so the edit cannot silently land somewhere else.
# Error messages interpolate the document path, and a tempfile path changes
# every run. Scrub it so snapshots pin the MESSAGE rather than the filesystem.
scrub_tmp <- function(x) {
  gsub("'[^']*[/\\\\]([^/\\\\']+\\.xml)'", "'<tmp>/\\1'", x)
}

# A temp file with a FIXED, meaningful basename, so a snapshot that
# interpolates the path stays stable across runs and still reads well.
named_tempfile <- function(name) {
  file.path(withr::local_tempdir(.local_envir = parent.frame()), name)
}

mutate_xml <- function(path, old, new, expect_n = 1L) {
  txt <- readLines(path, warn = FALSE)
  hits <- sum(vapply(
    txt,
    function(l) {
      lengths(regmatches(l, gregexpr(old, l, fixed = TRUE)))
    },
    integer(1)
  ))
  expect_identical(hits, expect_n)
  out <- tempfile(fileext = ".xml")
  writeLines(sub(old, new, txt, fixed = TRUE), out)
  out
}

# ---- happy path ---------------------------------------------------------

test_that("the bundled minimal document is valid Define-XML 2.1", {
  report <- validate_define(minimal())
  expect_s3_class(report, "artoo::artoo_check")
  expect_identical(nrow(report@findings), 0L)
  expect_true(report@summary$valid)
  expect_identical(report@summary$define_version, "2.1")
})

test_that("all four official CDISC examples validate, version auto-detected", {
  cases <- list(
    c("define20-sdtm.xml", "2.0"),
    c("define20-adam.xml", "2.0"),
    c("define21-sdtm.xml", "2.1"),
    c("define21-adam.xml", "2.1")
  )
  for (case in cases) {
    report <- validate_define(fixture(case[[1]]))
    expect_identical(report@summary$define_version, case[[2]], info = case[[1]])
    expect_identical(nrow(report@findings), 0L, info = case[[1]])
    expect_true(report@summary$valid, info = case[[1]])
  }
})

test_that("an ARM-bearing document validates, because the ARM root is used", {
  # define21-adam.xml carries arm: content and would FAIL against the define
  # root. Validating it cleanly is the observable consequence of always
  # choosing the ARM root, so this test breaks if that choice is reverted.
  report <- validate_define(fixture("define21-adam.xml"))
  expect_true(report@summary$valid)
})

# ---- what the schema DOES catch ----------------------------------------

test_that("schema validation catches an attribute outside its enumeration", {
  bad <- mutate_xml(minimal(), 'Repeating="No"', 'Repeating="Maybe"')
  report <- validate_define(bad)
  expect_false(report@summary$valid)
  expect_gt(nrow(report@findings), 0L)
  expect_identical(unique(report@findings$check), "define_schema_invalid")
  expect_identical(unique(report@findings$severity), "error")
  expect_identical(unique(report@findings$dimension), "schema")
  expect_match(report@findings$message[1], "Repeating")
})

test_that("schema validation catches an invalid DataType", {
  bad <- mutate_xml(
    minimal(),
    'DataType="text" Length="20"',
    'DataType="bogus" Length="20"'
  )
  report <- validate_define(bad)
  expect_false(report@summary$valid)
  expect_match(paste(report@findings$message, collapse = " "), "DataType")
})

test_that("schema validation catches a missing required attribute", {
  bad <- mutate_xml(
    minimal(),
    ' Name="SEX" DataType="text"',
    ' DataType="text"'
  )
  report <- validate_define(bad)
  expect_false(report@summary$valid)
  expect_gt(nrow(report@findings), 0L)
})

test_that("schema validation catches def:Class emitted out of sequence", {
  # This is the one herald bug the XSD can see: def:Class must follow every
  # ItemRef. Moving it ahead of them violates the xs:sequence.
  txt <- readLines(minimal(), warn = FALSE)
  cls <- grep('<def:Class Name="SPECIAL PURPOSE"/>', txt, fixed = TRUE)
  first_ref <- grep("<ItemRef ItemOID=", txt, fixed = TRUE)[1]
  expect_length(cls, 1L)
  moved <- append(txt[-cls], txt[cls], after = first_ref - 1L)
  out <- tempfile(fileext = ".xml")
  writeLines(moved, out)

  report <- validate_define(out)
  expect_false(report@summary$valid)
})

# ---- what the schema is BLIND to (the reason define_lint() exists) ------

test_that("schema validation is BLIND to a removed def:ValueListRef", {
  # Deleting the ValueListRef orphans its def:ValueListDef: nothing points at
  # it any more, so no value-level metadata renders in any reviewer tool. The
  # document still validates. This is herald bug (a), and it is why a schema
  # gate cannot be the only defence.
  src <- fixture("define21-sdtm.xml")
  txt <- readLines(src, warn = FALSE)
  hit <- grep("<def:ValueListRef ", txt, fixed = TRUE)
  # Assert the anchor EXISTS rather than skipping: a fixture re-vendor that
  # renamed the element would otherwise turn this into a silent skip, and a
  # test that quietly stops running is worse than one that fails.
  expect_gt(length(hit), 0L)

  target <- sub('.*ValueListOID="([^"]*)".*', "\\1", txt[hit[1]])
  out <- tempfile(fileext = ".xml")
  writeLines(txt[-hit[1]], out)

  # Assert the edit LANDED: the value list is now referenced by nothing.
  after <- readLines(out, warn = FALSE)
  expect_false(any(grepl(
    paste0('ValueListOID="', target, '"'),
    after,
    fixed = TRUE
  )))
  expect_true(any(grepl(
    paste0('ValueListDef OID="', target, '"'),
    after,
    fixed = TRUE
  )))

  report <- validate_define(out)
  expect_true(report@summary$valid)
  expect_identical(nrow(report@findings), 0L)
})

test_that("schema validation is BLIND to a dangling ItemRef/@ItemOID", {
  # Point an ItemRef at an ItemOID no ItemDef defines. Referential integrity
  # is not expressible in XML Schema, so this passes cleanly. This is herald
  # bug (b).
  src <- fixture("define21-sdtm.xml")
  txt <- readLines(src, warn = FALSE)
  hit <- grep('<ItemRef ItemOID="', txt, fixed = TRUE)[1]
  expect_false(is.na(hit))

  before <- txt[hit]
  txt[hit] <- sub('ItemOID="[^"]*"', 'ItemOID="IT.NOT.A.REAL.ITEM"', txt[hit])
  # Assert the substitution actually changed the line, and that the OID it
  # now names is defined nowhere. Without this a no-op sub() would leave the
  # test asserting that an UNMODIFIED document validates, which proves
  # nothing about the blindness it claims to pin.
  expect_false(identical(before, txt[hit]))
  expect_false(any(grepl(
    'ItemDef OID="IT.NOT.A.REAL.ITEM"',
    txt,
    fixed = TRUE
  )))

  out <- tempfile(fileext = ".xml")
  writeLines(txt, out)

  report <- validate_define(out)
  expect_true(report@summary$valid)
  expect_identical(nrow(report@findings), 0L)
})

# ---- version handling ---------------------------------------------------

test_that("an explicit version overrides namespace detection", {
  # Asserting the wrong version turns a silently-passing file into findings,
  # which is how you confirm a document really is the version it claims.
  report <- validate_define(minimal(), version = "2.0")
  expect_identical(report@summary$define_version, "2.0")
  expect_false(report@summary$valid)
})

test_that("an unknown version argument is refused", {
  expect_error(
    validate_define(minimal(), version = "3.0"),
    class = "artoo_error_input"
  )
  expect_snapshot(
    validate_define(minimal(), version = "3.0"),
    error = TRUE,
    transform = scrub_tmp
  )
})

# ---- error paths --------------------------------------------------------

test_that("a non-XML file is refused", {
  bad <- tempfile(fileext = ".xml")
  writeLines("this is not xml at all <<<", bad)
  expect_error(validate_define(bad), class = "artoo_error_input")
})

test_that("a document with no CDISC def namespace is refused with guidance", {
  other <- named_tempfile("not-define.xml")
  writeLines("<root><child/></root>", other)
  expect_error(validate_define(other), class = "artoo_error_input")
  expect_snapshot(validate_define(other), error = TRUE, transform = scrub_tmp)
})

test_that("a Define-XML v1.0 document is refused by name", {
  v1 <- named_tempfile("define-v1.xml")
  writeLines(
    paste0(
      '<ODM xmlns="http://www.cdisc.org/ns/odm/v1.2" ',
      'xmlns:def="http://www.cdisc.org/ns/def/v1.0"><Study/></ODM>'
    ),
    v1
  )
  expect_error(validate_define(v1), class = "artoo_error_input")
  expect_snapshot(validate_define(v1), error = TRUE, transform = scrub_tmp)
})

test_that("a bad path argument is refused before any parsing", {
  expect_error(validate_define(123), class = "artoo_error_input")
  expect_error(validate_define(c("a", "b")), class = "artoo_error_input")
})

# ---- install integrity --------------------------------------------------

test_that("an incomplete schema install is reported as an install fault", {
  # A partial install degrades xml_validate() to valid = FALSE, which a user
  # reads as "my define.xml is broken". It must surface as its own condition
  # kind instead, so it is catchable separately and says whose fault it is.
  real <- .artoo_extdata
  testthat::local_mocked_bindings(
    .artoo_extdata = function(...) {
      p <- real(...)
      # Hide one file the 2.1 chain needs.
      if (any(grepl("core/xlink.xsd", c(...), fixed = TRUE))) "" else p
    }
  )
  expect_error(validate_define(minimal()), class = "artoo_error_install")
  expect_snapshot(
    validate_define(minimal()),
    error = TRUE,
    transform = scrub_tmp
  )
})

test_that("a missing schema root is reported as an install fault", {
  testthat::local_mocked_bindings(.artoo_extdata = function(...) "")
  expect_error(validate_define(minimal()), class = "artoo_error_install")
})

test_that("a broken schema chain is reported as an install fault, not a document fault", {
  # The manifest pre-flight normally catches a partial install. When it is
  # itself absent, the failure surfaces later, as libxml2 failing to load a
  # nested import. That path must ALSO be an install error: the user's
  # document is fine, and reporting it as invalid would send them hunting a
  # defect that is not there.
  #
  # Serve the schema tree from a temp copy with one import removed. The
  # installed package is never touched.
  tmp <- withr::local_tempdir()
  file.copy(
    system.file("extdata", "2.1.0", package = "artoo"),
    tmp,
    recursive = TRUE
  )
  unlink(file.path(tmp, "2.1.0", "core", "xlink.xsd"))

  testthat::local_mocked_bindings(
    .artoo_extdata = function(...) {
      rel <- file.path(...)
      # No manifest: forces the failure past the pre-flight.
      if (identical(rel, "MANIFEST.sha256")) {
        return("")
      }
      file.path(tmp, rel)
    }
  )

  expect_error(validate_define(minimal()), class = "artoo_error_install")
})

test_that("a missing manifest skips the pre-flight without failing", {
  # The manifest is a convenience, not a requirement: an install that lacks it
  # should still validate rather than refuse to work.
  real <- .artoo_extdata
  testthat::local_mocked_bindings(
    .artoo_extdata = function(...) {
      if (identical(file.path(...), "MANIFEST.sha256")) "" else real(...)
    }
  )
  report <- validate_define(minimal())
  expect_true(report@summary$valid)
})

test_that("a missing file says so, rather than reporting unparseable XML", {
  expect_error(
    validate_define(file.path(withr::local_tempdir(), "absent.xml")),
    class = "artoo_error_input"
  )
})
