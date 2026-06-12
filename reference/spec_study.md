# Study-level metadata

Return the study-level metadata row, or a single field from it. Holds
the canonical study fields (`study_name`, `study_description`,
`protocol_name` — every source spelling is canonicalised by
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md))
plus any other study-scoped fields a source provides (the CDISC standard
lives on its own property — see
[`spec_standard()`](https://vthanik.github.io/artoo/reference/spec_standard.md)).

## Usage

``` r
spec_study(spec, field = NULL)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

- field:

  *Return one field instead of the row.* `<character(1)> | NULL`. When
  `NULL` (default) the whole study data frame is returned.

  **Restriction:** a non-`NULL` `field` must be a column of the study
  table; an unknown field aborts with `artoo_error_input`.

## Value

*The study data frame* (one row), or the value of one `field`. The
canonical fields are `study_name`, `study_description`, and
`protocol_name` — every source spelling is canonicalised to these by
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
— plus any other field the source carried verbatim (e.g.
`define_version` from a Define-XML read).

## See also

[`spec_datasets()`](https://vthanik.github.io/artoo/reference/spec_datasets.md)
for the datasets the study scopes;
[`spec_standard()`](https://vthanik.github.io/artoo/reference/spec_standard.md)
for the spec's CDISC standard.

## Examples

``` r
# ---- Example 1: the whole study row, then one field ----
#
# spec_study() with no field returns the study-level table; pass a field
# name to pull a single value such as the study name.
spec <- artoo_spec(
  cdisc_adam_datasets, cdisc_adam_variables,
  codelists = cdisc_codelists,
  study = data.frame(study_name = "CDISCPILOT01")
)
spec_study(spec)
#>     study_name
#> 1 CDISCPILOT01
spec_study(spec, "study_name")
#> [1] "CDISCPILOT01"
```
