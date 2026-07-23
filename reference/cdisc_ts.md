# Demo trial summary dataset (SDTM TS)

The CDISC pilot SDTM trial summary domain (TS): one row per trial
characteristic (33 rows in the pilot), the study-design parameters a
submission carries.

## Usage

``` r
cdisc_ts
```

## Format

A data frame with 33 rows (`STUDYID`, `TSPARMCD`, `TSPARM`, `TSVAL`,
...).

## Source

The CDISC pilot `sdtm/cdiscpilot01/ts.xpt` from the PHUSE Test Data
Factory (`phuse-org/phuse-scripts`).
