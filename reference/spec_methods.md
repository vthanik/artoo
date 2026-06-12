# Derivation methods in a spec

Return the method definitions a specification carries. Variables and
value-level rows reference these by `method_id`;
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md)
checks that every reference resolves and that each referenced method is
complete (has a description).

## Usage

``` r
spec_methods(spec)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

## Value

*A data frame of method metadata*, one row per method, with all eight
columns: `method_id`, `description`, `name`, `type`,
`expression_context`, `expression_code`, `document_id`, `pages`. Empty
when the spec defines no methods.

## See also

[`spec_comments()`](https://vthanik.github.io/artoo/reference/spec_comments.md),
[`spec_documents()`](https://vthanik.github.io/artoo/reference/spec_documents.md),
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md).

## Examples

``` r
# ---- Example 1: the methods a spec defines ----
#
# Build a spec with one derivation method and read it back.
spec <- artoo_spec(
  data.frame(dataset = "ADSL"),
  data.frame(dataset = "ADSL", variable = "AGEGR1", data_type = "string"),
  methods = data.frame(
    method_id = "MT.AGEGR1",
    description = "Age group from AGE.",
    stringsAsFactors = FALSE
  )
)
spec_methods(spec)
#>   method_id         description name type expression_context
#> 1 MT.AGEGR1 Age group from AGE. <NA> <NA>               <NA>
#>   expression_code document_id pages
#> 1            <NA>        <NA>  <NA>
```
