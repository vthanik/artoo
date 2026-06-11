

<!-- README.md is generated from README.qmd. Please edit that file -->

# artoo <a href="https://vthanik.github.io/artoo/"><img src="man/figures/logo.png" align="right" height="139" alt="artoo website" /></a>

<!-- badges: start -->

[![R-CMD-check](https://github.com/vthanik/artoo/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/vthanik/artoo/actions/workflows/R-CMD-check.yaml) [![Codecov test coverage](https://codecov.io/gh/vthanik/artoo/graph/badge.svg)](https://app.codecov.io/gh/vthanik/artoo) [![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active) <!-- badges: end -->

**artoo** is a lightweight, lossless, CDISC-native reader and writer for clinical-trial datasets. It moves data between **SAS XPORT (XPT)**, **CDISC Dataset-JSON v1.1**, **Apache Parquet**, and **RDS** through one canonical metadata model, so converting between any two formats is lossless *by construction* — not by best effort.

It is **pure R and lightweight**: no external SAS or Java runtime, and no heavy I/O dependency. One metadata model carries labels, CDISC data types, lengths, SAS display formats, controlled-terminology references, and sort keys identically across every format.

## Installation

``` r
# install.packages("pak")
pak::pak("vthanik/artoo")
```

## Quick start

A spec describes the dataset; `apply_spec()` conforms a raw frame to it; the writers carry every piece of metadata to disk — one pipeable chain:

``` r
library(artoo)

# A ready-made ADaM spec, bundled from the official CDISC Define-XML
# 2.1 example (one spec = one standard; this one is ADaMIG 1.1)
adam_spec
#> <artoo_spec>
#> Study: CDISC-Sample
#> Standard: ADaMIG 1.1
#> Datasets:  2
#> Variables: 104
#> Codelists: 30
#> Methods: 54
#> Comments: 22
#> Documents: 9
#> Spec for: ADSL, ADAE

# Scaffold, coerce, order, sort, stamp metadata, then write — the writers
# return their input invisibly, so one conformed frame fans out to every
# deliverable format.
path <- tempfile(fileext = ".xpt")
adsl <- cdisc_adsl |>
  apply_spec(adam_spec, "ADSL") |>
  write_xpt(path)
#> Scaffolded 6 variables: `TRTDURD`, `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`,
#> and `MMS1TSBL`

# Read it back — labels, formats, types, and record count intact
get_meta(read_xpt(path))@dataset$records
#> [1] 60
```

`columns()` is the quick look a SAS programmer expects from `PROC CONTENTS` — on a conformed frame or straight off a file (a metadata-carrying format also shows the CDISC `Key` sequence; XPORT bytes cannot store it):

``` r
columns(adsl)
#> <artoo_columns> ADSL -- 54 variables, 60 obs
#> #   Variable  Type  Len  Format  Informat  Label                                     Key
#> 1   STUDYID   Char  12                     Study Identifier                          1
#> 2   USUBJID   Char  11                     Unique Subject Identifier                 2
#> 3   SUBJID    Char  4                      Subject Identifier for the Study
#> 4   SITEID    Char  3                      Study Site Identifier
#> 5   SITEGR1   Char  3                      Pooled Site Group 1
#> 6   ARM       Char  20                     Description of Planned Arm
#> 7   TRT01P    Char  20                     Planned Treatment for Period 01
#> 8   TRT01PN   Num   2                      Planned Treatment for Period 01 (N)
#> 9   TRT01A    Char  20                     Actual Treatment for Period 01
#> 10  TRT01AN   Num   2                      Actual Treatment for Period 01 (N)
#> 11  TRTSDT    Num   5    date9.            Date of First Exposure to Treatment
#> 12  TRTEDT    Num   5    date9.            Date of Last Exposure to Treatment
#> 13  TRTDURD   Num   3                      Total Treatment Duration (Days)
#> 14  AVGDD     Num   4    5.1               Avg Daily Dose (as planned)
#> 15  CUMDOSE   Num   7    8.1               Cumulative Dose (as planned)
#> 16  AGE       Num   2                      Age
#> 17  AGEGR1    Char  5                      Pooled Age Group 1
#> 18  AGEGR1N   Num   2                      Pooled Age Group 1 (N)
#> 19  AGEU      Char  5                      Age Units
#> 20  RACE      Char  32                     Race
#> 21  RACEN     Num   1                      Race (N)
#> 22  SEX       Char  1                      Sex
#> 23  ETHNIC    Char  22                     Ethnicity
#> 24  SAFFL     Char  1                      Safety Population Flag
#> 25  ITTFL     Char  1                      Intent-To-Treat Population Flag
#> 26  EFFFL     Char  1                      Efficacy Population Flag
#> 27  COMP8FL   Char  1                      Completers of Week 8 Population Flag
#> 28  COMP16FL  Char  1                      Completers of Week 16 Population Flag
#> 29  COMP24FL  Char  1                      Completers of Week 24 Population Flag
#> 30  DISCONFL  Char  1                      Subject Discontinued Study Flag
#> 31  DSRAEFL   Char  1                      Subject Discontinued due to AE Flag
#> 32  DTHFL     Char  1                      Subject Death Flag
#> 33  BMIBL     Num   4    5.1               Baseline BMI (kg/m^2)
#> 34  BMIBLGR1  Char  6                      Pooled Baseline BMI Group 1
#> 35  HEIGHTBL  Num   5    6.1               Baseline Height (cm)
#> 36  WEIGHTBL  Num   5    6.1               Baseline Weight (kg)
#> 37  EDUCLVL   Num   2                      Years of Education
#> 38  DISONDT   Num   5    date9.            Date of Onset of Disease
#> 39  DURDIS    Num   5    6.1               Duration of Disease (Months)
#> 40  DURDSGR1  Char  4                      Pooled Disease Duration Group 1
#> 41  VISIT1DT  Num   5    date9.            Date of Visit 1
#> 42  RFSTDTC   Char                         Subject Reference Start Date/Time
#> 43  RFENDTC   Char                         Subject Reference End Date/Time
#> 44  VISNUMEN  Num   2                      End of Trt Visit (Vis 12 or Early Term.)
#> 45  RFENDT    Num   5                      Date of Discontinuation/Completion
#> 46  EOSSTT    Char  12                     End of Study Status
#> 47  DCSREAS   Char  18                     Reason for Discontinuation from Study
#> 48  EOSDISP   Char  27                     Standardized Disposition Term
#> 49  MMS1TSBL  Num   2                      MMS1-Total Score at Baseline
#> 50  TRTDUR    Num   8
#> 51  DISONSDT  Num   8    DATE9.
#> 52  DCDECOD   Char  27
#> 53  DCREASCD  Char  18
#> 54  MMSETOT   Num   8
```

Conformance is data, not console noise: `conformance(adsl)` returns every finding as a frame (`check`, `severity`, `variable`, `message`) with a sectioned print, and `decode_column()` derives coded variables straight from the spec’s codelists.

## Any-to-any, lossless

One conformed dataset becomes a file in any supported format, and any file becomes any other, with the metadata carried straight through:

``` r
json <- tempfile(fileext = ".json")
write_json(adsl, json)

# Dataset-JSON on disk -> a submission XPT, no spec re-application
out <- tempfile(fileext = ".xpt")
write_xpt(read_json(json), out)
```

## Supported formats

    #>    format read write    extensions
    #> 1    json TRUE  TRUE          json
    #> 2  ndjson TRUE  TRUE ndjson, jsonl
    #> 3 parquet TRUE  TRUE   parquet, pq
    #> 4     rds TRUE  TRUE           rds
    #> 5     xpt TRUE  TRUE    xpt, xport

| Format | Reader | Writer | Use |
|----|----|----|----|
| SAS XPORT (XPT) | `read_xpt()` | `write_xpt()` | FDA / PMDA submission |
| CDISC Dataset-JSON | `read_json()` | `write_json()` | Modern CDISC interchange |
| NDJSON | `read_ndjson()` | `write_ndjson()` | Streaming Dataset-JSON |
| Apache Parquet | `read_parquet()` | `write_parquet()` | Analytics, columnar store |
| RDS | `read_rds()` | `write_rds()` | Fast R-native storage |

The generic `read_dataset()` / `write_dataset()` dispatch on the file extension; every reader supports partial reads via `col_select` and `n_max`.

Partial ISO 8601 dates are first-class: a character `--DTC` column typed `date` writes to XPT as ISO text — `"1951-12"` survives byte for byte — while `targetDataType = "integer"` drives the ADaM numeric-date convention. SAS `TIME` values arrive as `hms` (seconds since midnight), and `>24h`, negative, and fractional times round-trip every format.

## Specs from anywhere

`read_spec()` reads Define-XML 2.x, Pinnacle 21 workbooks, and artoo’s native JSON; `write_spec()` writes native JSON (lossless) and P21 workbooks (interchange). Conversion is one composition:

``` r
read_spec("define.xml") |> write_spec("spec.xlsx")
```

## Learn more

- `vignette("getting-started")` — the whole workflow, start to finish: spec → apply → inspect → write → read back.

## License

MIT © Vignesh Thanikachalam
