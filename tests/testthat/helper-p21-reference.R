# Reference workbooks from the vendor's own tooling, when they are present.
#
# These are licensed material: the Community generator's control fixtures
# and an Enterprise blank template. Neither may be redistributed, so neither
# is tracked, neither ships in the tarball, and every test that wants one
# skips when it is absent. They live in `.local/fixtures/`, which is
# gitignored -- see `.local/docs/spec-workbook-generations.md` section 5.
#
# What they buy: `acrf-control.xlsx` and `define-2.0-acrf-control.xml` are a
# GOLDEN PAIR, one workbook and the define.xml the vendor's own generator
# produces from it, compared node by node by that project's own test. It is
# the most complete real specification available to this project -- 34
# datasets, 414 variables, 121 value-level rows -- and the only evidence
# that artoo's reading of the older workbook generation is right rather
# than merely self-consistent.
p21_reference <- function(name) {
  path <- testthat::test_path("..", "..", ".local", "fixtures", name)
  if (file.exists(path)) normalizePath(path) else ""
}

# skip_if_no_reference("acrf-control.xlsx") at the top of a test.
skip_if_no_reference <- function(name) {
  testthat::skip_if(
    !nzchar(p21_reference(name)),
    paste0("reference fixture not present: ", name)
  )
}

# Is xslt installed, WITHOUT loading it.
#
# `skip_if_not_installed()` calls `requireNamespace()`, which loads the
# package and its DLL -- and holding libxslt beside libxml2's XSD validator
# in one process is what the render subprocess exists to prevent. A test
# that skips unless xslt is present must not be the thing that loads it.
skip_if_no_xslt <- function() {
  testthat::skip_if(
    !nzchar(system.file(package = "xslt")),
    "xslt is not installed"
  )
}
