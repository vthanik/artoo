# The stylesheet, the processing instruction, and the rendered HTML.
#
# A define.xml is not read as XML by the people it is written for. It is read
# through an XSLT stylesheet, and the document names one in a processing
# instruction. Two things follow, and both are tested here: the file the PI
# names must actually be there (Pinnacle 21 raises the stylesheet-exists rule when it is not), and
# the rendering must not depend on a browser -- Chrome removes XSLT support in
# Chrome 158, on 2026-11-17.

FROZEN_HTML <- "2020-01-01 00:00:00"

html_case <- function(fixture, version) {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- file.path(dir, "define.xml")
  suppressWarnings(
    write_spec(
      read_define(fixture),
      path,
      version = version,
      created = FROZEN_HTML
    )
  )
  path
}

test_that("the processing instruction names a file that is actually there", {
  skip_if_not_installed("xml2")
  # Pinnacle 21 rule the stylesheet-exists rule. A PI pointing at a stylesheet nobody shipped is
  # the commonest way a define.xml arrives unrenderable.
  for (version in c("2.0", "2.1")) {
    path <- html_case("define21-sdtm.xml", version)
    pi <- readLines(path, n = 2L)[[2]]
    expect_match(pi, "^<\\?xml-stylesheet ")
    href <- sub('.*href="([^"]+)".*', "\\1", pi)
    expect_true(nzchar(href), info = version)
    expect_true(file.exists(file.path(dirname(path), href)), info = version)
  }
})

test_that("a stylesheet already beside the output is never overwritten", {
  skip_if_not_installed("xml2")
  # A sponsor who has customised the rendering keeps it. The copy exists only
  # so the processing instruction resolves to something.
  dir <- withr::local_tempdir()
  sheet <- file.path(dir, "define2-1.xsl")
  writeLines("<!-- a sponsor's own stylesheet -->", sheet)
  suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      file.path(dir, "define.xml"),
      created = FROZEN_HTML
    )
  )
  expect_identical(
    readLines(sheet, warn = FALSE),
    "<!-- a sponsor's own stylesheet -->"
  )
})

test_that("html = TRUE renders the document through its own stylesheet", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  # Deliberately NOT skip_on_cran(): this is the only test that exercises the
  # renderer, and skipping it there would leave the whole path uncovered by
  # the coverage run too, which is how it would rot.
  for (version in c("2.0", "2.1")) {
    dir <- withr::local_tempdir()
    path <- file.path(dir, "define.xml")
    suppressWarnings(
      write_spec(
        read_define("define21-sdtm.xml"),
        path,
        version = version,
        created = FROZEN_HTML,
        html = TRUE
      )
    )
    rendered <- file.path(dir, "define.html")
    expect_true(file.exists(rendered), info = version)
    text <- paste(readLines(rendered, warn = FALSE), collapse = "\n")
    # It is the study's own metadata, not an empty shell: the stylesheet puts
    # the study name in the title and the datasets in the body.
    expect_match(text, "CDISC01_1", info = version)
    expect_match(text, "VSORRES", info = version)
    expect_gt(nchar(text), 50000L)
  }
})

test_that("html = <path> renders to that path", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  dir <- withr::local_tempdir()
  elsewhere <- file.path(dir, "review", "rendering.html")
  dir.create(dirname(elsewhere))
  suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      file.path(dir, "define.xml"),
      created = FROZEN_HTML,
      html = elsewhere
    )
  )
  expect_true(file.exists(elsewhere))
  expect_false(file.exists(file.path(dir, "define.html")))
})

test_that("html = TRUE without xslt names the package rather than skipping", {
  skip_if_not_installed("xml2")
  # Silently writing no HTML when it was asked for is the failure mode this
  # guards: the user finds out when a reviewer cannot open the file.
  # Pretend it is absent, in both halves. The availability check
  # deliberately does NOT use `requireNamespace()` -- that would load
  # libxslt into this process, the very thing the render subprocess exists
  # to prevent -- so the absence has to be faked at the check, and then
  # `check_installed()` has to react to it as it would in reality.
  testthat::local_mocked_bindings(.dx_have_xslt = function() FALSE)
  testthat::local_mocked_bindings(
    check_installed = function(pkg, ...) {
      if ("xslt" %in% pkg) {
        stop("xslt is not installed")
      }
      invisible(NULL)
    },
    .package = "rlang"
  )
  dir <- withr::local_tempdir()
  expect_error(
    write_spec(
      read_define("define21-sdtm.xml"),
      file.path(dir, "define.xml"),
      created = FROZEN_HTML,
      html = TRUE
    ),
    "xslt"
  )
})

