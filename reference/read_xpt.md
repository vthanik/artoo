# Read a dataset from SAS XPORT

Read a SAS Transport (`.xpt`) file (v5 or v8) back to a data frame,
restoring the `artoo_meta` its NAMESTR records carry and realizing SAS
date/datetime/time variables to R `Date` / `POSIXct` /
[`hms::hms`](https://hms.tidyverse.org/reference/hms.html). The ingest
end of the I/O layer; a thin wrapper over
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
with `format = "xpt"`.

## Usage

``` r
read_xpt(path, encoding = NULL, col_select = NULL, n_max = Inf, member = NULL)
```

## Arguments

- path:

  *Source `.xpt` path.* `<character(1)>: required`.

- encoding:

  *Force a source charset.* `<character(1)> | NULL`. `NULL` (default)
  auto-detects (UTF-8 when every character value and label is valid
  UTF-8, else Windows-1252). IANA and SAS names both work.

  **Tip:** any SAS or IANA spelling listed by
  [`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md)
  is accepted.

- col_select:

  *Variables to read.* `<character> | NULL`. `NULL` (default) reads
  every column; otherwise a vector of variable names (matching the names
  as stored, uppercase for v5). Columns return in file order, and the
  `artoo_meta` is filtered to match.

  **Note:** an unknown name is a `artoo_error_input`, never a silent
  drop.

- n_max:

  *Maximum records to read.* `<numeric(1)>: default Inf`. Caps the row
  count; the returned `artoo_meta` reports the rows actually read.

- member:

  *Which member of a multi-member transport file to read.*
  `<character(1) | numeric(1)> | NULL`. A transport file can hold
  several datasets; pass a member name (case-insensitive) or 1-based
  index to pick one. `NULL` (default) reads a single-member file
  directly and aborts on a multi-member file, pointing at
  [`xpt_members()`](https://vthanik.github.io/artoo/reference/xpt_members.md).

  **Tip:** `xpt_members(path)` lists what a file holds before you
  choose.

## Value

*A `<data.frame>`* carrying `artoo_meta` (read it with
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)).

## Details

The character encoding is auto-detected (UTF-8 if every character value
is valid UTF-8, else Windows-1252) and recorded on the returned
`artoo_meta`, so a later
[`write_xpt()`](https://vthanik.github.io/artoo/reference/write_xpt.md)
reproduces it; pass `encoding` to override. XPORT cannot record its own
encoding, so this detection is a heuristic. See
[`write_xpt()`](https://vthanik.github.io/artoo/reference/write_xpt.md)
for what XPORT can and cannot preserve.

## See also

[`xpt_members()`](https://vthanik.github.io/artoo/reference/xpt_members.md)
to list a file's members;
[`write_xpt()`](https://vthanik.github.io/artoo/reference/write_xpt.md)
for the inverse;
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)

# ---- Example 1: round-trip a conformed dataset through xpt ----
#
# Write ADSL, read it back; the variable labels and lengths survive.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".xpt")
write_xpt(adsl, path)
back <- read_xpt(path)
get_meta(back)@columns$STUDYID$label
#> [1] "Study Identifier"

# ---- Example 2: pick one member of a multi-member transport file ----
#
# Build a two-member file by concatenating two single-member files (every
# member section is 80-byte padded), then read one dataset out of it.
dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
p_dm <- tempfile(fileext = ".xpt")
write_xpt(dm, p_dm)
multi <- tempfile(fileext = ".xpt")
writeBin(
  c(
    readBin(path, "raw", file.size(path)),
    readBin(p_dm, "raw", file.size(p_dm))[-(1:240)]
  ),
  multi
)
xpt_members(multi)$name
#> [1] "ADSL" "DM"  
nrow(read_xpt(multi, member = "DM"))
#> [1] 60
```
