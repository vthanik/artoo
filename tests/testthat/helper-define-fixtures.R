# Reading a bundled Define-XML fixture warns that its external codelists were
# dropped -- artoo has no dictionary model yet, and a loss nothing reports is
# worse than one that fails. That warning is asserted once, in
# test-spec_read_define_columns.R; everywhere else it is noise that would bury
# the warnings a test actually cares about.
read_define <- function(name) {
  suppressWarnings(read_spec(testthat::test_path("fixtures", name)))
}
