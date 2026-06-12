# Read a dataset from CDISC Dataset-JSON NDJSON

Read a newline-delimited CDISC Dataset-JSON v1.1 (`.ndjson`) file back
to a data frame, restoring the full `artoo_meta` from its metadata line
and realizing SAS date/datetime/time variables to R `Date` / `POSIXct` /
[`hms::hms`](https://hms.tidyverse.org/reference/hms.html). Rows are
parsed in bounded slabs, and `n_max` stops the line loop early, so a
partial read of a huge file never parses the tail. A thin wrapper over
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
with `format = "ndjson"`.

## Usage

``` r
read_ndjson(path, col_select = NULL, n_max = Inf, encoding = NULL)
```

## Arguments

- path:

  *Source `.ndjson` path.* `<character(1)>: required`. A gzip stream
  (`.ndjson.gz`) is inflated transparently. A file whose first line is
  not the Dataset-JSON metadata object aborts with `artoo_error_codec`.

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
  file a producer wrote in that charset; each line is transcoded to
  UTF-8 on read, preserving the bounded `n_max` streaming.

## Value

*A `<data.frame>`* carrying `artoo_meta` (read it with
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)).

## See also

[`write_ndjson()`](https://vthanik.github.io/artoo/reference/write_ndjson.md)
for the inverse;
[`read_json()`](https://vthanik.github.io/artoo/reference/read_json.md)
for the array-form file;
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)

# ---- Example 1: round-trip a conformed dataset through NDJSON ----
#
# The variable labels, types, and keys survive the round-trip.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".ndjson")
write_ndjson(adsl, path)
back <- read_ndjson(path)
identical(get_meta(back)@columns, get_meta(adsl)@columns)
#> [1] TRUE

# ---- Example 2: a bounded partial read of the first rows ----
#
# n_max stops the line loop as soon as enough rows are in.
head_rows <- read_ndjson(path, n_max = 5)
get_meta(head_rows)@dataset$records
#> [1] 5
```
