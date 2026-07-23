# Write a dataset to Apache Parquet

Serialize a data frame to an Apache Parquet (`.parquet`) file, storing
the data natively while preserving the full `artoo_meta` as a
CDISC-shaped sidecar in the file's key-value metadata. The emit end of
the artoo workflow (spec -\> apply_spec -\> write_parquet); a thin
wrapper over
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
with `format = "parquet"`. Requires the lightweight `nanoparquet`
package.

## Usage

``` r
write_parquet(
  x,
  path,
  encoding = NULL,
  on_invalid = c("error", "translit", "fold", "replace", "ignore"),
  compression = "snappy"
)
```

## Arguments

- x:

  *The dataset to write.* `<data.frame>: required`. Typically the output
  of
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md),
  carrying `artoo_meta`.

- path:

  *Destination `.parquet` path.* `<character(1)>: required`.

- encoding:

  *Source charset to record.* `<character(1)> | NULL`. The parquet bytes
  are always written as UTF-8 (the format's STRING type is UTF-8 by
  spec); `encoding` only records the data's original charset in the
  `artoo_meta`, so a later
  [`write_xpt()`](https://vthanik.github.io/artoo/reference/write_xpt.md)
  can reproduce the source bytes. `NULL` (default) leaves the recorded
  encoding untouched.

  **Tip:** any SAS or IANA spelling listed by
  [`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md)
  is accepted.

- on_invalid:

  *Policy for values that are not valid UTF-8.*
  `<character(1)>: default "error"`. One of `"error"` (abort with
  `artoo_error_codec`), `"replace"` (substitute `?` and warn with
  `artoo_warning_encoding`), `"ignore"` (drop the invalid bytes), or
  `"translit"` / `"fold"` (accepted for pipeline symmetry; behave as
  `"error"` here, since a byte-level invalidity has no character fold).
  See
  [`write_json()`](https://vthanik.github.io/artoo/reference/write_json.md)
  for when this fires; parquet STRING bytes are UTF-8 by spec, exactly
  like Dataset-JSON.

- compression:

  *Column compression codec.* `<character(1)>: default "snappy"`. One
  of:

  - `"snappy"` (default) — fast, the parquet ecosystem default.

  - `"gzip"` — smaller files, slower.

  - `"zstd"` — the best size/speed trade-off where supported.

  - `"uncompressed"` — raw pages.

## Value

*The input `x`*, invisibly, so a write can sit mid-pipeline.

## Details

**Metadata where plain Parquet has none.** A bare nanoparquet/arrow file
drops labels, formats, and codelists; `write_parquet()` embeds the
complete `artoo_meta` as a single Dataset-JSON-shaped string under the
`metadata_json` key, so
[`read_parquet()`](https://vthanik.github.io/artoo/reference/read_parquet.md)
restores every CDISC attribute. The same string is what a `.json` file
or an rds carries, so conversion between any two formats stays lossless.
A reader without artoo still opens the data and can see the
`metadata_json` block.

## See also

[`read_parquet()`](https://vthanik.github.io/artoo/reference/read_parquet.md)
for the inverse;
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)

# ---- Example 1: write a conformed dataset to Parquet ----
#
# apply_spec() attaches the metadata; write_parquet() stores the data
# natively and the metadata as a CDISC-shaped sidecar.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".parquet")
write_parquet(adsl, path)

# ---- Example 2: round-trip and confirm the metadata survived ----
#
# Reading it back yields an identical artoo_meta.
back <- read_parquet(path)
identical(get_meta(back)@columns, get_meta(adsl)@columns)
#> [1] TRUE
```
