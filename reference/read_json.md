# Read a dataset from CDISC Dataset-JSON

Read a CDISC Dataset-JSON v1.1 (`.json`) file back to a data frame,
restoring the full `artoo_meta` it carries and realizing SAS
date/datetime/time variables to R `Date` / `POSIXct` /
[`hms::hms`](https://hms.tidyverse.org/reference/hms.html). Column types
are reconstructed from the recorded metadata, not guessed from the JSON
tokens, so the round-trip is lossless. The ingest end of the I/O layer;
a thin wrapper over
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
with `format = "json"`.

## Usage

``` r
read_json(path, col_select = NULL, n_max = Inf, encoding = NULL)
```

## Arguments

- path:

  *Source `.json` path.* `<character(1)>: required`. A JSON file that is
  not Dataset-JSON v1.1 aborts with `artoo_error_codec`.

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

- encoding:

  *Source charset of the file bytes.* `<character(1)> | NULL`. `NULL`
  (default) reads UTF-8, as Dataset-JSON requires. Pass an IANA or SAS
  charset name (e.g. `"windows-1252"`) only to read a non-conformant
  file a producer wrote in that charset; the bytes are transcoded to
  UTF-8 on read.

  **Tip:** any SAS or IANA spelling listed by
  [`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md)
  is accepted.

## Value

*A `<data.frame>`* carrying `artoo_meta` (read it with
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)).

## See also

[`write_json()`](https://vthanik.github.io/artoo/reference/write_json.md)
for the inverse;
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)

# ---- Example 1: round-trip a conformed dataset through Dataset-JSON ----
#
# The variable labels, types, and keys survive the round-trip.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".json")
write_json(adsl, path)
back <- read_json(path)
identical(get_meta(back)@columns, get_meta(adsl)@columns)
#> [1] TRUE

# ---- Example 2: the metadata names the dataset and row count ----
#
# The restored artoo_meta exposes the dataset-level attributes.
get_meta(back)@dataset$records
#> [1] 60
```
