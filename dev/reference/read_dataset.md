# Read a dataset from any supported format

Read a clinical file back to a data frame, restoring its `artoo_meta`.
The codec is chosen from the file extension (or an explicit `format`),
and the metadata the file carries is re-attached, so a value written by
[`write_dataset()`](https://vthanik.github.io/artoo/dev/reference/write_dataset.md)
round-trips losslessly. This is the ingest end of the I/O layer; the
per-format wrappers like
[`read_rds()`](https://vthanik.github.io/artoo/dev/reference/read_rds.md)
call it.

## Usage

``` r
read_dataset(path, format = NULL, col_select = NULL, n_max = Inf, ...)
```

## Arguments

- path:

  *Source file path.* `<character(1)>: required`. Its extension selects
  the codec unless `format` is given.

- format:

  *Force a codec instead of inferring from the extension.*
  `<character(1)> | NULL`. One of the registered formats (see
  [`artoo_formats()`](https://vthanik.github.io/artoo/dev/reference/artoo_formats.md)).

- col_select:

  *Variables to read.* `<character> | NULL`. `NULL` (default) reads
  every column; otherwise a vector of variable names. Columns return in
  file order (not the requested order) and the `artoo_meta` is filtered
  to match. Works on every format: parquet narrows columns natively, the
  rest filter after decode.

  **Note:** an unknown name is a `artoo_error_input`, never a silent
  drop.

- n_max:

  *Maximum records to read.* `<numeric(1)>: default Inf`. Caps the row
  count; the returned `artoo_meta` reports the rows actually read. xpt
  v8 bounds the disk read; the other formats cap after decode.

- ...:

  *Codec-specific arguments* passed through to the decoder (see the
  per-format wrappers, e.g.
  [`read_xpt()`](https://vthanik.github.io/artoo/dev/reference/read_xpt.md)).
  An argument the codec does not know is an error, never silently
  ignored.

## Value

*A `<data.frame>`* carrying `artoo_meta` when the file recorded it (read
it with
[`get_meta()`](https://vthanik.github.io/artoo/dev/reference/get_meta.md)).
A file whose payload is not a data frame is a `artoo_error_codec`.

## See also

[`write_dataset()`](https://vthanik.github.io/artoo/dev/reference/write_dataset.md)
for the inverse;
[`read_rds()`](https://vthanik.github.io/artoo/dev/reference/read_rds.md)
for the per-format wrapper.

## Examples

``` r
spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)

# ---- Example 1: round-trip a dataset through rds ----
#
# Write a conformed dataset, then read it back; the metadata survives.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".rds")
write_dataset(adsl, path)
back <- read_dataset(path)
identical(get_meta(back)@columns, get_meta(adsl)@columns)
#> [1] TRUE

# ---- Example 2: the metadata names the dataset and row count ----
#
# The restored artoo_meta exposes the dataset-level attributes.
get_meta(back)@dataset$records
#> [1] 60
```
