# An end-to-end ADaM build

This article walks the everyday ADaM programming loop with artoo doing
the carriage: load the spec, derive, translate through codelists,
conform, and fan the result out to every deliverable format. Everything
runs on the bundled demo data (`cdisc_adsl`, `adam_spec` — built
reproducibly from the official CDISC Define-XML 2.1 example and the
PHUSE Test Data Factory).

## 1. The spec is the contract

`adam_spec` describes ADSL and ADAE for ADaMIG 1.1 — variables, CDISC
data types, lengths, labels, codelists, and keys:

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

The accessors return plain data frames, so the spec slots into ordinary
base R work:

``` r

vars <- spec_variables(adam_spec, "ADSL")
head(vars[, c("variable", "label", "data_type", "codelist_id")])
```

      variable                            label data_type codelist_id
    1  STUDYID                 Study Identifier    string        <NA>
    2  USUBJID        Unique Subject Identifier    string        <NA>
    3   SUBJID Subject Identifier for the Study    string        <NA>
    4   SITEID            Study Site Identifier    string        <NA>
    5  SITEGR1              Pooled Site Group 1    string        <NA>
    6      ARM       Description of Planned Arm    string      CL.ARM

## 2. Derive, with temporaries

A real derivation program accumulates working columns the spec never
declares. That is fine — they are “extras”, and you decide their fate at
conform time:

``` r

adsl <- cdisc_adsl
adsl$AGEGR1_TMP <- cut(
  adsl$AGE,
  breaks = c(-Inf, 64, 74, Inf),
  labels = c("<65", "65-74", ">=75")
)
adsl$AGEGR1 <- as.character(adsl$AGEGR1_TMP)
```

## 3. Codelists: check membership, translate values

The codelist surface is reference-keyed: each variable’s row in the spec
names its `codelist_id`, and
[`spec_codelists()`](https://vthanik.github.io/artoo/reference/spec_codelists.md)
returns the terms:

``` r

head(spec_codelists(adam_spec))
```

      codelist_id  term decode order extended comment_id
    1   CL.AGEGR1   <65   <NA>    NA    FALSE       <NA>
    2   CL.AGEGR1 65-80   <NA>    NA    FALSE       <NA>
    3   CL.AGEGR1   >80   <NA>    NA    FALSE       <NA>
    4  CL.AGEGR1N     1    <65     1    FALSE       <NA>
    5  CL.AGEGR1N     2  65-80     2    FALSE       <NA>
    6  CL.AGEGR1N     3    >80     3    FALSE       <NA>

[`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md)
is the single-variable translator (code to decode or decode to code —
the `RACEN`-from-`RACE` shape);
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
itself never translates values, so submission values stay untouched
unless you ask.

## 4. Conform: coerce, order, sort, stamp

[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
runs the fixed pipeline and stamps the CDISC metadata. `extra = "drop"`
trims the derivation temporaries to exactly the spec’s columns —
announced, and recorded by the `extra_variable` finding, so the drop is
never silent:

``` r

conformed <- apply_spec(adsl, adam_spec, "ADSL", extra = "drop")
```

    6 variables the spec declares are absent from the data (not added): `TRTDURD`,
    `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
    ℹ See `conformance(x)` for the findings.

    Warning: 1 conformance error for "ADSL".
    ℹ Run `conformance(x)` on the returned frame to see every finding.

    Dropped 6 undeclared variables: `TRTDUR`, `DISONSDT`, `DCDECOD`, `DCREASCD`,
    `MMSETOT`, and `AGEGR1_TMP`

``` r

"AGEGR1_TMP" %in% names(conformed)
```

    [1] FALSE

Two boundaries worth knowing, because they are deliberate:

- **`conformance =` disposes of findings only.** Pipeline errors — above
  all a lossy coercion, where the spec says `integer` but the data
  carries fractions — abort under *every* setting (`artoo_error_type`).
  The fix is retyping the spec variable to `"float"`/`"decimal"`, never
  accepting silent truncation. The condition carries the offenders as
  data in `cnd$variables`.
- **Sorting matches SAS.** The default `na_position = "first"` orders
  missing key values before present ones, exactly as SAS `PROC SORT`
  does (and as FDA submission datasets are sorted). Set `"last"` only
  when your comparison target is R’s
  [`order()`](https://rdrr.io/r/base/order.html) / pandas / Polars.

## 5. Fan out to every deliverable

The writers return their input invisibly, so one conformed frame flows
to every format in a single pipe — losslessly, because each codec
carries the same metadata:

``` r

xpt <- tempfile(fileext = ".xpt")
json <- tempfile(fileext = ".json")
conformed |>
  write_xpt(xpt) |>
  write_json(json)
columns(json)
```

    <artoo_columns> ADSL -- 43 variables, 60 obs
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

## Where to next

- [Any-to-any
  conversion](https://vthanik.github.io/artoo/articles/convert.md) —
  moving between the formats.
- [Dates, times, and
  `--DTC`](https://vthanik.github.io/artoo/articles/dates.md) — how
  temporal values travel.
- [Common errors](https://vthanik.github.io/artoo/articles/errors.md) —
  every condition, its trigger, its fix.
