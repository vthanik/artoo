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
Define-XML 2.1 release examples. `adam_spec` covers the ADaM datasets;
the same spec also ships as a P21 workbook you can open in Excel:

``` r

adam_spec
```

    <artoo_spec>
    Study: (unspecified)
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
is the conform pipeline: it scaffolds the variables the spec declares
(typed `NA`), coerces each column to its CDISC data type, orders the
columns, sorts by the dataset keys, and stamps the result with its
metadata. The input is never mutated, no column is ever dropped, and a
coercion that would damage values aborts before it runs.

``` r

adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL")
```

    Scaffolded 6 variables: `TRTDURD`, `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`,
    and `MMS1TSBL`

The conformance findings ride along on the result — read them back as a
frame with
[`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md):

``` r

nrow(conformance(adsl))
```

    [1] 6

## 3. Inspect the columns

[`columns()`](https://vthanik.github.io/artoo/reference/columns.md) is
the quick look a SAS programmer expects from `PROC CONTENTS`: one row
per variable with position, type, length, format, label, and the CDISC
key sequence. It works on a conformed frame, any plain data frame, or a
file path:

``` r

columns(adsl)
```

    <artoo_columns> ADSL -- 54 variables, 60 obs
    #   Variable  Type  Len  Format  Informat  Label                                     Key
    1   STUDYID   Char  12                     Study Identifier                          1
    2   USUBJID   Char  11                     Unique Subject Identifier                 2
    3   SUBJID    Char  4                      Subject Identifier for the Study
    4   SITEID    Char  3                      Study Site Identifier
    5   SITEGR1   Char  3                      Pooled Site Group 1
    6   ARM       Char  20                     Description of Planned Arm
    7   TRT01P    Char  20                     Planned Treatment for Period 01
    8   TRT01PN   Num   2                      Planned Treatment for Period 01 (N)
    9   TRT01A    Char  20                     Actual Treatment for Period 01
    10  TRT01AN   Num   2                      Actual Treatment for Period 01 (N)
    11  TRTSDT    Num   5    date9.            Date of First Exposure to Treatment
    12  TRTEDT    Num   5    date9.            Date of Last Exposure to Treatment
    13  TRTDURD   Num   3                      Total Treatment Duration (Days)
    14  AVGDD     Num   4    5.1               Avg Daily Dose (as planned)
    15  CUMDOSE   Num   7    8.1               Cumulative Dose (as planned)
    16  AGE       Num   2                      Age
    17  AGEGR1    Char  5                      Pooled Age Group 1
    18  AGEGR1N   Num   2                      Pooled Age Group 1 (N)
    19  AGEU      Char  5                      Age Units
    20  RACE      Char  32                     Race
    21  RACEN     Num   1                      Race (N)
    22  SEX       Char  1                      Sex
    23  ETHNIC    Char  22                     Ethnicity
    24  SAFFL     Char  1                      Safety Population Flag
    25  ITTFL     Char  1                      Intent-To-Treat Population Flag
    26  EFFFL     Char  1                      Efficacy Population Flag
    27  COMP8FL   Char  1                      Completers of Week 8 Population Flag
    28  COMP16FL  Char  1                      Completers of Week 16 Population Flag
    29  COMP24FL  Char  1                      Completers of Week 24 Population Flag
    30  DISCONFL  Char  1                      Subject Discontinued Study Flag
    31  DSRAEFL   Char  1                      Subject Discontinued due to AE Flag
    32  DTHFL     Char  1                      Subject Death Flag
    33  BMIBL     Num   4    5.1               Baseline BMI (kg/m^2)
    34  BMIBLGR1  Char  6                      Pooled Baseline BMI Group 1
    35  HEIGHTBL  Num   5    6.1               Baseline Height (cm)
    36  WEIGHTBL  Num   5    6.1               Baseline Weight (kg)
    37  EDUCLVL   Num   2                      Years of Education
    38  DISONDT   Num   5    date9.            Date of Onset of Disease
    39  DURDIS    Num   5    6.1               Duration of Disease (Months)
    40  DURDSGR1  Char  4                      Pooled Disease Duration Group 1
    41  VISIT1DT  Num   5    date9.            Date of Visit 1
    42  RFSTDTC   Char                         Subject Reference Start Date/Time
    43  RFENDTC   Char                         Subject Reference End Date/Time
    44  VISNUMEN  Num   2                      End of Trt Visit (Vis 12 or Early Term.)
    45  RFENDT    Num   5                      Date of Discontinuation/Completion
    46  EOSSTT    Char  12                     End of Study Status
    47  DCSREAS   Char  18                     Reason for Discontinuation from Study
    48  EOSDISP   Char  27                     Standardized Disposition Term
    49  MMS1TSBL  Num   2                      MMS1-Total Score at Baseline
    50  TRTDUR    Num   8
    51  DISONSDT  Num   8    DATE9.
    52  DCDECOD   Char  27
    53  DCREASCD  Char  18
    54  MMSETOT   Num   8

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

back <- read_xpt(xpt)
get_meta(back)@dataset$records
```

    [1] 60

``` r

columns(back)
```

    <artoo_columns> ADSL -- 54 variables, 60 obs
    #   Variable  Type  Len  Format  Informat  Label                                     Key
    1   STUDYID   Char  12                     Study Identifier
    2   USUBJID   Char  11                     Unique Subject Identifier
    3   SUBJID    Char  4                      Subject Identifier for the Study
    4   SITEID    Char  3                      Study Site Identifier
    5   SITEGR1   Char  3                      Pooled Site Group 1
    6   ARM       Char  20                     Description of Planned Arm
    7   TRT01P    Char  20                     Planned Treatment for Period 01
    8   TRT01PN   Num                          Planned Treatment for Period 01 (N)
    9   TRT01A    Char  20                     Actual Treatment for Period 01
    10  TRT01AN   Num                          Actual Treatment for Period 01 (N)
    11  TRTSDT    Num        date9.            Date of First Exposure to Treatment
    12  TRTEDT    Num        date9.            Date of Last Exposure to Treatment
    13  TRTDURD   Num                          Total Treatment Duration (Days)
    14  AVGDD     Num        5.1               Avg Daily Dose (as planned)
    15  CUMDOSE   Num        8.1               Cumulative Dose (as planned)
    16  AGE       Num                          Age
    17  AGEGR1    Char  5                      Pooled Age Group 1
    18  AGEGR1N   Num                          Pooled Age Group 1 (N)
    19  AGEU      Char  5                      Age Units
    20  RACE      Char  32                     Race
    21  RACEN     Num                          Race (N)
    22  SEX       Char  1                      Sex
    23  ETHNIC    Char  22                     Ethnicity
    24  SAFFL     Char  1                      Safety Population Flag
    25  ITTFL     Char  1                      Intent-To-Treat Population Flag
    26  EFFFL     Char  1                      Efficacy Population Flag
    27  COMP8FL   Char  1                      Completers of Week 8 Population Flag
    28  COMP16FL  Char  1                      Completers of Week 16 Population Flag
    29  COMP24FL  Char  1                      Completers of Week 24 Population Flag
    30  DISCONFL  Char  1                      Subject Discontinued Study Flag
    31  DSRAEFL   Char  1                      Subject Discontinued due to AE Flag
    32  DTHFL     Char  1                      Subject Death Flag
    33  BMIBL     Num        5.1               Baseline BMI (kg/m^2)
    34  BMIBLGR1  Char  6                      Pooled Baseline BMI Group 1
    35  HEIGHTBL  Num        6.1               Baseline Height (cm)
    36  WEIGHTBL  Num        6.1               Baseline Weight (kg)
    37  EDUCLVL   Num                          Years of Education
    38  DISONDT   Num        date9.            Date of Onset of Disease
    39  DURDIS    Num        6.1               Duration of Disease (Months)
    40  DURDSGR1  Char  4                      Pooled Disease Duration Group 1
    41  VISIT1DT  Num        date9.            Date of Visit 1
    42  RFSTDTC   Char  10                     Subject Reference Start Date/Time
    43  RFENDTC   Char  10                     Subject Reference End Date/Time
    44  VISNUMEN  Num                          End of Trt Visit (Vis 12 or Early Term.)
    45  RFENDT    Num                          Date of Discontinuation/Completion
    46  EOSSTT    Char  12                     End of Study Status
    47  DCSREAS   Char  18                     Reason for Discontinuation from Study
    48  EOSDISP   Char  27                     Standardized Disposition Term
    49  MMS1TSBL  Num                          MMS1-Total Score at Baseline
    50  TRTDUR    Num
    51  DISONSDT  Num        DATE9.
    52  DCDECOD   Char  27
    53  DCREASCD  Char  18
    54  MMSETOT   Num

That round-trip identity is the whole point: what you submit is what you
archived is what you analysed.

## Where to next

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
