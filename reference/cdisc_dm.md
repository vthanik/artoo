# Demo demographics dataset (SDTM DM)

A 60-subject sample of the CDISC pilot SDTM demographics domain (DM):
one row per subject, with the standard DM variables (labels preserved as
attributes).

## Usage

``` r
cdisc_dm
```

## Format

A data frame with 60 rows and 25 variables (`STUDYID`, `DOMAIN`,
`USUBJID`, `AGE`, `SEX`, `RACE`, `ARM`, `COUNTRY`, ...).

## Source

First 60 subjects of the CDISC pilot `sdtm/TDF_SDTM_v1.0/dm.xpt` from
the PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
