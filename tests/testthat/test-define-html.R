# The stylesheet, the processing instruction, and the rendered HTML.
#
# A define.xml is not read as XML by the people it is written for. It is read
# through an XSLT stylesheet, and the document names one in a processing
# instruction. Two things follow, and both are tested here: the file the PI
# names must actually be there (Pinnacle 21 raises DD0085 when it is not), and
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
  # Pinnacle 21 rule DD0085. A PI pointing at a stylesheet nobody shipped is
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
  skip_if_not_installed("xslt")
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
  skip_if_not_installed("xslt")
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
  skip_if_not_installed("xslt")
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
  skip_if_not_installed("xslt")
  skip_if_not_installed("callr")
  # An artoo packaging fault, catchable separately from anything wrong with
  # the user's document.
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  suppressWarnings(
    write_spec(read_define("define21-sdtm.xml"), path, created = FROZEN_HTML)
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
  skip_if_not_installed("xslt")
  skip_if_not_installed("callr")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "define.xml")
  suppressWarnings(
    write_spec(read_define("define21-sdtm.xml"), path, created = FROZEN_HTML)
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
