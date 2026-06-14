# Recipes

These are the everyday programming loops a clinical programmer runs — an
ADaM analysis dataset, an SDTM domain, a codelist decode, the temporal
shapes — each rendered **live** below from the bundled demo data, so
what you see is exactly what the code produces. Every recipe ends on a
conformed result; the closing line shows how to **ship it** to any
deliverable, just by changing the extension.

![A spec plus data go through apply_spec, write to a file, and read back
identical, closing a lossless round-trip
loop.](../reference/figures/round-trip-hero.svg)

The artoo lossless round-trip, the loop every recipe walks.

## An ADaM build: ADSL

A real derivation program accumulates working columns the spec never
declares — here an age-group cut. Those are “extras”; `extra = "drop"`
trims them to exactly the spec’s columns, recorded by the
`extra_variable` finding so the drop is never silent.
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
then coerces, orders, sorts, and stamps:

``` r

adsl_raw <- cdisc_adsl
adsl_raw$AGEGR1_TMP <- cut(
  adsl_raw$AGE,
  breaks = c(-Inf, 64, 74, Inf),
  labels = c("<65", "65-74", ">=75")
)
adsl_raw$AGEGR1 <- as.character(adsl_raw$AGEGR1_TMP)

adsl <- apply_spec(adsl_raw, adam_spec, "ADSL", extra = "drop")
```

    Warning: 1 conformance error for "ADSL".
    ℹ Run `conformance(x)` on the returned frame to see every finding.

``` r

columns(adsl)
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

``` r

write_xpt(adsl, "adsl.xpt") # ship: or .json / .parquet / .rds
```

## An SDTM build: DM

The pipeline is identical — only the spec and the data change. Assemble
the domain (with a QC temporary), conform, then read the result back as
a one-line inventory with
[`members()`](https://vthanik.github.io/artoo/reference/members.md):

``` r

dm_raw <- cdisc_dm
dm_raw$AGE_CHECK <- dm_raw$AGE >= 18

dm <- apply_spec(dm_raw, sdtm_spec, "DM", extra = "drop", conformance = "off")

json <- tempfile(fileext = ".json")
write_json(dm, json)
members(json)
```

    <artoo_members> 1 dataset
    file                   member  label         records  variables  format
    file1ecb17104ac3.json  DM      Demographics  60       15         json

``` r

write_xpt(dm, "dm.xpt") # ship: or .json / .parquet / .rds
```

## Codelists: decode in either direction

[`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md)
reads the codelist a variable is bound to in the spec and maps in either
direction — here, deriving the numeric `RACEN` code from the `RACE`
decode (`direction = "to_code"`):

``` r

adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off")
coded <- decode_column(
  adsl, adam_spec, "ADSL",
  from = "RACE", to = "RACEN", direction = "to_code"
)
unique(coded[, c("RACE", "RACEN")])
```

                                   RACE RACEN
    1                             WHITE     1
    20        BLACK OR AFRICAN AMERICAN     2
    24 AMERICAN INDIAN OR ALASKA NATIVE     6

A value outside the codelist’s terms aborts (`artoo_error_codelist`)
unless you pass `no_match = "keep"` / `"na"`.

## Dates, times, and `--DTC`

Clinical dates travel in two shapes, and artoo keeps the distinction
explicit through `dataType`, `targetDataType`, and `displayFormat`.
**Scope note:** this is about *carriage* — partial-date imputation is an
analysis decision your SAP owns; artoo never imputes.

An SDTM `--DTC` variable typed `date` is ISO 8601 text by the CDISC
storage rule, so it stays character through the pipeline, partial values
included (`"2024-03"` is a legal ISO date, and padding it would be
imputation by stealth):

``` r

dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
class(dm$RFSTDTC)
```

    [1] "character"

A variable typed `date` with no `targetDataType` realizes to an R `Date`
in memory:

``` r

adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off")
class(adsl$DISONSDT)
```

    [1] "Date"

The ADaM numeric-date convention is the other shape: a variable carried
as an `integer` SAS-epoch day count, with a `displayFormat` (`date9.`)
telling SAS how to render it. `TRTSDT` is one, and the format rides in
the metadata:

``` r

class(adsl$TRTSDT)
```

    [1] "integer"

``` r

p <- tempfile(fileext = ".json")
write_json(adsl, p)
get_meta(read_json(p))@columns$TRTSDT[c("dataType", "displayFormat")]
```

    $dataType
    [1] "integer"

    $displayFormat
    [1] "date9."

SAS `TIME` values import as `hms` (seconds since midnight), so values
past 24 hours, negative values, and fractional seconds all survive:

``` r

hms::as_hms(30615)
```

    08:30:15

Either date shape round-trips byte-faithfully — the SAS-epoch
(1960-01-01) versus R-epoch conversion happens inside the codecs, never
in your code:

``` r

identical(read_json(p)$TRTSDT, adsl$TRTSDT)
```

    [1] TRUE

## Where to next

- [Specifications](https://vthanik.github.io/artoo/articles/specs.md) —
  the spec each recipe starts from.
- [Conform &
  validate](https://vthanik.github.io/artoo/articles/conform.md) —
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
  and the findings in depth.
- [Formats & lossless
  conversion](https://vthanik.github.io/artoo/articles/convert.md) — the
  round trips these ship lines rely on.
- [Get started](https://vthanik.github.io/artoo/articles/artoo.md) — the
  round-trip from the top.
