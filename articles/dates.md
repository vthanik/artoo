# Dates, times, and –DTC

Clinical dates travel in two shapes — ISO 8601 text in SDTM (`--DTC`)
and numeric SAS dates in ADaM (`ADT`, `TRTSDT`) — and most tooling pain
comes from conflating them. artoo keeps the distinction explicit through
three metadata fields: `dataType`, `targetDataType`, and
`displayFormat`. This article shows how each shape is represented,
realized in R, and round-tripped. **Scope note:** this is about
*carriage*. Partial-date imputation is an analysis decision your SAP
owns; artoo never imputes.

## 1. ISO text stays text (`--DTC`)

A spec variable typed `date`/`datetime` with **no** `targetDataType` is,
by the CDISC storage rule, ISO 8601 text — the SDTM `--DTC` shape.
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
leaves it as character, partial values included, because `"2024-03"` is
a legal ISO date and truncating or padding it would be imputation by
stealth:

``` r

dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
```

    Scaffolded 1 variable: `BRTHDTC`

``` r

class(dm$BRTHDTC)
```

    [1] "character"

## 2. Typed dates realize to R classes

A variable whose `dataType` is `date`, `datetime`, or `time` realizes to
the matching R class — `Date`, `POSIXct` (UTC),
[`hms::hms`](https://hms.tidyverse.org/reference/hms.html) — in memory,
both through
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
and on every read:

``` r

adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off")
```

    Scaffolded 6 variables: `TRTDURD`, `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`,
    and `MMS1TSBL`

``` r

class(adsl$TRTSDT)
```

    [1] "integer"

How the value travels *in the file* is the spec’s call: with no
`targetDataType` the exchange form is the ISO 8601 string; declaring
`targetDataType = "integer"` opts into SAS-epoch numbers (the ADaM
numeric-date convention). Either way, the SAS epoch (1960-01-01) versus
R epoch (1970-01-01) conversion — 3653 days — happens inside the codecs;
you never shift values yourself.

## 3. Times are `hms`

SAS `TIME` values import as
[`hms::hms`](https://hms.tidyverse.org/reference/hms.html) (seconds
since midnight), which prints as a clock time but is numeric underneath,
so elapsed times past 24 hours, negative values, and fractional seconds
all survive:

``` r

hms::as_hms(30615)
```

    08:30:15

## 4. Round trips preserve the exchange form

On write, each codec emits the exchange form the metadata dictates: ISO
strings for text-shaped temporals, SAS-epoch numbers when
`targetDataType` says numeric, with `displayFormat` (`DATE9.`,
`DATETIME20.`) riding along for SAS consumers:

``` r

p <- tempfile(fileext = ".json")
write_json(adsl, p)
meta <- get_meta(read_json(p))
meta@columns$TRTSDT[c("dataType", "displayFormat")]
```

    $dataType
    [1] "integer"

    $displayFormat
    [1] "date9."

``` r

identical(read_json(p)$TRTSDT, adsl$TRTSDT)
```

    [1] TRUE

## Where to next

- [An end-to-end ADaM
  build](https://vthanik.github.io/artoo/articles/adam-build.md) — the
  full loop these columns live in.
- [Common errors](https://vthanik.github.io/artoo/articles/errors.md) —
  including what happens when a temporal value cannot be realized.
