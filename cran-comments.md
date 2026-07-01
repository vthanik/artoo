# cran-comments

## Update

This is an update (version 0.1.2) that fixes the check failure reported on
the noLD (no long double) flavor for the current CRAN version 0.1.1.

One test asserted a bit-exact round-trip of a `decimal` column through its
shortest decimal-string form. That guarantee holds only when the platform's
C library string/double conversions are exact inverses, which is not the case
on a noLD build, so `1/3` read back one ULP off. The test now skips on
platforms without long double, guarded on `capabilities("long.double")`; the
codec is unchanged (it already writes the best round-trip string the platform
allows). No user-facing behaviour changes.

## Test environments

- Local: macOS 26.5.1 (aarch64-apple-darwin20), R 4.5.3 --
  `R CMD check --as-cran`: OK (1 environmental NOTE, see below).
- win-builder, R-devel (x86_64-w64-mingw32).
- GitHub Actions: Ubuntu (R-devel, R-release, R-oldrel-1), macOS, and
  Windows (R-release): OK.

## R CMD check results

0 errors | 0 warnings | 1 note.

On the local check machine the only NOTE is environmental
("checking for future file timestamps ... unable to verify current time"),
caused by the check machine having no network access to the time server. It
does not appear on CRAN's build machines.

## Notes for the reviewer

- The change is confined to a single test guard plus the version and NEWS
  bumps. No exported function, argument, or documented behaviour changed.
