# cran-comments

## Resubmission

This is a resubmission (version 0.1.1). In response to the reviewer's
feedback:

- Removed the use of `artoo:::` in the documentation. The `set_meta()`
  example no longer reaches an internal function; it now builds the metadata
  through the exported `apply_spec()` and `get_meta()` functions.
- Added references for the implemented formats to the Description field. The
  package has no methods paper, so the specifications it implements are cited
  via URL as the note's `<https:...>` fallback allows: CDISC Dataset-JSON
  (<https://cdisc-org.github.io/DataExchange-DatasetJson/doc/dataset-json1-1.html>)
  and SAS XPORT
  (<https://www.loc.gov/preservation/digital/formats/fdd/fdd000466.shtml>).

## Submission

This is the first submission of artoo to CRAN.

## Test environments

- Local: macOS 26.5.1 (aarch64-apple-darwin20), R 4.5.3 --
  `R CMD check --as-cran`: OK.
- win-builder, R-devel (x86_64-w64-mingw32): 1 NOTE (see below).
- macOS builder, R-release (mac.r-project.org): OK.
- GitHub Actions: Ubuntu (R-devel, R-release, R-oldrel-1), macOS, and
  Windows (R-release): OK.

## R CMD check results

The only NOTE is the standard first-submission NOTE on win-builder:

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Vignesh Thanikachalam <about.vignesh@gmail.com>'

New submission

Possibly misspelled words in DESCRIPTION:
  ADaM CDISC SDTM XPORT XPT losslessly
```

The flagged words are all intentional: ADaM, CDISC, SDTM, XPORT, and XPT are
standard clinical-data-interchange abbreviations, each written in full on
first mention with the abbreviation in parentheses; "losslessly" is the
correct adverb of "lossless".

On the local check machine a different, environmental NOTE can appear
("checking for future file timestamps ... unable to verify current time"),
caused by the check machine having no network access to the time server. It
does not appear on win-builder or on CRAN's build machines.

## Notes for the reviewer

- The package has no methods paper. It implements public data-exchange
  standards (CDISC Dataset-JSON, SAS XPORT), now cited by URL in the
  Description field.
- All examples run under `R CMD check`. Examples and the vignette that
  exercise the optional `nanoparquet`, `readxl`, `writexl`, and `xml2`
  back-ends are guarded with `requireNamespace()`, so the package checks
  cleanly with only its declared `Imports`.
