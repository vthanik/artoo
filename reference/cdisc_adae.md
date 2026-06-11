# Demo adverse events analysis dataset (ADaM ADAE)

A 60-row sample of the CDISC pilot ADaM adverse events analysis dataset
(ADAE): one row per reported event, with treatment-emergent flags,
severity, and coding variables (labels preserved as attributes).

## Usage

``` r
cdisc_adae
```

## Format

A data frame with 60 rows (`STUDYID`, `USUBJID`, `AETERM`, `AESEV`,
`TRTEMFL`, `ASTDT`, ...).

## Source

First 60 rows of the CDISC pilot `adam/cdisc/adae.xpt` from the PHUSE
Test Data Factory (`phuse-org/phuse-scripts`).
