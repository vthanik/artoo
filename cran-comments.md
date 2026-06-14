# cran-comments

## Submission

This is the first submission of artoo to CRAN.

## Test environments

- Local: macOS 26.5.1 (aarch64-apple-darwin20), R 4.5.3 --
  `R CMD check --as-cran`: OK.
- To run before submission: win-builder (R-release and R-devel) and R-hub
  (Linux, macOS, Windows).

## R CMD check results

0 errors | 0 warnings | 0 notes.

Locally a single NOTE appears:

```
checking for future file timestamps ... NOTE
  unable to verify current time
```

This is an environmental artifact of the check machine's clock-verification
step (no network access to the time server), not a property of the package.
It does not appear on CRAN's build machines.

## Notes for the reviewer

- The DESCRIPTION uses standard clinical-data-interchange abbreviations
  (CDISC, SDTM, ADaM, XPORT / XPT). Each is written in full on first mention,
  with the abbreviation in parentheses.
- The package has no references describing its methods: it implements public
  data-exchange standards (CDISC Dataset-JSON, SAS XPORT) that are cited in
  the function documentation.
- All examples run under `R CMD check`. Examples and the vignette that
  exercise the optional `nanoparquet`, `readxl`, `writexl`, and `xml2`
  back-ends are guarded with `requireNamespace()`, so the package checks
  cleanly with only its declared `Imports`.
