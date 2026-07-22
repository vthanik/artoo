# Demo vital signs dataset (SDTM VS)

A 60-row sample of the CDISC pilot SDTM vital signs domain (VS):
repeated measurements per subject across visits, positions, and planned
timepoints.

## Usage

``` r
cdisc_vs
```

## Format

A data frame with 60 rows (`STUDYID`, `USUBJID`, `VSTESTCD`, `VSORRES`,
`VISITNUM`, `VSPOS`, `VSTPTNUM`, ...).

## Source

First 60 rows of the CDISC pilot `sdtm/cdiscpilot01/vs.xpt` from the
PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