test_that("rendering does not destabilise the session (#p8)", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  skip_on_cran()
  # libxslt and libxml2's XSD validator share global state, and driving both
  # in one process corrupts it: after the schema gate has run, rendering left
  # reading ANY XML liable to segfault -- nine runs in ten over the four
  # bundled examples. The render is exiled to its own process for that
  # reason, so reading XML after one must be safe.
  dir <- withr::local_tempdir()
  for (fixture in c("define20-sdtm.xml", "define21-adam.xml")) {
    path <- file.path(dir, sub("[.]xml$", "-out.xml", fixture))
    suppressWarnings(
      write_spec(read_define(fixture), path, created = FROZEN_HTML, html = TRUE)
    )
    expect_true(file.exists(sub("[.]xml$", ".html", path)))
    # The read that used to crash.
    expect_s3_class(xml2::read_xml(path), "xml_document")
    expect_true(is_artoo_spec(read_define_path(path)))
  }
})

test_that("stylesheet = FALSE writes neither a PI nor a stylesheet", {
  skip_if_not_installed("xml2")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      path,
      created = FROZEN_HTML,
      stylesheet = FALSE
    )
  )
  expect_false(any(grepl("xml-stylesheet", readLines(path, n = 3L))))
  expect_identical(list.files(dir), "define.xml")
})

test_that("a missing bundled stylesheet is an install error, not a render error", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  # An artoo packaging fault, catchable separately from anything wrong with
  # the user's document.
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  # stylesheet = FALSE so none is copied beside the output: the renderer
  # prefers a sheet sitting next to the document, and would find that one.
  suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      path,
      created = FROZEN_HTML,
      stylesheet = FALSE
    )
  )
  testthat::local_mocked_bindings(.artoo_extdata = function(...) "")
  expect_error(
    artoo:::.dx_render_html(path, TRUE, artoo:::.define_profile("2.1")),
    class = "artoo_error_install"
  )
  expect_snapshot(
    artoo:::.dx_render_html(path, TRUE, artoo:::.define_profile("2.1")),
    error = TRUE
  )
})

test_that("a stylesheet that cannot render says so as a codec error", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      path,
      created = FROZEN_HTML,
      stylesheet = FALSE
    )
  )
  # Point the renderer at something that is not a stylesheet.
  broken <- file.path(dir, "broken.xsl")
  writeLines("<not-a-stylesheet/>", broken)
  testthat::local_mocked_bindings(.artoo_extdata = function(...) broken)
  expect_error(
    artoo:::.dx_render_html(path, TRUE, artoo:::.define_profile("2.1")),
    class = "artoo_error_codec"
  )
  # ...and the failed render leaves no half-written HTML behind.
  expect_false(file.exists(file.path(dir, "define.html")))
})

test_that("the stylesheet the document names is the one it renders through", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  # Keeping a sponsor's stylesheet and then rendering through the bundled one
  # would give a browser and artoo two different renderings of one document
  # -- in exactly the case the keep-it rule exists for.
  dir <- withr::local_tempdir()
  writeLines(
    c(
      "<?xml version=\"1.0\"?>",
      "<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\">",
      "<xsl:template match=\"/\"><html><body>SPONSOR RENDERING</body></html></xsl:template>",
      "</xsl:stylesheet>"
    ),
    file.path(dir, "define2-1.xsl")
  )
  suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      file.path(dir, "define.xml"),
      created = FROZEN_HTML,
      html = TRUE
    )
  )
  expect_match(
    paste(
      readLines(file.path(dir, "define.html"), warn = FALSE),
      collapse = ""
    ),
    "SPONSOR RENDERING"
  )
})

test_that("rendered text is not glued together by whitespace stripping (#p8-review-1)", {
  # Gated on CRAN: a breadth loop over the bundled CDISC corpora, which is
  # where the Windows check time goes. It runs in full on CI, on every
  # platform, so the coverage is not lost -- only CRAN's clock is spared.
  skip_on_cran()
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  # xml2::read_xml() strips whitespace-only text nodes by default, and the
  # stylesheets take string-values that span them -- so a method description
  # rendered as "...and SUBJIDcatx(...)" with the space gone. A derivation
  # silently altered in the reviewer-facing deliverable.
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  suppressWarnings(
    write_spec(
      read_define("define20-sdtm.xml"),
      path,
      created = FROZEN_HTML,
      html = TRUE
    )
  )
  rendered <- paste(
    readLines(file.path(dir, "define.html"), warn = FALSE),
    collapse = "\n"
  )
  expect_false(grepl("SUBJIDcatx", rendered, fixed = TRUE))
  expect_match(rendered, "catx", fixed = TRUE)
})

