# test-define-assets.R — the vendored CDISC schema and stylesheet trees.
#
# These assets ship in inst/extdata/ and are read at runtime: validate_define()
# compiles a schema root from there, and the Define-XML writer copies a
# stylesheet next to the user's define.xml. So a missing, corrupted, or
# line-ending-normalised file is a user-facing failure, not a dev inconvenience.
#
# The 4x4 matrix below is the real gate. It proves three things at once: every
# xs:import / xs:redefine chain resolves from the INSTALLED layout (the two
# version trees have different internal shapes and only work if each replicates
# its own source package), each version's root accepts its own examples, and
# each correctly rejects the other version's. The off-diagonal failures are
# free negative controls -- if they ever start passing, a schema root is not
# constraining what we think it is.

skip_if_not_installed("xml2")
skip_if_not_installed("digest")

extdata <- function(...) system.file("extdata", ..., package = "artoo")

# The four official CDISC example documents, used as oracles. They live under
# tests/ rather than inst/ -- they are test material, not runtime assets.
.doc <- function(key) testthat::test_path("fixtures", .docs[[key]])

# Schema-compilation chatter that is not a document error. libxml2 reports a
# repeated namespace import as an "error" on a perfectly valid file, so
# xml_validate() returns TRUE with a non-empty errors attribute.
.informational <- function(e) grepl("Skipping import", e, fixed = TRUE)

# A missing or unreadable schema file. This must never be reported as a
# document problem -- a partial install degrades xml_validate() to
# valid = FALSE, which reads as "your define.xml is broken".
.infrastructure <- function(e) grepl("Failed to locate|failed to load", e)

.roots <- c(
  "define-2.0" = "2.0.0/cdisc-define-2.0/define2-0-0.xsd",
  "arm-2.0" = "2.0.0/cdisc-arm-1.0/arm1-0-0.xsd",
  "define-2.1" = "2.1.0/cdisc-define-2.1/define2-1-0.xsd",
  "arm-2.1" = "2.1.0/cdisc-arm-1.0/arm1-0-0.xsd"
)

.docs <- c(
  "20-sdtm" = "define20-sdtm.xml",
  "20-adam" = "define20-adam.xml",
  "21-sdtm" = "define21-sdtm.xml",
  "21-adam" = "define21-adam.xml"
)

test_that("every vendored asset is present and byte-identical to its pin", {
  manifest <- extdata("MANIFEST.sha256")
  expect_true(nzchar(manifest))

  lines <- readLines(manifest, warn = FALSE)
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  expect_gt(length(lines), 0)

  parts <- strsplit(lines, " ", fixed = TRUE)
  pins <- vapply(parts, `[`, character(1), 1L)
  paths <- vapply(parts, `[`, character(1), 2L)

  got <- vapply(
    paths,
    function(p) {
      f <- extdata(p)
      if (!nzchar(f)) {
        NA_character_
      } else {
        digest::digest(f, algo = "sha256", file = TRUE)
      }
    },
    character(1)
  )

  # Name the offenders rather than reporting a bare count -- a CRLF
  # normalisation breaks many files at once, and the list of paths is the
  # diagnosis while a count is not.
  mismatched <- paths[is.na(got) | got != pins]
  expect_identical(mismatched, character(0))
})

test_that("all four schema roots compile with no infrastructure failures", {
  for (nm in names(.roots)) {
    path <- extdata(.roots[[nm]])
    expect_true(nzchar(path), info = nm)

    schema <- xml2::read_xml(path)
    res <- xml2::xml_validate(xml2::read_xml(.doc("21-sdtm")), schema)
    infra <- Filter(.infrastructure, attr(res, "errors"))
    expect_identical(infra, character(0), info = nm)
  }
})

