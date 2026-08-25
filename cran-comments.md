# cran-comments

## Update

This is a feature update (version 0.2.0) adding CDISC Define-XML, the
specification document that accompanies a regulatory submission, and two
ways to drive it from what is already on disk:

- `write_spec()` writes Define-XML 2.1 and 2.0 when given a `.xml` path, so
  a specification workbook or a native JSON spec becomes a define.xml in one
  call. The document is schema-validated against the bundled CDISC schemas
  before it reaches its destination, so an invalid one never overwrites a
  good file.
- `read_spec()` reads Define-XML 2.0 and 2.1, including value-level
  metadata, where clauses, external dictionaries, and Analysis Results
  Metadata v1.0.
- New `validate_define()` schema-validates any vendor's define.xml offline;
  new `lint_define()` walks the OID reference graph the schema is blind to
  (an OID is `odm:oidref`, not `xs:ID`, so libxml2 never resolves one).
- New `write_template()` writes a blank specification workbook whose sheets
  and headers are derived from the reader's own maps.
- `write_spec()` accepts `data =` as either a named list of data frames or
  one folder, matching each dataset the spec names to a file called after
  it, and fills blank lengths from the real maximum byte width.
- `members()` gains `format =`, restricting a dataset inventory to named
  formats.
- `html = TRUE` renders the document through its CDISC stylesheet, which
  matters because browsers are removing XSLT support. The render runs in a
  subprocess: libxslt and libxml2's XSD validator share global state, and
  driving both in one session corrupts it.

A new article, "Authoring a specification workbook", documents the
spreadsheet surface sheet by sheet.

The CDISC Define-XML, ODM and ARM schemas and the Define-XML stylesheets
are redistributed byte for byte under CDISC's Terms of Use, with every
notice they carry; the three W3C schemas inside those packages are covered
by the W3C Software License. All copyright holders are named in
`Authors@R`, and `inst/COPYRIGHTS` records each package, its terms, and the
sha256 of every vendored file.

## Test environments

- Local: macOS 26.5.1 (aarch64-apple-darwin20), R 4.5.3 --
  `R CMD check --as-cran` on the release tarball: 0 errors, 0 warnings,
  2 notes, both environmental (this machine's HTML Tidy predates the
  validator; the clock could not be verified offline). Neither appears on
  CRAN's machines.
- win-builder, R-release (R 4.6.1, x86_64-w64-mingw32): 1 note, below.
  Check time 559s, tests 402s.
- win-builder, R-devel (2026-08-24 r90445 ucrt): the same 1 note. Check
  time 595s, tests 430s.
- GitHub Actions: Ubuntu (R-devel, R-release, R-oldrel-1), macOS, and
  Windows (R-release): all green.

## R CMD check results

0 errors | 0 warnings | 1 note.

On win-builder the note is:

    Possibly misspelled words in DESCRIPTION:
      stylesheet (24:28)

"stylesheet" is spelled correctly and is the term the standards use: the
document artoo renders through is named by an `<?xml-stylesheet?>`
processing instruction and its root element is `xsl:stylesheet`.

Seven test blocks that walk the bundled CDISC example corpora carry
`skip_on_cran()`. Each re-confirms a property a narrower test already pins,
and they are the bulk of the Windows check time; the full suite runs on
every platform in CI.

## Reverse dependencies

None: artoo has no reverse dependencies on CRAN.
