# Check a dataset against its spec

Compare a data frame to one dataset's specification and report where
they diverge. This is the data-conformance check at the end of the artoo
workflow (spec -\> apply_spec -\> check_spec): it reuses the metadata
the spec already carries (variables, types, lengths, codelists, keys).
It is distinct from
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md),
which checks the spec's own internal integrity rather than the data.
Both report findings keyed to the same open rule catalog.

## Usage

``` r
check_spec(
  x,
  spec,
  dataset,
  decode = c("none", "to_decode", "to_code"),
  checks = NULL
)
```

## Arguments

- x:

  *The data frame to check.* `<data.frame>: required`. Typically the
  output of
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md),
  but any frame works.

- spec:

  *The specification to check against.* `<artoo_spec>: required`.

- dataset:

  *The dataset whose rules apply.* `<character(1)>: required`.

  **Restriction:** must name a dataset in `spec` (see
  [`spec_datasets()`](https://vthanik.github.io/artoo/reference/spec_datasets.md)).

- decode:

  *Which codelist column membership is checked against.*
  `<character(1)>`. One of `"none"` (default), `"to_decode"`, or
  `"to_code"`.

- checks:

  *Which conformance dimensions to evaluate.* `<artoo_checks> | NULL`.
  When `NULL` (default) every dimension runs; build a control with
  [`artoo_checks()`](https://vthanik.github.io/artoo/reference/artoo_checks.md)
  to disable some.

## Value

*A findings data frame* with columns `check`, `dimension`, `severity`
(`"error"`, `"warning"`, or `"note"`), `dataset`, `variable`, and
`message`, one row per divergence. Zero rows means the data conforms.

## Details

**Findings, not enforcement.** `check_spec()` never modifies data; it
returns every divergence it finds.
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
runs it and decides what to do via its `conformance` argument (warn,
abort, off). The dimensions checked are: missing variables (split into
mandatory, an error, and permissible, a warning), extra variables (data
column the spec does not declare), type mismatch, ISO 8601 validity of
character date/datetime/time values (CDISC partials pass; `"12NOV2019"`
does not), fractional values and 32-bit overflow under an `integer`
dataType (both would corrupt data at coercion), character length
overflow, the hard 200-byte XPORT v5 / FDA character limit, codelist
membership, label drift against the spec, key uniqueness, and
displayFormat validity.

**Decode-aware membership.** `decode` selects which codelist column the
data is checked against, matching
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)'s
decode step: `"none"`/`"to_code"` check against the codelist `term`s,
`"to_decode"` against the `decode`s.
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
threads its own `decode` through, so a decoded column is not wrongly
flagged.

## See also

[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
which runs this;
[`artoo_checks()`](https://vthanik.github.io/artoo/reference/artoo_checks.md)
to select dimensions;
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md)
for spec integrity.

## Examples

``` r
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)

# ---- Example 1: a conformed dataset has no findings ----
#
# apply_spec() scaffolds, coerces, and orders to spec; checking the result
# against the same spec returns zero rows.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
nrow(check_spec(adsl, spec, "ADSL"))
#> [1] 0

# ---- Example 2: raw data surfaces divergences ----
#
# Checking a frame with an undeclared column flags it as an extra variable.
raw <- cdisc_adsl
raw$NOTASPEC <- 1
check_spec(raw, spec, "DM")[, c("check", "variable", "severity")]
#>               check variable severity
#> 1  missing_variable   DOMAIN    error
#> 2  missing_variable RFXSTDTC    error
#> 3  missing_variable RFXENDTC    error
#> 4  missing_variable  RFICDTC    error
#> 5  missing_variable RFPENDTC    error
#> 6  missing_variable   DTHDTC    error
#> 7  missing_variable    ARMCD    error
#> 8  missing_variable ACTARMCD    error
#> 9  missing_variable   ACTARM    error
#> 10 missing_variable  COUNTRY    error
#> 11 missing_variable    DMDTC    error
#> 12 missing_variable     DMDY    error
#> 13   extra_variable  SITEGR1  warning
#> 14   extra_variable   TRT01P  warning
#> 15   extra_variable  TRT01PN  warning
#> 16   extra_variable   TRT01A  warning
#> 17   extra_variable  TRT01AN  warning
#> 18   extra_variable   TRTSDT  warning
#> 19   extra_variable   TRTEDT  warning
#> 20   extra_variable   TRTDUR  warning
#> 21   extra_variable    AVGDD  warning
#> 22   extra_variable  CUMDOSE  warning
#> 23   extra_variable   AGEGR1  warning
#> 24   extra_variable  AGEGR1N  warning
#> 25   extra_variable    RACEN  warning
#> 26   extra_variable    SAFFL  warning
#> 27   extra_variable    ITTFL  warning
#> 28   extra_variable    EFFFL  warning
#> 29   extra_variable  COMP8FL  warning
#> 30   extra_variable COMP16FL  warning
#> 31   extra_variable COMP24FL  warning
#> 32   extra_variable DISCONFL  warning
#> 33   extra_variable  DSRAEFL  warning
#> 34   extra_variable    BMIBL  warning
#> 35   extra_variable BMIBLGR1  warning
#> 36   extra_variable HEIGHTBL  warning
#> 37   extra_variable WEIGHTBL  warning
#> 38   extra_variable  EDUCLVL  warning
#> 39   extra_variable DISONSDT  warning
#> 40   extra_variable   DURDIS  warning
#> 41   extra_variable DURDSGR1  warning
#> 42   extra_variable VISIT1DT  warning
#> 43   extra_variable VISNUMEN  warning
#> 44   extra_variable   RFENDT  warning
#> 45   extra_variable  DCDECOD  warning
#> 46   extra_variable DCREASCD  warning
#> 47   extra_variable  MMSETOT  warning
#> 48   extra_variable NOTASPEC  warning
#> 49      label_match    DTHFL     note
```
