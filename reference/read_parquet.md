# Read a dataset from Apache Parquet

Read an Apache Parquet (`.parquet`) file back to a data frame, restoring
the `artoo_meta` from its `metadata_json` sidecar and realizing SAS
date/datetime/time variables to R `Date` / `POSIXct` /
[`hms::hms`](https://hms.tidyverse.org/reference/hms.html). A parquet
written by another tool (with no artoo sidecar) reads back as a bare
frame. A thin wrapper over
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
with `format = "parquet"`. Requires the lightweight `nanoparquet`
package.

## Usage

``` r
read_parquet(path, col_select = NULL, n_max = Inf, encoding = NULL)
```

## Arguments

- path:

  *Source `.parquet` path.* `<character(1)>: required`.

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

  *Source charset of the string columns.* `<character(1)> | NULL`.
  `NULL` (default) reads the UTF-8 bytes parquet stores. Pass a charset
  name only to read a foreign file whose string columns hold that
  charset's bytes; they are transcoded to UTF-8 on read.

## Value

*A `<data.frame>`* carrying `artoo_meta` when the file recorded it (read
it with
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md));
otherwise a plain data frame.

## See also

[`write_parquet()`](https://vthanik.github.io/artoo/reference/write_parquet.md)
for the inverse;
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)

# ---- Example 1: round-trip a conformed dataset through Parquet ----
#
# The variable labels, types, and keys survive the round-trip.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".parquet")
write_parquet(adsl, path)
back <- read_parquet(path)
get_meta(back)@columns$STUDYID$label
#> [1] "Study Identifier"

# ---- Example 2: the metadata names the dataset and row count ----
#
# The restored artoo_meta exposes the dataset-level attributes.
get_meta(back)@dataset$records
#> [1] 60
```
