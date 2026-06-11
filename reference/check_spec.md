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
# ---- Example 1: a conformed dataset has no findings ----
#
# apply_spec() scaffolds, coerces, and orders to spec; checking the result
# against the same spec returns zero rows.
adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off")
#> Scaffolded 6 variables: `TRTDURD`, `DISONDT`, `EOSSTT`, `DCSREAS`,
#> `EOSDISP`, and `MMS1TSBL`
nrow(check_spec(adsl, adam_spec, "ADSL"))
#> [1] 6

# ---- Example 2: raw data surfaces divergences ----
#
# Checking a raw frame with an undeclared column flags the extras.
raw <- cdisc_adsl
raw$NOTASPEC <- 1
head(check_spec(raw, adam_spec, "ADSL")[, c("check", "variable", "severity")])
#>                 check variable severity
#> 1 missing_permissible  TRTDURD  warning
#> 2 missing_permissible  DISONDT  warning
#> 3 missing_permissible   EOSSTT  warning
#> 4 missing_permissible  DCSREAS  warning
#> 5 missing_permissible  EOSDISP  warning
#> 6 missing_permissible MMS1TSBL  warning
```
