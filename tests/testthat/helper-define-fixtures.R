# Reading a bundled Define-XML fixture warns: each carries `Alias` elements
# whose context artoo does not model (the SDTM one has 18 naming "Sponsor"),
# and a loss nothing reports is worse than one that fails. That warning is
# asserted in test-spec_read_define.R; everywhere else it is noise that would
# bury the warnings a test actually cares about.
#
# It used to say external codelists were dropped because artoo had no
# dictionary model. It has one -- the same fixture now reads a dictionary
# row -- so that reason described a limitation that no longer exists, over a
# warning about something else.
# Memoised. The bundled defines are read ~40 times across the suite and are
# immutable on disk, so re-parsing them is the single largest cost in the
# check: read_spec() is 37% of the CRAN-mode runtime. Specs are value objects
# (S7 properties are immutable and every transform returns a new object), so
# handing the same one to two tests cannot let one leak into the other.
.define_cache <- new.env(parent = emptyenv())

read_define <- function(name) {
  hit <- .define_cache[[name]]
  if (is.null(hit)) {
    hit <- suppressWarnings(read_spec(testthat::test_path("fixtures", name)))
    .define_cache[[name]] <- hit
  }
  hit
}

# Same, for a file written during a test rather than a bundled fixture.
read_define_path <- function(path) suppressWarnings(read_spec(path))
