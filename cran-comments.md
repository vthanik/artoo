# cran-comments

## Update

This is a feature update (version 0.1.3) focused on character-encoding
migration (WLATIN1 / Windows-1252 to UTF-8), a routine need for clinical
datasets:

- The writers accept two new `on_invalid` policies: `"translit"` (fold
  typographic punctuation to its exact ASCII form) and `"fold"` (also strip
  accents, following the ICU Latin-ASCII transliterator, pinned as data so
  results are identical across platforms). Characters with no
  standards-backed ASCII form still abort.
- `on_invalid = "replace"` now substitutes one `?` per unrepresentable
  character instead of one per byte.
- New `invalid_encoding` conformance check flags character values whose
  bytes are not valid UTF-8 (a mis-declared source encoding).
- `write_xpt()` warns when a value forces a column wider than its declared
  metadata length (data was already never truncated).
- Additional SAS encoding-name aliases (OEM/DOS code pages) resolve.

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
