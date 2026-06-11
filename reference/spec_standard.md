# The CDISC standard a spec implements

Return the one CDISC standard the specification carries (e.g.
`"ADaMIG 1.1"`, `"SDTMIG 3.2"`). A `artoo_spec` is single-standard by
construction –
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
aborts when its sources mix standards – so this is always a scalar; `NA`
when no source named one.

## Usage

``` r
spec_standard(spec)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

## Value

*A `<character(1)>`*: the standard, or `NA` when unspecified.

## See also

[`spec_study()`](https://vthanik.github.io/artoo/reference/spec_study.md)
for the rest of the study-level metadata;
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
for how the standard is resolved.

## Examples

``` r
# ---- Example 1: the standard set at construction ----
#
# Pass the standard explicitly (or let it resolve from a P21 workbook's
# Standard column / a Define-XML study block) and read it back.
spec <- artoo_spec(
  cdisc_adam_datasets, cdisc_adam_variables,
  codelists = cdisc_codelists,
  standard = "ADaMIG 1.1"
)
spec_standard(spec)
#> [1] "ADaMIG 1.1"

# ---- Example 2: unspecified resolves to NA ----
#
# A spec built without any standard source carries NA.
bare <- artoo_spec(
  cdisc_adam_datasets, cdisc_adam_variables,
  codelists = cdisc_codelists
)
spec_standard(bare)
#> [1] "ADaMIG 1.1"
```
