# cran-comments

## Update

This is a feature update (version 0.2.0) that adds CDISC Define-XML, the
specification document that accompanies a regulatory submission:

- `write_spec()` writes Define-XML 2.1 and 2.0 when given a `.xml` path, so
  a Pinnacle 21 workbook or a native JSON spec becomes a define.xml in one
  call. The document is schema-validated against the bundled CDISC schemas
  before it reaches its destination, so an invalid one never overwrites a
  good file.
- `read_spec()` reads Define-XML 2.0 and 2.1, including value-level
  metadata, where clauses, and Analysis Results Metadata v1.0.
- New `validate_define()` schema-validates any vendor's define.xml offline,
  and new `lint_define()` walks the OID reference graph the schema is blind
  to (an OID is `odm:oidref`, not `xs:ID`, so libxml2 never resolves one).
- New `write_template()` writes a blank Pinnacle 21 workbook whose sheets
  and headers are derived from the reader's own maps.
- `write_spec()` accepts `data =`, filling blank lengths from the real
  maximum byte width and deriving value-level metadata for the standard
  findings shapes.
- `html = TRUE` renders the document through its CDISC stylesheet, which
  matters because browsers are removing XSLT support.

The CDISC Define-XML, ODM and ARM schemas and the Define-XML stylesheets
are redistributed byte for byte under CDISC's Terms of Use, with every
notice they carry; the three W3C schemas inside those packages are covered
by the W3C Software License. All copyright holders are named in
`Authors@R`, and `inst/COPYRIGHTS` records each package, its terms, and the
sha256 of every vendored file.

## Test environments

- Local: macOS 26.5.1 (aarch64-apple-darwin20), R 4.5.3 --
  `R CMD check --as-cran` on the release tarball: OK (NOTEs below).
- win-builder, R-devel (x86_64-w64-mingw32).
- GitHub Actions: Ubuntu (R-devel, R-release, R-oldrel-1), macOS, and
  Windows (R-release): OK.

## R CMD check results

0 errors | 0 warnings | 2 notes.

Both local NOTEs are environmental: "unable to verify current time" (the
check machine has no network route to the time server) and "Skipping
checking HTML validation" (the local HTML Tidy predates the validator).
Neither appears on CRAN's build machines.

The misspelled-words NOTE, when it appears, names domain vocabulary
(CDISC, ADaM, SDTM, ODM, Pinnacle) that is spelled correctly.