test_that("the 4x4 schema matrix is exactly the expected diagonal", {
  # Rows are schema roots, columns are the official example documents.
  # TRUE means the document validates against that root.
  expected <- matrix(
    c(
      # 20-sdtm 20-adam 21-sdtm 21-adam
      TRUE,
      TRUE,
      FALSE,
      FALSE, # define-2.0
      TRUE,
      TRUE,
      FALSE,
      FALSE, # arm-2.0
      FALSE,
      FALSE,
      TRUE,
      FALSE, # define-2.1  <- rejects ARM content
      FALSE,
      FALSE,
      TRUE,
      TRUE # arm-2.1     <- superset, accepts both
    ),
    nrow = 4,
    byrow = TRUE,
    dimnames = list(names(.roots), names(.docs))
  )

  got <- expected
  got[] <- NA
  for (r in names(.roots)) {
    schema <- xml2::read_xml(extdata(.roots[[r]]))
    for (d in names(.docs)) {
      res <- xml2::xml_validate(xml2::read_xml(.doc(d)), schema)
      expect_identical(
        Filter(.infrastructure, attr(res, "errors")),
        character(0),
        info = paste(r, d)
      )
      got[r, d] <- as.logical(res)
    }
  }

  expect_identical(got, expected)
})

test_that("the ARM root is a strict superset, so one root per version suffices", {
  # This is why the writer and validate_define() always use the ARM root:
  # validating a document containing arm: content against the define root
  # fails, while the ARM root accepts ARM-free documents too.
  arm21 <- xml2::read_xml(extdata(.roots[["arm-2.1"]]))
  def21 <- xml2::read_xml(extdata(.roots[["define-2.1"]]))
  adam <- xml2::read_xml(.doc("21-adam"))

  expect_true(as.logical(xml2::xml_validate(adam, arm21)))
  expect_false(as.logical(xml2::xml_validate(adam, def21)))

  # ...and the ARM root does not reject a document with no ARM at all.
  sdtm <- xml2::read_xml(.doc("21-sdtm"))
  expect_true(as.logical(xml2::xml_validate(sdtm, arm21)))
})

test_that("the two version trees keep their distinct internal layouts", {
  # 2.0 keeps the W3C schemas inside cdisc-odm-1.3.2/; 2.1 moves them to a
  # sibling core/. Merging or deduplicating the trees breaks every relative
  # xs:import, and the failure surfaces as an unrelated-looking validation
  # error, so assert the shape directly.
  expect_true(nzchar(extdata("2.0.0/cdisc-odm-1.3.2/xlink.xsd")))
  expect_true(nzchar(extdata("2.1.0/core/xlink.xsd")))
  expect_identical(extdata("2.1.0/cdisc-odm-1.3.2/xlink.xsd"), "")

  # The two ARM trees target different def namespaces and are NOT
  # interchangeable: 2.0's is the original ARM v1.0 for Define-XML v2.0.
  arm20 <- readLines(extdata("2.0.0/cdisc-arm-1.0/arm-ns.xsd"), warn = FALSE)
  arm21 <- readLines(extdata("2.1.0/cdisc-arm-1.0/arm-ns.xsd"), warn = FALSE)
  expect_true(any(grepl("ns/def/v2.0", arm20, fixed = TRUE)))
  expect_true(any(grepl("ns/def/v2.1", arm21, fixed = TRUE)))
})

test_that("both CDISC stylesheets ship with their licence notices", {
  for (p in c(
    "2.0.0/cdisc-xsl/define2-0-0.xsl",
    "2.1.0/cdisc-xsl/define2-1.xsl"
  )) {
    f <- extdata(p)
    expect_true(nzchar(f), info = p)
    # The MIT notice is retained inside the stylesheet itself, which is what
    # the licence requires of a redistribution.
    head <- readLines(f, n = 30, warn = FALSE)
    expect_true(any(grepl("MIT License", head, fixed = TRUE)), info = p)
    expect_true(any(grepl("Lex Jansen", head, fixed = TRUE)), info = p)
    expect_true(nzchar(extdata(paste0(p, ".LICENSE.TXT"))), info = p)
  }
})
