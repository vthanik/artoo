# Write a dataset to CDISC Dataset-JSON

Serialize a data frame to a CDISC Dataset-JSON v1.1 (`.json`) file,
Dataset-JSON being the native home of the `artoo_meta` shape: the file
is the metadata block plus a flat `rows` array. The emit end of the
artoo workflow (spec -\> apply_spec -\> write_json); a thin wrapper over
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
with `format = "json"`.

## Usage

``` r
write_json(x, path, created = NULL, strict = FALSE)
```

## Arguments

- x:

  *The dataset to write.* `<data.frame>: required`. Typically the output
  of
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md),
  carrying `artoo_meta`.

- path:

  *Destination `.json` path.* `<character(1)>: required`.

- created:

  *Creation timestamp.* `<POSIXct(1)> | NULL`. `NULL` (default) stamps
  the current time into `datasetJSONCreationDateTime`; freeze it for
  byte-stable output.

- strict:

  *Suppress the `_artoo` extension block.*
  `<logical(1)>: default FALSE`. By default the file carries a single
  namespaced `_artoo` object when (and only when) there is content
  strict CDISC cannot express: SAS special-missing tags (`.A`-`.Z`,
  `._`), the recorded source encoding, and informats. Data values stay
  plain `null`s either way, so a foreign reader degrades gracefully.

  **Note:** `strict = TRUE` writes a pure closed-vocabulary file and
  warns (`artoo_warning_codec`) naming exactly what was dropped; those
  attributes will not survive a read-back.

## Value

*The input `x`*, invisibly, so a write can sit mid-pipeline.

## Details

**Full metadata, no loss.** Unlike `.xpt`, a `.json` file records the
complete `artoo_meta`: keySequence, codelist, origin, targetDataType,
and significantDigits all survive. Dates, datetimes, and times are
exchanged as ISO 8601 strings, or as SAS-epoch numbers when their
`targetDataType` is `"integer"` (the ADaM numeric-date convention);
`decimal` rides as a string so exact precision is preserved. The file is
always UTF-8 (RFC 8259 / CDISC v1.1). `NaN` and infinite values are not
valid CDISC numerics and abort the write.

**Streaming write, whole-file read.** The writer streams the `rows`
array in bounded slabs (a `.json.gz` path gzips the stream
transparently), but
[`read_json()`](https://vthanik.github.io/artoo/reference/read_json.md)
must parse the whole array at once. For multi-million-row datasets
prefer the NDJSON variant
([`write_ndjson()`](https://vthanik.github.io/artoo/reference/write_ndjson.md)
/
[`read_ndjson()`](https://vthanik.github.io/artoo/reference/read_ndjson.md)),
which bounds memory in both directions.

## See also

[`read_json()`](https://vthanik.github.io/artoo/reference/read_json.md)
for the inverse;
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)

# ---- Example 1: write a conformed dataset as Dataset-JSON ----
#
# apply_spec() attaches the metadata; write_json() serializes the full
# itemGroup plus the data rows.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".json")
write_json(adsl, path)

# ---- Example 2: a frozen timestamp for reproducible bytes ----
#
# Fixing `created` makes two writes byte-identical.
dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
path2 <- tempfile(fileext = ".json")
write_json(dm, path2, created = as.POSIXct("2020-01-01", tz = "UTC"))
```
