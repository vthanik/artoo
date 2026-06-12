# Getting started with artoo

`artoo` carries clinical-trial datasets losslessly across SAS XPORT,
CDISC Dataset-JSON, NDJSON, Apache Parquet, and RDS through one
canonical, CDISC-shaped metadata model. This vignette walks the whole
workflow once, start to finish: **spec → apply → inspect → write → read
back**.

## 1. Get a spec

A `artoo_spec` is the canonical description of your datasets: variables,
CDISC data types, lengths, labels, controlled-terminology codelists, and
sort keys — always for exactly **one** CDISC standard.
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
reads one from Define-XML, a Pinnacle 21 workbook, or artoo’s native
JSON;
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
assembles one from metadata frames.

The package bundles ready-made specs built from the official CDISC
Define-XML 2.1 release examples — `adam_spec` for ADaM (ADSL, ADAE) and
`sdtm_spec` for SDTM (DM, VS, TS, SUPPDM). Each also ships as a P21
workbook you can open in Excel:

``` r

adam_spec
```

    <artoo_spec>
    Study: CDISC-Sample
    Standard: ADaMIG 1.1
    Datasets:  2
    Variables: 104
    Codelists: 30
    Methods: 54
    Comments: 22
    Documents: 9
    Spec for: ADSL, ADAE

``` r

p21 <- system.file("extdata", "adam-spec.xlsx", package = "artoo")
identical(spec_standard(read_spec(p21)), spec_standard(adam_spec))
```

    [1] TRUE

Because
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
and
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md)
are inverses on each format, format conversion is one composition —
Define-XML in, P21 workbook out:

``` r

read_spec("define.xml") |> write_spec("spec.xlsx")
```

## 2. Apply the spec

[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
is the conform pipeline: it coerces each column to its CDISC data type,
orders the columns, sorts by the dataset keys, and stamps the result
with its metadata. A variable the spec declares but the data lacks is
reported, never fabricated as an empty column. The input is never
mutated, no column is ever dropped, and a coercion that would damage
values aborts before it runs.

``` r

adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL")
```

    6 variables the spec declares are absent from the data (not added): `TRTDURD`,
    `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
    ℹ See `conformance(x)` for the findings.

The conformance findings ride along on the result — read them back as a
frame with
[`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md):

``` r

nrow(conformance(adsl))
```

    [1] 12

