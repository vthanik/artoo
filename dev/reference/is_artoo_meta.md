# Test for a artoo_meta object

Report whether an object is a `artoo_meta` — the CDISC-shaped metadata a
conformed dataset carries through the artoo workflow (spec -\>
apply_spec -\> read\_/write\_).
[`get_meta()`](https://vthanik.github.io/artoo/dev/reference/get_meta.md)
returns one; this is the type guard before you inspect its `@dataset`
and `@columns` slots.

## Usage

``` r
is_artoo_meta(x)
```

## Arguments

- x:

  *Object to test.* `<any>`.

## Value

*A `<logical(1)>`*: `TRUE` when `x` is a `artoo_meta`, else `FALSE`.

## See also

[`get_meta()`](https://vthanik.github.io/artoo/dev/reference/get_meta.md)
and
[`set_meta()`](https://vthanik.github.io/artoo/dev/reference/set_meta.md)
to read and attach metadata.

## Examples

``` r
# ---- Example 1: guard before inspecting metadata ----
#
# get_meta() yields a artoo_meta; is_artoo_meta() confirms the type before
# you reach into its slots.
spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)
adsl <- apply_spec(cdisc_adsl, spec, "ADSL")
meta <- get_meta(adsl)
is_artoo_meta(meta)
#> [1] TRUE

# ---- Example 2: a bare data frame carries no meta object ----
#
# The raw frame itself is not a artoo_meta — only the object get_meta()
# returns is.
is_artoo_meta(cdisc_adsl)
#> [1] FALSE
```
