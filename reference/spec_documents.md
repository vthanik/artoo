# Document references in a spec

Return the document references a specification carries. Methods and
comments point to these by `document_id`.

## Usage

``` r
spec_documents(spec)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

## Value

*A data frame of document metadata* (`document_id`, `title`, `href`),
one row per document. Empty when the spec defines none.

## See also

[`spec_methods()`](https://vthanik.github.io/artoo/reference/spec_methods.md),
[`spec_comments()`](https://vthanik.github.io/artoo/reference/spec_comments.md),
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md).

## Examples

``` r
# ---- Example 1: the documents a spec defines ----
#
# Build a spec with one document reference and read it back.
spec <- artoo_spec(
  data.frame(dataset = "ADSL"),
  data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
  documents = data.frame(
    document_id = "SAP",
    title = "Statistical Analysis Plan",
    stringsAsFactors = FALSE
  )
)
spec_documents(spec)
#>   document_id                     title href
#> 1         SAP Statistical Analysis Plan <NA>
```
