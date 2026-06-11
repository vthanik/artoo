# Dataset names in a spec

List the datasets a specification defines. The result is the set of
names you pass as the `dataset` argument to the other accessors and to
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md).

## Usage

``` r
spec_datasets(spec)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

## Value

*A character vector of dataset names*, de-duplicated and with `NA`s
dropped. Empty when the spec has no datasets.

## See also

[`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md)
for one dataset's variables;
[`spec_keys()`](https://vthanik.github.io/artoo/reference/spec_keys.md)
for its sort keys.

## Examples

``` r
# ---- Example 1: the datasets the pilot ADaM spec defines ----
#
# Build the spec from the bundled CDISC-pilot tables and list its
# datasets -- the names you pass to the other accessors.
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
spec_datasets(spec)
#> [1] "ADSL" "DM"  
```
