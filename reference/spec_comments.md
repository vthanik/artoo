# Comment definitions in a spec

Return the comment definitions a specification carries. Datasets,
variables, value-level rows, and codelists reference these by
`comment_id`;
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md)
checks the references resolve and each referenced comment has a body.

## Usage

``` r
spec_comments(spec)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

## Value

*A data frame of comment metadata*, one row per comment, with all four
columns: `comment_id`, `description`, `document_id`, `pages`. Empty when
the spec defines no comments.

## See also

[`spec_methods()`](https://vthanik.github.io/artoo/reference/spec_methods.md),
[`spec_documents()`](https://vthanik.github.io/artoo/reference/spec_documents.md),
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md).

## Examples

``` r
# ---- Example 1: the comments a spec defines ----
#
# Build a spec with one comment and read it back.
spec <- artoo_spec(
  data.frame(dataset = "ADSL"),
  data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
  comments = data.frame(
    comment_id = "C.AGE",
    description = "Age in years at informed consent.",
    stringsAsFactors = FALSE
  )
)
spec_comments(spec)
#>   comment_id                       description document_id pages
#> 1      C.AGE Age in years at informed consent.        <NA>  <NA>
```
