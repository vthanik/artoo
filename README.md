

<!-- README.md is generated from README.qmd. Please edit that file -->

# artoo <a href="https://vthanik.github.io/artoo/"><img src="man/figures/logo.png" align="right" height="139" alt="artoo website" /></a>

<div id="pkg-badges">

<!-- badges: start -->

[![R-CMD-check](https://github.com/vthanik/artoo/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/vthanik/artoo/actions/workflows/R-CMD-check.yaml) [![Codecov test coverage](https://codecov.io/gh/vthanik/artoo/graph/badge.svg)](https://app.codecov.io/gh/vthanik/artoo) [![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active) <!-- badges: end -->

</div>

**artoo** is a lightweight, lossless, CDISC-native reader and writer for clinical-trial datasets. It moves data between **SAS XPORT (XPT)**, **CDISC Dataset-JSON v1.1**, **NDJSON**, **Apache Parquet**, and **RDS** through one canonical metadata model, so converting between any two is lossless *by construction* — not by best effort.

## Installation

``` r
# install.packages("pak")
pak::pak("vthanik/artoo")
```

## Quick start

A spec describes the dataset; `apply_spec()` conforms a raw frame to it; the writers carry every piece of metadata to disk — one pipeable chain:

``` r
library(artoo)

# Coerce, order, sort, stamp metadata, then write. The writers return their
# input invisibly, so one conformed frame fans out to every deliverable.
path <- tempfile(fileext = ".xpt")
adsl <- cdisc_adsl |>
  apply_spec(adam_spec, "ADSL") |>
  write_xpt(path)
#> 6 variables the spec declares are absent from the data (not added): `TRTDURD`,
#> `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
#> ℹ See `conformance(x)` for the findings.

# Read it back — labels, formats, types, and record count intact.
get_meta(read_xpt(path))@dataset$records
#> [1] 60
```

`columns()` is the quick look a SAS programmer expects from `PROC CONTENTS`, on a conformed frame or straight off a file:

``` r
columns(adsl)
#> <artoo_columns> ADSL -- 48 variables, 60 obs
#> #   Variable  Type  Len  Format  Label                                     Key
#> 1   STUDYID   Char  12           Study Identifier                          1
#> 2   USUBJID   Char  11           Unique Subject Identifier                 2
#> 3   SUBJID    Char  4            Subject Identifier for the Study
#> 4   SITEID    Char  3            Study Site Identifier
#> 5   SITEGR1   Char  3            Pooled Site Group 1
#> 6   ARM       Char  20           Description of Planned Arm
#> 7   TRT01P    Char  20           Planned Treatment for Period 01
#> 8   TRT01PN   Num                Planned Treatment for Period 01 (N)
#> 9   TRT01A    Char  20           Actual Treatment for Period 01
#> 10  TRT01AN   Num                Actual Treatment for Period 01 (N)
#> 11  TRTSDT    Num        DATE9.  Date of First Exposure to Treatment
#> 12  TRTEDT    Num        DATE9.  Date of Last Exposure to Treatment
#> 13  AVGDD     Num        5.1     Avg Daily Dose (as planned)
#> 14  CUMDOSE   Num        8.1     Cumulative Dose (as planned)
#> 15  AGE       Num                Age
#> 16  AGEGR1    Char  5            Pooled Age Group 1
#> 17  AGEGR1N   Num                Pooled Age Group 1 (N)
#> 18  AGEU      Char  5            Age Units
#> 19  RACE      Char  32           Race
#> 20  RACEN     Num                Race (N)
#> 21  SEX       Char  1            Sex
#> 22  ETHNIC    Char  22           Ethnicity
#> 23  SAFFL     Char  1            Safety Population Flag
#> 24  ITTFL     Char  1            Intent-To-Treat Population Flag
#> 25  EFFFL     Char  1            Efficacy Population Flag
#> 26  COMP8FL   Char  1            Completers of Week 8 Population Flag
#> 27  COMP16FL  Char  1            Completers of Week 16 Population Flag
#> 28  COMP24FL  Char  1            Completers of Week 24 Population Flag
#> 29  DISCONFL  Char  1            Subject Discontinued Study Flag
#> 30  DSRAEFL   Char  1            Subject Discontinued due to AE Flag
#> 31  DTHFL     Char  1            Subject Death Flag
#> 32  BMIBL     Num        5.1     Baseline BMI (kg/m^2)
#> 33  BMIBLGR1  Char  6            Pooled Baseline BMI Group 1
#> 34  HEIGHTBL  Num        6.1     Baseline Height (cm)
#> 35  WEIGHTBL  Num        6.1     Baseline Weight (kg)
#> 36  EDUCLVL   Num                Years of Education
#> 37  DURDIS    Num        6.1     Duration of Disease (Months)
#> 38  DURDSGR1  Char  4            Pooled Disease Duration Group 1
#> 39  VISIT1DT  Num        DATE9.  Date of Visit 1
#> 40  RFSTDTC   Char  10           Subject Reference Start Date/Time
#> 41  RFENDTC   Char  10           Subject Reference End Date/Time
#> 42  VISNUMEN  Num                End of Trt Visit (Vis 12 or Early Term.)
#> 43  RFENDT    Num                Date of Discontinuation/Completion
#> 44  TRTDUR    Num
#> 45  DISONSDT  Num        DATE9.
#> 46  DCDECOD   Char  27
#> 47  DCREASCD  Char  18
#> 48  MMSETOT   Num
```

## Why artoo?

- **Lossless by construction.** One canonical metadata model carries labels, CDISC data types, lengths, SAS display formats, controlled-terminology references, and sort keys identically across every format, so any-to-any conversion preserves them — not by best effort, by design.
- **Lossless or loud.** A coercion that would truncate or an unencodable byte aborts with a classed condition before it can damage data; there is no silent-truncation path.
- **Pure R and lightweight.** No external SAS or Java runtime, and no heavy I/O dependency.
- **CDISC-native.** Types, dates and `--DTC` text, and codelists follow the Dataset-JSON v1.1 vocabulary; specs read from Define-XML, Pinnacle 21 workbooks, or native JSON.

## Where artoo fits

artoo is the carrier between the formats a clinical-trial dataset travels in: the XPORT a regulator expects, the Dataset-JSON modern CDISC exchange uses, the Parquet an analytics stack reads, and an R-native checkpoint. Reach for it whenever a dataset must change formats without losing the metadata that makes it submission-ready — labels, types, lengths, display formats, codelists, and keys — and you want that guarantee enforced rather than hoped for. It is a focused reader/writer, not a validation suite or a table renderer.

## Supported formats

| Format | Reader | Writer | Use |
|----|----|----|----|
| SAS XPORT (XPT) | `read_xpt()` | `write_xpt()` | FDA / PMDA submission |
| CDISC Dataset-JSON | `read_json()` | `write_json()` | Modern CDISC interchange |
| NDJSON | `read_ndjson()` | `write_ndjson()` | Streaming Dataset-JSON |
| Apache Parquet | `read_parquet()` | `write_parquet()` | Analytics, columnar store |
| RDS | `read_rds()` | `write_rds()` | Fast R-native storage |

The generic `read_dataset()` / `write_dataset()` dispatch on the file extension; every reader supports partial reads via `col_select` and `n_max`.

Partial ISO 8601 dates are first-class: a character `--DTC` column typed `date` writes to XPT as ISO text — `"1951-12"` survives byte for byte — while `targetDataType = "integer"` drives the ADaM numeric-date convention. SAS `TIME` values arrive as `hms` (seconds since midnight), and `>24h`, negative, and fractional times round-trip every format.

## Documentation

- [Get started](https://vthanik.github.io/artoo/articles/artoo.html) — the whole round-trip, start to finish, on bundled data.
- [Specifications](https://vthanik.github.io/artoo/articles/specs.html) — read, inspect, and repair a spec.
- [Conform & validate](https://vthanik.github.io/artoo/articles/conform.html) — `apply_spec()` and every conformance finding.
- [Formats & lossless conversion](https://vthanik.github.io/artoo/articles/convert.html) — any-to-any round trips and qualification evidence.
- [Recipes](https://vthanik.github.io/artoo/articles/recipes.html) — end-to-end ADaM and SDTM builds, dates, and codelists, rendered live.
- [Reference](https://vthanik.github.io/artoo/reference/index.html) — every function, grouped by stage.

## License

MIT © Vignesh Thanikachalam
