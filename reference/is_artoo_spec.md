# Test for a artoo_spec object

Report whether an object is a `artoo_spec` — the validated CDISC
specification that drives the artoo workflow (spec -\> apply_spec -\>
read\_/write\_).
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
builds one; this is the type guard before you pass it to
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
or reach into it with the spec accessors.

## Usage

``` r
is_artoo_spec(x)
```

## Arguments

- x:

  *Object to test.* `<any>`.

## Value

*A `<logical(1)>`*: `TRUE` when `x` is a `artoo_spec`, else `FALSE`.

## See also

[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
to build one;
[`is_artoo_meta()`](https://vthanik.github.io/artoo/reference/is_artoo_meta.md)
for the metadata guard.

## Examples

``` r
# ---- Example 1: guard a built specification ----
#
# artoo_spec() assembles and validates a spec; is_artoo_spec() confirms the
# type before you drive apply_spec() with it.
spec <- artoo_spec(cdisc_sdtm_datasets, cdisc_sdtm_variables, codelists = cdisc_codelists)
is_artoo_spec(spec)
#> [1] TRUE

# ---- Example 2: an ordinary object is not a spec ----
#
# Any non-artoo_spec value — a bare data frame, say — returns FALSE.
is_artoo_spec(cdisc_dm)
#> [1] FALSE
```
