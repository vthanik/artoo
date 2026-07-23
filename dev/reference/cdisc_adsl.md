# Demo subject-level analysis dataset (ADaM ADSL)

A 60-subject sample of the CDISC pilot ADaM subject-level analysis
dataset (ADSL): one row per subject, with treatment, demographic,
baseline, and disposition variables (labels preserved as column
attributes).

## Usage

``` r
cdisc_adsl
```

## Format

A data frame with 60 rows and 48 variables (`STUDYID`, `USUBJID`,
`TRT01P`, `AGE`, `SEX`, `RACE`, `SAFFL`, `TRTSDT`, ...).

## Source

First 60 subjects of the CDISC pilot `adam/cdisc/adsl.xpt` from the
PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
