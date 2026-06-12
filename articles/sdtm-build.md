# An end-to-end SDTM build

This article walks the SDTM tabulation loop with artoo doing the
carriage: load the spec, assemble the domain, check controlled
terminology, conform, and fan the result out to every deliverable
format. Everything runs on the bundled demo data (`cdisc_dm`,
`sdtm_spec` — built reproducibly from the official CDISC Define-XML 2.1
example and the PHUSE Test Data Factory). It is the SDTM counterpart of
the [ADaM
build](https://vthanik.github.io/artoo/articles/adam-build.md); the
pipeline is identical, only the spec and the data change.

## 1. The spec is the contract

`sdtm_spec` describes the SDTM domains DM, VS, TS, and SUPPDM for SDTMIG
3.1.2 — variables, CDISC data types, lengths, labels, codelists, and
keys:

``` r

sdtm_spec
```

    <artoo_spec>
    Study: CDISC01_1
    Standard: SDTMIG 3.1.2
    Datasets:  4
    Variables: 52
    Codelists: 39
    Methods: 33
    Comments: 30
    Documents: 12
    Value-level: 35
    Spec for: TS, DM, VS, SUPPDM

The accessors return plain data frames, so the spec slots into ordinary
base R work:

``` r

vars <- spec_variables(sdtm_spec, "DM")
head(vars[, c("variable", "label", "data_type", "codelist_id")])
```

       variable                             label data_type  codelist_id
    14  STUDYID                  Study Identifier    string         <NA>
    15   DOMAIN               Domain Abbreviation    string CL.DM.DOMAIN
    16  USUBJID         Unique Subject Identifier    string         <NA>
    17   SUBJID  Subject Identifier for the Study    string         <NA>
    18  RFSTDTC Subject Reference Start Date/Time      date         <NA>
    19  RFENDTC   Subject Reference End Date/Time      date         <NA>

## 2. Assemble the domain, with temporaries

A tabulation program accumulates working columns the spec never declares
— a QC flag, an intermediate join. Those are “extras”, and you decide
their fate at conform time:

``` r

dm <- cdisc_dm
dm$AGE_CHECK <- dm$AGE >= 18
```

## 3. Controlled terminology: check membership

Each coded variable’s row in the spec names its `codelist_id`, and
[`spec_codelists()`](https://vthanik.github.io/artoo/reference/spec_codelists.md)
returns the terms a value is allowed to take:

``` r

head(spec_codelists(sdtm_spec))
```

      codelist_id               term             decode order extended comment_id
    1     CL.AGEU              YEARS               <NA>     1    FALSE       <NA>
    2      CL.ARM Miracle Drug 10 mg               <NA>    NA     TRUE       <NA>
    3      CL.ARM Miracle Drug 20 mg               <NA>    NA     TRUE       <NA>
    4      CL.ARM            Placebo               <NA>    NA     TRUE       <NA>
    5      CL.ARM     Screen Failure               <NA>    NA     TRUE       <NA>
    6    CL.ARMCD           WONDER10 Miracle Drug 10 mg     1     TRUE       <NA>

[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
never translates values, so submission values stay exactly as collected;
[`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md)
is the explicit single-variable translator when you need to move between
a code and its decode.

## 4. Conform: coerce, order, sort, stamp

[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
runs the fixed pipeline and stamps the CDISC metadata. `extra = "drop"`
trims the QC temporaries to exactly the spec’s columns — announced, and
recorded by the `extra_variable` finding, so the drop is never silent:

``` r

conformed <- apply_spec(dm, sdtm_spec, "DM", extra = "drop")
```

    1 variable the spec declares is absent from the data (not added): `BRTHDTC`.
    ℹ See `conformance(x)` for the findings.
    Dropped 11 undeclared variables: `RFXSTDTC`, `RFXENDTC`, `RFICDTC`, `RFPENDTC`,
    `DTHDTC`, `DTHFL`, `ACTARMCD`, `ACTARM`, `DMDTC`, `DMDY`, and `AGE_CHECK`

``` r

"AGE_CHECK" %in% names(conformed)
```

    [1] FALSE

A `--DTC` reference date such as `RFSTDTC` is ISO 8601 text by CDISC
definition, so it stays character through the pipeline; in the
`PROC CONTENTS`-style pane its length is the stored byte width, while a
numeric carries none:

``` r

columns(conformed)
```

    <artoo_columns> DM -- 15 variables, 60 obs
    #   Variable  Type  Len  Format  Label                              Key
    1   STUDYID   Char  7            Study Identifier                   1
    2   DOMAIN    Char  2            Domain Abbreviation
    3   USUBJID   Char  14           Unique Subject Identifier          2
    4   SUBJID    Char  6            Subject Identifier for the Study
    5   RFSTDTC   Char  10           Subject Reference Start Date/Time
    6   RFENDTC   Char  10           Subject Reference End Date/Time
    7   SITEID    Char  3            Study Site Identifier
    8   AGE       Num                Age
    9   AGEU      Char  5            Age Units
    10  SEX       Char  16           Sex
    11  RACE      Char  41           Race
    12  ETHNIC    Char  22           Ethnicity
    13  ARMCD     Char  8            Planned Arm Code
    14  ARM       Char  20           Description of Planned Arm
    15  COUNTRY   Char  3            Country

## 5. Fan out to every deliverable

The writers return their input invisibly, so one conformed domain flows
to every format in a single pipe — losslessly, because each codec
carries the same metadata.
[`members()`](https://vthanik.github.io/artoo/reference/members.md) then
reads any container back as a one-line inventory:

``` r

xpt <- tempfile(fileext = ".xpt")
json <- tempfile(fileext = ".json")
conformed |>
  write_xpt(xpt) |>
  write_json(json)
members(json)
```

    <artoo_members> 1 dataset
    file                  member  label         records  variables  format
    file200e3cfa437.json  DM      Demographics  60       15         json

## Where to next

- [An end-to-end ADaM
  build](https://vthanik.github.io/artoo/articles/adam-build.md) — the
  analysis-dataset loop.
- [Any-to-any
  conversion](https://vthanik.github.io/artoo/articles/convert.md) —
  moving between the formats.
- [Dates, times, and
  `--DTC`](https://vthanik.github.io/artoo/articles/dates.md) — how
  temporal values travel.
- [Common errors](https://vthanik.github.io/artoo/articles/errors.md) —
  every condition, its trigger, its fix.
