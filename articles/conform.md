# Conform & validate

[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
is the heart of artoo: it conforms a raw frame to a spec — coerce,
order, sort, stamp — and never silently damages data. Validation is the
same surface read the other way:
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
and
[`check_study()`](https://vthanik.github.io/artoo/reference/check_study.md)
return every finding at once, and every abort artoo raises is a classed
condition that names its fix. This article covers both.

![A spec plus data flow into apply_spec, which scaffolds, coerces,
orders, sorts, and stamps; check_spec and check_study inspect the result
for findings.](../reference/figures/round-trip-hero.svg)

The artoo lossless round-trip, centred on apply_spec and the check
verbs.

## 1. Conform with `apply_spec()`

[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
runs the same five steps, in the same documented order — scaffold the
spec’s columns, coerce each to its CDISC data type, order to the spec,
sort by the dataset keys, stamp the metadata — and returns a frame ready
to write. A variable the spec declares but the data lacks is reported,
never fabricated as an empty column:

``` r

adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL")
```

    6 variables the spec declares are absent from the data (not added): `TRTDURD`,
    `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
    ℹ See `conformance(x)` for the findings.

Two arguments cover the common cases. `extra = "drop"` trims columns the
spec does not mention — announced, and recorded by the `extra_variable`
finding, so the drop is never silent:

``` r

adsl_lean <- apply_spec(cdisc_adsl, adam_spec, "ADSL", extra = "drop")
```

    6 variables the spec declares are absent from the data (not added): `TRTDURD`,
    `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
    ℹ See `conformance(x)` for the findings.
    Dropped 5 undeclared variables: `TRTDUR`, `DISONSDT`, `DCDECOD`, `DCREASCD`,
    and `MMSETOT`

``` r

ncol(adsl_lean) <= ncol(cdisc_adsl)
```

    [1] TRUE

`na_position` controls where missing key values sort. The default
`"first"` matches SAS `PROC SORT` (and FDA submission datasets); set
`"last"` only when your comparison target is R’s
[`order()`](https://rdrr.io/r/base/order.html):

``` r

nrow(apply_spec(cdisc_adsl, adam_spec, "ADSL", na_position = "last"))
```

    6 variables the spec declares are absent from the data (not added): `TRTDURD`,
    `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
    ℹ See `conformance(x)` for the findings.

    [1] 60

## 2. Lossless or loud

artoo’s core rule is that no operation silently damages data. A coercion
that would truncate fractions or overflow R’s 32-bit integer range
aborts with `artoo_error_type` **before** touching a value — and this
gate is independent of `conformance`, so turning conformance off does
not bypass it:

``` r

vars <- spec_variables(adam_spec)
vars$data_type[vars$variable == "AGE"] <- "integer"
strict <- artoo_spec(
  adam_spec@datasets, vars,
  codelists = adam_spec@codelists,
  study = spec_study(adam_spec)
)
raw <- cdisc_adsl
raw$AGE[1] <- raw$AGE[1] + 0.5
apply_spec(raw, strict, "ADSL", conformance = "off")
```

    Error:
    ! Coercion to the spec dataTypes would lose data.
    ✖ Integer coercion would truncate fractional values in: AGE (1).
    ℹ This gate is separate from `conformance`; `conformance = "off"` does not
      bypass it.
    ℹ To keep these values in R, set `apply_spec(on_coercion_loss = "keep")`, or
      retype the spec with `set_type()` (dataType "float" or "decimal").
    ℹ To see every finding at once, run `check_spec(x, spec, dataset)`.

You have two honest one-line exits: keep the wider source type with
`apply_spec(on_coercion_loss = "keep")` (the value is preserved and the
mismatch is left as an `integer_fraction` finding), or retype the spec
with
[`set_type()`](https://vthanik.github.io/artoo/reference/set_type.md).

## 3. See every finding, without halting

[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
stops at the first thing that would lose data; to *list* every issue
instead, ask.
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
returns all of them as a tidy frame — one row per finding, no abort:

``` r

findings <- check_spec(cdisc_adsl, adam_spec, "ADSL")
findings
```

    <artoo_findings> ADSL: 0 errors, 11 warnings, 15 notes

    Warnings
    --------
    [missing_permissible] Permissible spec variable 'TRTDURD' is absent from the data.  (ADSL.TRTDURD)
    [missing_permissible] Permissible spec variable 'DISONDT' is absent from the data.  (ADSL.DISONDT)
    [missing_permissible] Permissible spec variable 'EOSSTT' is absent from the data.  (ADSL.EOSSTT)
    [missing_permissible] Permissible spec variable 'DCSREAS' is absent from the data.  (ADSL.DCSREAS)
    [missing_permissible] Permissible spec variable 'EOSDISP' is absent from the data.  (ADSL.EOSDISP)
    [missing_permissible] Permissible spec variable 'MMS1TSBL' is absent from the data.  (ADSL.MMS1TSBL)
    [extra_variable] Column 'TRTDUR' is not declared in the spec.  (ADSL.TRTDUR)
    [extra_variable] Column 'DISONSDT' is not declared in the spec.  (ADSL.DISONSDT)
    [extra_variable] Column 'DCDECOD' is not declared in the spec.  (ADSL.DCDECOD)
    [extra_variable] Column 'DCREASCD' is not declared in the spec.  (ADSL.DCREASCD)
    [extra_variable] Column 'MMSETOT' is not declared in the spec.  (ADSL.MMSETOT)

    Notes
    -----
    [type_mismatch] 'TRT01PN' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.TRT01PN)
    [type_mismatch] 'TRT01AN' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.TRT01AN)
    [type_mismatch] 'TRTSDT' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.TRTSDT)
    [type_mismatch] 'TRTEDT' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.TRTEDT)
    [type_mismatch] 'AGE' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.AGE)
    [type_mismatch] 'AGEGR1N' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.AGEGR1N)
    [type_mismatch] 'RACEN' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.RACEN)
    [label_match] 'DISCONFL' label 'Did the Subject Discontinue the Study?' differs from the spec label 'Subject Discontinued Study Flag'.  (ADSL.DISCONFL)
    [label_match] 'DSRAEFL' label 'Discontinued due to AE?' differs from the spec label 'Subject Discontinued due to AE Flag'.  (ADSL.DSRAEFL)
    [label_match] 'DTHFL' label 'Subject Died?' differs from the spec label 'Subject Death Flag'.  (ADSL.DTHFL)
    [codelist_membership_extensible] 'BMIBLGR1' has 1 value(s) outside extensible codelist 'CL.BMICAT': >=30.  (ADSL.BMIBLGR1)
    [type_mismatch] 'EDUCLVL' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.EDUCLVL)
    [type_mismatch] 'VISIT1DT' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.VISIT1DT)
    [type_mismatch] 'VISNUMEN' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.VISNUMEN)
    [type_mismatch] 'RFENDT' is stored as double but the spec dataType 'integer' wants integer.  (ADSL.RFENDT)

The same report rides along on a conformed result under the default
`conformance = "warn"`; read it back with
[`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md):

``` r

nrow(conformance(adsl))
```

    [1] 12

Scaling to a whole study is one call:
[`check_study()`](https://vthanik.github.io/artoo/reference/check_study.md)
takes a named list of datasets and returns the same shape, so “is my
study submittable?” has a single answer.

``` r

nrow(check_study(adam_spec, list(ADSL = cdisc_adsl)))
```

    [1] 26

## 4. Scope the checks

[`artoo_checks()`](https://vthanik.github.io/artoo/reference/artoo_checks.md)
toggles each conformance dimension on or off; pass the result to
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
/
[`check_study()`](https://vthanik.github.io/artoo/reference/check_study.md)
to narrow a run to what you care about (here, everything except the
type-mismatch note):

``` r

ck <- artoo_checks(type_mismatch = FALSE)
nrow(check_spec(cdisc_adsl, adam_spec, "ADSL", checks = ck))
```

    [1] 15

## 5. The error family

Every abort artoo raises carries a class of the form
`artoo_error_<kind>` (plus `artoo_error` and `artoo_condition`, so one
`tryCatch(artoo_error = )` catches them all), and the data-protection
conditions carry their evidence as data, so a qualification harness can
assert on `cnd$variables` / `cnd$findings` rather than match message
text. The kinds, each triggered live:

`artoo_error_input` — the call is malformed (here, an unknown dataset):

``` r

apply_spec(cdisc_dm, sdtm_spec, "NOPE")
```

    Error:
    ! `dataset` must be one of the spec's datasets.
    ✖ "NOPE" is not in the spec.
    ℹ Available: "TS", "DM", "VS", and "SUPPDM".

`artoo_error_conformance` — `apply_spec(conformance = "abort")` met
error-severity findings:

``` r

dm <- cdisc_dm
dm$SEX[1] <- "X9"
apply_spec(dm, sdtm_spec, "DM", conformance = "abort")
```

    Error:
    ! Data does not conform to the spec for "DM".
    ✖ 'SEX' has 1 value(s) outside codelist 'CL.SEX': X9.

`artoo_error_codelist` —
[`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md)
met a value outside the codelist’s terms (pass `no_match = "keep"` /
`"na"` to carry it through):

``` r

decode_column(dm, sdtm_spec, "DM", from = "SEX", to = "SEXDECD")
```

    Error:
    ! Values in `SEX` are not in codelist "CL.SEX".
    ✖ Unmatched: "X9".
    ℹ Set `no_match = "keep"` or `"na"` to allow them.

`artoo_error_codec` — the bytes cannot travel (an invalid-UTF-8 value
for Dataset-JSON); re-read with the true `encoding=`, or set an
`on_invalid` policy on the writer:

``` r

clean <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
clean$USUBJID[1] <- rawToChar(as.raw(c(0x63, 0xE9)))
write_json(clean, tempfile(fileext = ".json"))
```

    Error in `write_json()`:
    ! Cannot encode 1 value as UTF-8.
    ✖ Invalid bytes (hex-escaped): "c<e9>".
    ℹ Re-read the source with the correct `encoding`, or set `on_invalid`.

(The remaining kind, `artoo_error_spec`, fires at spec construction when
a slot references an unknown dataset or codelist, mixes standards, or
duplicates a definition.)

## Where to next

- [Specifications](https://vthanik.github.io/artoo/articles/specs.md) —
  build, inspect, and repair the spec this verb consumes.
- [Formats & lossless
  conversion](https://vthanik.github.io/artoo/articles/convert.md) —
  write the conformed frame to any format, and the qualification
  evidence behind “lossless”.
- [Recipes](https://vthanik.github.io/artoo/articles/recipes.md) —
  conform inside an end-to-end ADaM and SDTM build.
- [Get started](https://vthanik.github.io/artoo/articles/artoo.md) — the
  round-trip from the top.