test_that("a renamed stylesheet is the one rendered through (#p10-review-m1)", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  # `stylesheet = "acme.xsl"` names acme.xsl in the processing instruction
  # and leaves the file to the sponsor. Rendering through the bundled sheet
  # anyway would hand a browser and artoo two different renderings of one
  # document -- the same defect the keep-a-sponsor-sheet rule exists for,
  # reached by a different door.
  dir <- withr::local_tempdir()
  writeLines(
    c(
      "<?xml version=\"1.0\"?>",
      "<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\">",
      "<xsl:template match=\"/\"><html><body>ACME RENDERING</body></html></xsl:template>",
      "</xsl:stylesheet>"
    ),
    file.path(dir, "acme.xsl")
  )
  suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      file.path(dir, "define.xml"),
      created = FROZEN_HTML,
      stylesheet = "acme.xsl",
      html = TRUE
    )
  )
  expect_match(
    paste(
      readLines(file.path(dir, "define.html"), warn = FALSE),
      collapse = ""
    ),
    "ACME RENDERING"
  )
})

test_that("a malformed document is a render error, not partial HTML (#p10-review-m2)", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  # What this pins: a document that will not parse is a codec error and
  # leaves no half-written HTML behind. It is NOT a probe of the options
  # change -- measured on xml2 1.6.0, `RECOVER` + `NOERROR` also throws on a
  # truncated document and on a tag mismatch, so the renderer asking for no
  # options at all is a no-op for malformed input on this stack. The change
  # stands on not asking libxml2 for error suppression we do not want, and
  # this test would have been green before it.
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      path,
      created = FROZEN_HTML,
      stylesheet = FALSE
    )
  )
  lines <- readLines(path, warn = FALSE)
  writeLines(head(lines, length(lines) %/% 2L), path)
  expect_error(
    artoo:::.dx_render_html(path, TRUE, artoo:::.define_profile("2.1")),
    class = "artoo_error_codec"
  )
  expect_false(file.exists(file.path(dir, "define.html")))
})

test_that("a PI naming an absent stylesheet is not rendered in silence (#p11-review)", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  # `stylesheet = "acme.xsl"` names a file the sponsor supplies. Before they
  # do, artoo can only render through the bundled sheet -- which is the same
  # browser-and-artoo divergence the href lookup exists to prevent, reached
  # from the other side, so it says so.
  dir <- withr::local_tempdir()
  expect_warning(
    suppressMessages(
      write_spec(
        read_define("define21-sdtm.xml"),
        file.path(dir, "define.xml"),
        created = FROZEN_HTML,
        stylesheet = "acme.xsl",
        html = TRUE
      )
    ),
    class = "artoo_warning_define"
  )
  expect_true(file.exists(file.path(dir, "define.html")))
})

test_that("rendering never loads libxslt into this process (#p12-ci)", {
  skip_if_not_installed("xml2")
  skip_if_no_xslt()
  skip_if_not_installed("callr")
  # The whole reason the render runs in a subprocess is that libxslt and
  # libxml2's XSD validator share global state: with both resident, reading
  # any XML afterwards can abort the session outright -- "Start tag
  # expected" and a core dump, not an R error a caller could catch.
  #
  # That isolation was defeated for a while by the availability check
  # itself. `rlang::check_installed()` calls `requireNamespace()`, which
  # loads the package and its DLL, so the parent held both libraries before
  # the subprocess ever started. macOS tolerated the pair; every Linux and
  # Windows runner aborted, which is why only CI saw it.
  #
  # This asserts the property directly, because the symptom is a crash --
  # a crashed process cannot report its own failure, so no ordinary test
  # can catch the regression.
  skip_if(
    "xslt" %in% loadedNamespaces(),
    "xslt already loaded by something else in this session"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  suppressMessages(suppressWarnings(
    write_spec(
      read_define("define21-sdtm.xml"),
      path,
      created = FROZEN_HTML,
      html = TRUE
    )
  ))
  expect_true(file.exists(file.path(dir, "define.html")))
  expect_false("xslt" %in% loadedNamespaces())
  expect_false("xslt" %in% names(getLoadedDLLs()))
  # ...and the thing the crash actually broke still works.
  expect_s3_class(xml2::read_xml(path), "xml_document")
  expect_true(validate_define(path)@summary$valid)
})
