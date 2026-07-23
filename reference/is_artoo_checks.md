# Test for a artoo_checks control

Report whether an object is a `artoo_checks` control built by
[`artoo_checks()`](https://vthanik.github.io/artoo/reference/artoo_checks.md).
Use it to guard a `checks` argument before threading it into
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
or
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md).

## Usage

``` r
is_artoo_checks(x)
```

## Arguments

- x:

  *Object to test.* `<any>`.

## Value

*A `<logical(1)>`*: `TRUE` when `x` is a `artoo_checks`.

## See also

[`artoo_checks()`](https://vthanik.github.io/artoo/reference/artoo_checks.md)
to build one.

## Examples

``` r
# ---- Example 1: confirm a control before reusing it ----
#
# is_artoo_checks() distinguishes a real control from a bare list of flags.
is_artoo_checks(artoo_checks())
#> [1] TRUE
is_artoo_checks(list(missing_variable = TRUE))
#> [1] FALSE
```
