# Sort keys for a dataset

Parse a dataset's sort keys into a character vector of variable names.
These keys drive the sort step of
[`apply_spec()`](https://vthanik.github.io/artoo/dev/reference/apply_spec.md)
and the `keySequence` written to each output format.

## Usage

``` r
spec_keys(spec, dataset)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

- dataset:

  *The dataset whose keys to parse.* `<character(1)>: required`.

  **Restriction:** must name a dataset in the spec.

## Value

*A character vector of key variable names*, split from the dataset's
`keys` cell (whitespace- or comma-separated). Empty when no keys are
declared.

## See also

[`spec_datasets()`](https://vthanik.github.io/artoo/dev/reference/spec_datasets.md)
for the dataset names;
[`spec_variables()`](https://vthanik.github.io/artoo/dev/reference/spec_variables.md)
for the variables a key must reference.

## Examples

``` r
# ---- Example 1: parse a dataset's sort keys ----
#
# Declare DM's keys, then read them back as the ordered vector apply_spec()
# sorts by. (STUDYID and USUBJID are real DM variables in the demo data.)
ds <- cdisc_sdtm_datasets
ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
spec <- artoo_spec(ds, cdisc_sdtm_variables, codelists = cdisc_codelists)
spec_keys(spec, "DM")
#> [1] "STUDYID" "USUBJID"
```
