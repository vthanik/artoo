# artoo

![The artoo lossless round-trip: a spec plus data go through
apply_spec(), write to a file, and read back identical; set_type() and
check_spec() fix and inspect the
spec.](reference/figures/round-trip-hero.svg)

**artoo** is a lightweight, lossless, CDISC-native reader and writer for
clinical-trial datasets. It moves data between **SAS XPORT (XPT)**,
**CDISC Dataset-JSON v1.1**, **Apache Parquet**, and **RDS** through one
canonical metadata model, so converting between any two formats is
lossless *by construction* — not by best effort.

It is **pure R and lightweight**: no external SAS or Java runtime, and
no heavy I/O dependency. One metadata model carries labels, CDISC data
types, lengths, SAS display formats, controlled-terminology references,
and sort keys identically across every format.

## Installation

``` r

# install.packages("pak")
pak::pak("vthanik/artoo")
```

## Quick start

A spec describes the dataset;
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
conforms a raw frame to it; the writers carry every piece of metadata to
disk — one pipeable chain:

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

# Coerce, order, sort, stamp metadata, then write — the writers
# return their input invisibly, so one conformed frame fans out to every
# deliverable format.
path <- tempfile(fileext = ".xpt")
adsl <- cdisc_adsl |>
  apply_spec(adam_spec, "ADSL") |>
  write_xpt(path)
#> 6 variables the spec declares are absent from the data (not added): `TRTDURD`,
#> `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
#> ℹ See `conformance(x)` for the findings.

# Read it back — labels, formats, types, and record count intact
get_meta(read_xpt(path))@dataset$records
#> [1] 60
```

[`columns()`](https://vthanik.github.io/artoo/reference/columns.md) is
the quick look a SAS programmer expects from `PROC CONTENTS` — on a
conformed frame or straight off a file (a metadata-carrying format also
shows the CDISC `Key` sequence; XPORT bytes cannot store it):

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

Conformance is data, not console noise: `conformance(adsl)` returns
every finding as a frame (`check`, `severity`, `variable`, `message`)
with a sectioned print, and
[`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md)
derives coded variables straight from the spec’s codelists.

## Any-to-any, lossless

One conformed dataset becomes a file in any supported format, and any
file becomes any other, with the metadata carried straight through:

``` r

json <- tempfile(fileext = ".json")
write_json(adsl, json)

# Dataset-JSON on disk -> a submission XPT, no spec re-application
out <- tempfile(fileext = ".xpt")
write_xpt(read_json(json), out)
```

## Supported formats

``` R
#>    format read write    extensions
#> 1    json TRUE  TRUE          json
#> 2  ndjson TRUE  TRUE ndjson, jsonl
#> 3 parquet TRUE  TRUE   parquet, pq
#> 4     rds TRUE  TRUE           rds
#> 5     xpt TRUE  TRUE    xpt, xport
```

| Format | Reader | Writer | Use |
|----|----|----|----|
| SAS XPORT (XPT) | [`read_xpt()`](https://vthanik.github.io/artoo/reference/read_xpt.md) | [`write_xpt()`](https://vthanik.github.io/artoo/reference/write_xpt.md) | FDA / PMDA submission |
| CDISC Dataset-JSON | [`read_json()`](https://vthanik.github.io/artoo/reference/read_json.md) | [`write_json()`](https://vthanik.github.io/artoo/reference/write_json.md) | Modern CDISC interchange |
| NDJSON | [`read_ndjson()`](https://vthanik.github.io/artoo/reference/read_ndjson.md) | [`write_ndjson()`](https://vthanik.github.io/artoo/reference/write_ndjson.md) | Streaming Dataset-JSON |
| Apache Parquet | [`read_parquet()`](https://vthanik.github.io/artoo/reference/read_parquet.md) | [`write_parquet()`](https://vthanik.github.io/artoo/reference/write_parquet.md) | Analytics, columnar store |
| RDS | [`read_rds()`](https://vthanik.github.io/artoo/reference/read_rds.md) | [`write_rds()`](https://vthanik.github.io/artoo/reference/write_rds.md) | Fast R-native storage |

The generic
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
/
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
dispatch on the file extension; every reader supports partial reads via
`col_select` and `n_max`.

Partial ISO 8601 dates are first-class: a character `--DTC` column typed
`date` writes to XPT as ISO text — `"1951-12"` survives byte for byte —
while `targetDataType = "integer"` drives the ADaM numeric-date
convention. SAS `TIME` values arrive as `hms` (seconds since midnight),
and `>24h`, negative, and fractional times round-trip every format.

## Specs from anywhere

[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
reads Define-XML 2.x, Pinnacle 21 workbooks, and artoo’s native JSON;
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md)
writes native JSON (lossless) and P21 workbooks (interchange).
Conversion is one composition:

``` r

read_spec("define.xml") |> write_spec("spec.xlsx")
```

## Learn more

- [`vignette("artoo")`](https://vthanik.github.io/artoo/articles/artoo.md)
  — the whole workflow, start to finish: spec → apply → inspect → write
  → read back, for both SDTM and ADaM.

## License

MIT © Vignesh Thanikachalam
