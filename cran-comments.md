# cran-comments

## Update

This is a feature update (version 0.2.0) that adds CDISC Define-XML, the
specification document that accompanies a regulatory submission:

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
- `write_spec()` accepts `data =`, filling blank lengths from the real
  maximum byte width and deriving value-level metadata for the standard
  findings shapes.
- `html = TRUE` renders the document through its CDISC stylesheet, which
  matters because browsers are removing XSLT support.

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
  1 note (local HTML Tidy predates the validator; not present on CRAN).
- win-builder, R-release (R 4.6.1, x86_64-w64-mingw32): 1 note, below.
- win-builder, R-devel (x86_64-w64-mingw32).
- GitHub Actions: Ubuntu (R-devel, R-release, R-oldrel-1), macOS, and
  Windows (R-release).

<!-- NOT YET SUBMITTABLE until the R-devel win-builder result and CI are
     in. Delete this comment then, and only then. -->

## R CMD check results

0 errors | 0 warnings | 1 note.

On win-builder the note is:

    Possibly misspelled words in DESCRIPTION:
      stylesheet (24:28)

"stylesheet" is spelled correctly and is the term the standards use: the
document artoo renders through is named by an `<?xml-stylesheet?>`
processing instruction and its root element is `xsl:stylesheet`. Any other
misspelled-words note names domain vocabulary in the same position (CDISC,
ADaM, SDTM, ODM).

The note seen locally is different and environmental: "Skipping checking
HTML validation", because this machine's HTML Tidy predates the validator.
It does not appear on CRAN's build machines.

Windows check time was 467s in total (tests 365s), well inside the limit.

## Reverse dependencies

None: artoo has no reverse dependencies on CRAN.
