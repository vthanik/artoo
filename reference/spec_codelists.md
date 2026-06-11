# Codelist terms

Return the controlled-terminology terms and decodes a spec carries: one
codelist's terms when `codelist_id` names it, or the full `codelists`
slot when `codelist_id` is `NULL`. Use it to inspect the values a coded
variable is allowed to take before applying the spec. Mirrors the
[`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md)
filter pattern.

## Usage

``` r
spec_codelists(spec, codelist_id = NULL)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

- codelist_id:

  *The codelist to return.* `<character(1)> | NULL`. When `NULL`
  (default) the whole codelists table is returned.

  **Restriction:** a non-`NULL` id must name a codelist present in the
  spec's `codelists` slot; an unknown id aborts with
  `artoo_error_input`.

## Value

*A data frame of codelist terms*, one row per term: every term when
`codelist_id` is `NULL`, else the named codelist's terms. Columns:

- `codelist_id` – the codelist identifier variables reference.

- `term` – the submission value (what conformed data carries).

- `decode` – the human-readable decoded value.

- `order` – display order within the codelist.

- `extended` – `TRUE` marks an extensible codelist (sponsor terms
  allowed; non-members downgrade to notes in
  [`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)).

- `comment_id` – reference into the comments slot.

## See also

[`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md)
for which variables reference a codelist.

## Examples

``` r
# ---- Example 1: the terms behind a coded variable ----
#
# SEX is coded against C66731; spec_codelists() returns the terms and their
# decodes that apply_spec() will enforce or decode.
spec <- artoo_spec(
  cdisc_adam_datasets, cdisc_adam_variables,
  codelists = cdisc_codelists
)
spec_codelists(spec, "C66731")
#>   codelist_id             term           decode order extended
#> 1      C66731                F           Female     1       NA
#> 2      C66731                M             Male     2       NA
#> 3      C66731                U          Unknown     3       NA
#> 4      C66731 UNDIFFERENTIATED Undifferentiated     4       NA
#>   comment_id
#> 1       <NA>
#> 2       <NA>
#> 3       <NA>
#> 4       <NA>

# ---- Example 2: the whole codelists table ----
#
# Called with no id, it returns every term across every codelist.
head(spec_codelists(spec))
#>   codelist_id             term           decode order extended
#> 1      C66731                F           Female     1       NA
#> 2      C66731                M             Male     2       NA
#> 3      C66731                U          Unknown     3       NA
#> 4      C66731 UNDIFFERENTIATED Undifferentiated     4       NA
#>   comment_id
#> 1       <NA>
#> 2       <NA>
#> 3       <NA>
#> 4       <NA>
```