The pipeline is standard-neutral: an SDTM domain conforms identically —
only the spec and the dataset change. The full SDTM walkthrough is its
own [task
guide](https://vthanik.github.io/artoo/articles/articles/sdtm-build.md).

``` r

dm <- apply_spec(cdisc_dm, sdtm_spec, "DM")
```

    1 variable the spec declares is absent from the data (not added): `BRTHDTC`.
    ℹ See `conformance(x)` for the findings.

``` r

nrow(conformance(dm))
```

    [1] 14

## 3. Inspect the columns

[`columns()`](https://vthanik.github.io/artoo/reference/columns.md) is
the quick look a SAS programmer expects from `PROC CONTENTS`: one row
per variable with position, type, length, format, label, and the CDISC
key sequence. It works on a conformed frame, any plain data frame, or a
file path:

``` r

columns(adsl)
```

    <artoo_columns> ADSL -- 48 variables, 60 obs
    #   Variable  Type  Len  Format  Label                                     Key
    1   STUDYID   Char  12           Study Identifier                          1
    2   USUBJID   Char  11           Unique Subject Identifier                 2
    3   SUBJID    Char  4            Subject Identifier for the Study
    4   SITEID    Char  3            Study Site Identifier
    5   SITEGR1   Char  3            Pooled Site Group 1
    6   ARM       Char  20           Description of Planned Arm
    7   TRT01P    Char  20           Planned Treatment for Period 01
    8   TRT01PN   Num                Planned Treatment for Period 01 (N)
    9   TRT01A    Char  20           Actual Treatment for Period 01
    10  TRT01AN   Num                Actual Treatment for Period 01 (N)
    11  TRTSDT    Num        DATE9.  Date of First Exposure to Treatment
    12  TRTEDT    Num        DATE9.  Date of Last Exposure to Treatment
    13  AVGDD     Num        5.1     Avg Daily Dose (as planned)
    14  CUMDOSE   Num        8.1     Cumulative Dose (as planned)
    15  AGE       Num                Age
    16  AGEGR1    Char  5            Pooled Age Group 1
    17  AGEGR1N   Num                Pooled Age Group 1 (N)
    18  AGEU      Char  5            Age Units
    19  RACE      Char  32           Race
    20  RACEN     Num                Race (N)
    21  SEX       Char  1            Sex
    22  ETHNIC    Char  22           Ethnicity
    23  SAFFL     Char  1            Safety Population Flag
    24  ITTFL     Char  1            Intent-To-Treat Population Flag
    25  EFFFL     Char  1            Efficacy Population Flag
    26  COMP8FL   Char  1            Completers of Week 8 Population Flag
    27  COMP16FL  Char  1            Completers of Week 16 Population Flag
    28  COMP24FL  Char  1            Completers of Week 24 Population Flag
    29  DISCONFL  Char  1            Subject Discontinued Study Flag
    30  DSRAEFL   Char  1            Subject Discontinued due to AE Flag
    31  DTHFL     Char  1            Subject Death Flag
    32  BMIBL     Num        5.1     Baseline BMI (kg/m^2)
    33  BMIBLGR1  Char  6            Pooled Baseline BMI Group 1
    34  HEIGHTBL  Num        6.1     Baseline Height (cm)
    35  WEIGHTBL  Num        6.1     Baseline Weight (kg)
    36  EDUCLVL   Num                Years of Education
    37  DURDIS    Num        6.1     Duration of Disease (Months)
    38  DURDSGR1  Char  4            Pooled Disease Duration Group 1
    39  VISIT1DT  Num        DATE9.  Date of Visit 1
    40  RFSTDTC   Char  10           Subject Reference Start Date/Time
    41  RFENDTC   Char  10           Subject Reference End Date/Time
    42  VISNUMEN  Num                End of Trt Visit (Vis 12 or Early Term.)
    43  RFENDT    Num                Date of Discontinuation/Completion
    44  TRTDUR    Num
    45  DISONSDT  Num        DATE9.
    46  DCDECOD   Char  27
    47  DCREASCD  Char  18
    48  MMSETOT   Num

## 4. Write to any format — losslessly

Every writer carries the full metadata model, so the write is lossless
by construction. The writers return their input invisibly, so one
conformed frame fans out to every deliverable:

``` r

xpt <- tempfile(fileext = ".xpt")
json <- tempfile(fileext = ".json")

adsl |>
  write_xpt(xpt) |>
  write_json(json)
```

Any file converts to any other without re-applying the spec — the
metadata travels inside (or beside) the container:

``` r

parquet <- tempfile(fileext = ".parquet")
write_parquet(read_json(json), parquet)
```

## 5. Read back, intact

Reading restores the values, the R classes (dates as `Date`, times as
`hms`), the labels, and the metadata — identically from every format:

``` r

back <- read_json(json)
get_meta(back)@dataset$records
```

    [1] 60

``` r

columns(back)
```

    <artoo_columns> ADSL -- 48 variables, 60 obs
    #   Variable  Type  Len  Format  Label                                     Key
    1   STUDYID   Char  12           Study Identifier                          1
    2   USUBJID   Char  11           Unique Subject Identifier                 2
    3   SUBJID    Char  4            Subject Identifier for the Study
    4   SITEID    Char  3            Study Site Identifier
    5   SITEGR1   Char  3            Pooled Site Group 1
    6   ARM       Char  20           Description of Planned Arm
    7   TRT01P    Char  20           Planned Treatment for Period 01
    8   TRT01PN   Num                Planned Treatment for Period 01 (N)
    9   TRT01A    Char  20           Actual Treatment for Period 01
    10  TRT01AN   Num                Actual Treatment for Period 01 (N)
    11  TRTSDT    Num        DATE9.  Date of First Exposure to Treatment
    12  TRTEDT    Num        DATE9.  Date of Last Exposure to Treatment
    13  AVGDD     Num        5.1     Avg Daily Dose (as planned)
    14  CUMDOSE   Num        8.1     Cumulative Dose (as planned)
    15  AGE       Num                Age
    16  AGEGR1    Char  5            Pooled Age Group 1
    17  AGEGR1N   Num                Pooled Age Group 1 (N)
    18  AGEU      Char  5            Age Units
    19  RACE      Char  32           Race
    20  RACEN     Num                Race (N)
    21  SEX       Char  1            Sex
    22  ETHNIC    Char  22           Ethnicity
    23  SAFFL     Char  1            Safety Population Flag
    24  ITTFL     Char  1            Intent-To-Treat Population Flag
    25  EFFFL     Char  1            Efficacy Population Flag
    26  COMP8FL   Char  1            Completers of Week 8 Population Flag
    27  COMP16FL  Char  1            Completers of Week 16 Population Flag
    28  COMP24FL  Char  1            Completers of Week 24 Population Flag
    29  DISCONFL  Char  1            Subject Discontinued Study Flag
    30  DSRAEFL   Char  1            Subject Discontinued due to AE Flag
    31  DTHFL     Char  1            Subject Death Flag
    32  BMIBL     Num        5.1     Baseline BMI (kg/m^2)
    33  BMIBLGR1  Char  6            Pooled Baseline BMI Group 1
    34  HEIGHTBL  Num        6.1     Baseline Height (cm)
    35  WEIGHTBL  Num        6.1     Baseline Weight (kg)
    36  EDUCLVL   Num                Years of Education
    37  DURDIS    Num        6.1     Duration of Disease (Months)
    38  DURDSGR1  Char  4            Pooled Disease Duration Group 1
    39  VISIT1DT  Num        DATE9.  Date of Visit 1
    40  RFSTDTC   Char  10           Subject Reference Start Date/Time
    41  RFENDTC   Char  10           Subject Reference End Date/Time
    42  VISNUMEN  Num                End of Trt Visit (Vis 12 or Early Term.)
    43  RFENDT    Num                Date of Discontinuation/Completion
    44  TRTDUR    Num
    45  DISONSDT  Num        DATE9.
    46  DCDECOD   Char  27
    47  DCREASCD  Char  18
    48  MMSETOT   Num

One honest caveat: the XPORT byte layout stores only name, label,
length, and formats, so
[`columns()`](https://vthanik.github.io/artoo/reference/columns.md) on
an `.xpt` path shows a blank `Key` — the key sequence (like codelist
references) rides the metadata-carrying formats and the in-session
frame, never the 1980s transport bytes.

That round-trip identity is the whole point: what you submit is what you
archived is what you analysed.

## Where to next

- The task guides: [an end-to-end ADaM
  build](https://vthanik.github.io/artoo/articles/articles/adam-build.md),
  [an end-to-end SDTM
  build](https://vthanik.github.io/artoo/articles/articles/sdtm-build.md),
  [any-to-any
  conversion](https://vthanik.github.io/artoo/articles/articles/convert.md),
  [dates, times, and
  `--DTC`](https://vthanik.github.io/artoo/articles/articles/dates.md),
  [validation &
  qualification](https://vthanik.github.io/artoo/articles/articles/validation.md),
  and [common
  errors](https://vthanik.github.io/artoo/articles/articles/errors.md).
- [`?apply_spec`](https://vthanik.github.io/artoo/reference/apply_spec.md),
  [`?check_spec`](https://vthanik.github.io/artoo/reference/check_spec.md),
  [`?decode_column`](https://vthanik.github.io/artoo/reference/decode_column.md)
  — the conform surface.
- [`?read_spec`](https://vthanik.github.io/artoo/reference/read_spec.md),
  [`?write_spec`](https://vthanik.github.io/artoo/reference/write_spec.md),
  [`?spec_variables`](https://vthanik.github.io/artoo/reference/spec_variables.md)
  — the spec surface.
- [`?read_dataset`](https://vthanik.github.io/artoo/reference/read_dataset.md)
  — generic I/O and the per-format wrappers.
- [`?adam_spec`](https://vthanik.github.io/artoo/reference/cdisc_specs.md)
  — the bundled demo specs and datasets.
