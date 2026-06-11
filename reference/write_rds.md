# Write a dataset to rds

Write a data frame to an R `.rds` file, preserving its `artoo_meta`. A
thin wrapper over
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
with `format = "rds"`; the rds carries the metadata both as live R
attributes and as the language-agnostic `metadata_json` string, so
[`read_rds()`](https://vthanik.github.io/artoo/reference/read_rds.md)
restores it exactly.

## Usage

``` r
write_rds(x, path, encoding = NULL)
```

## Arguments

- x:

  *The dataset to write.* `<data.frame>: required`.

- path:

  *Destination `.rds` path.* `<character(1)>: required`.

- encoding:

  *Source charset to record.* `<character(1)> | NULL`. rds is R-native
  and faithful: strings are saved as-is, never transcoded. `encoding`
  only records the data's original charset in the `artoo_meta`, so a
  later
  [`write_xpt()`](https://vthanik.github.io/artoo/reference/write_xpt.md)
  can reproduce the source bytes. `NULL` (default) leaves the recorded
  encoding untouched.

  **Tip:** any SAS or IANA spelling listed by
  [`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md)
  is accepted.

## Value

*The input `x`*, invisibly, so a write can sit mid-pipeline.

## See also

[`read_rds()`](https://vthanik.github.io/artoo/reference/read_rds.md)
for the inverse;
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)

# ---- Example 1: write a conformed dataset to rds ----
#
# apply_spec() attaches the metadata; write_rds() carries it into the file.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".rds")
write_rds(adsl, path)

# ---- Example 2: round-trip and confirm the metadata survived ----
#
# Reading it back yields an identical artoo_meta.
back <- read_rds(path)
identical(get_meta(back)@columns, get_meta(adsl)@columns)
#> [1] TRUE
```
