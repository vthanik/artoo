# Read a dataset from rds

Read an R `.rds` file written by
[`write_rds()`](https://vthanik.github.io/artoo/reference/write_rds.md)
(or any rds carrying a `metadata_json` attribute) back to a data frame
with its `artoo_meta` restored. A thin wrapper over
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
with `format = "rds"`.

## Usage

``` r
read_rds(path, col_select = NULL, n_max = Inf, encoding = NULL)
```

## Arguments

- path:

  *Source `.rds` path.* `<character(1)>: required`.

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
  `NULL` (default) returns the strings exactly as saved (faithful R
  round-trip). Pass a charset name only to transcode a foreign rds whose
  string columns hold that charset's bytes.

  **Tip:** any SAS or IANA spelling listed by
  [`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md)
  is accepted.

## Value

*A `<data.frame>`* carrying `artoo_meta` when the file recorded it. An
rds holding anything other than a data frame is a `artoo_error_codec`;
use [`readRDS()`](https://rdrr.io/r/base/readRDS.html) for arbitrary
objects.

## See also

[`write_rds()`](https://vthanik.github.io/artoo/reference/write_rds.md)
for the inverse;
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)

# ---- Example 1: read a dataset written by write_rds() ----
#
# The restored frame carries the same metadata it was written with.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".rds")
write_rds(adsl, path)
back <- read_rds(path)
get_meta(back)@dataset$records
#> [1] 60

# ---- Example 2: a plain rds still reads as a data frame ----
#
# An rds without artoo metadata reads back as an ordinary frame.
bare <- tempfile(fileext = ".rds")
saveRDS(cdisc_dm, bare)
nrow(read_rds(bare))
#> [1] 60
```
