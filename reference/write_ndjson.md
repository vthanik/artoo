# Write a dataset to CDISC Dataset-JSON NDJSON

Serialize a data frame to the newline-delimited variant of CDISC
Dataset-JSON v1.1 (`.ndjson`): line 1 carries the complete metadata
block, every following line one row array. The streaming end of the
artoo workflow (spec -\> apply_spec -\> write_ndjson) for datasets too
large for the array-form `.json` file; a thin wrapper over
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
with `format = "ndjson"`.

## Usage

``` r
write_ndjson(
  x,
  path,
  on_invalid = c("error", "translit", "fold", "replace", "ignore"),
  created = NULL,
  strict = FALSE
)
```

## Arguments

- x:

  *The dataset to write.* `<data.frame>: required`. Typically the output
  of
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md),
  carrying `artoo_meta`.

- path:

  *Destination `.ndjson` path.* `<character(1)>: required`. A
  `.ndjson.gz` path writes gzip-compressed bytes.

- on_invalid:

  *Policy for values that are not valid UTF-8.*
  `<character(1)>: default "error"`. One of `"error"` (abort with
  `artoo_error_codec`), `"replace"` (substitute `?` and warn with
  `artoo_warning_encoding`), `"ignore"` (drop the invalid bytes), or
  `"translit"` / `"fold"` (accepted for pipeline symmetry; behave as
  `"error"` here, since a byte-level invalidity has no character fold).
  See
  [`write_json()`](https://vthanik.github.io/artoo/reference/write_json.md)
  for when this fires.

- created:

  *Creation timestamp.* `<POSIXct(1)> | NULL`. `NULL` (default) stamps
  the current time into `datasetJSONCreationDateTime`; freeze it for
  byte-stable output.

- strict:

  *Suppress the `_artoo` extension block.*
  `<logical(1)>: default FALSE`. See
  [`write_json()`](https://vthanik.github.io/artoo/reference/write_json.md):
  the same extension semantics apply to the metadata line.

## Value

*The input `x`*, invisibly, so a write can sit mid-pipeline.

## Details

**Bounded memory, both directions.** The writer streams slabs of
per-column JSON literals and
[`read_ndjson()`](https://vthanik.github.io/artoo/reference/read_ndjson.md)
parses slab-sized line batches, so a multi-million-row dataset never
materializes a whole `rows` array the way the `.json` codec must. A
`.ndjson.gz` path gzips the stream transparently.

## See also

[`read_ndjson()`](https://vthanik.github.io/artoo/reference/read_ndjson.md)
for the inverse;
[`write_json()`](https://vthanik.github.io/artoo/reference/write_json.md)
for the array-form file;
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)

# ---- Example 1: write a conformed dataset as NDJSON ----
#
# apply_spec() attaches the metadata; write_ndjson() streams the metadata
# line and one row per line.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".ndjson")
write_ndjson(adsl, path)
readLines(path, n = 2)[2]
#> [1] "[\"CDISCPILOT01\",\"01-701-1015\",\"1015\",\"701\",\"701\",\"Placebo\",\"Placebo\",0,\"Placebo\",0,19725,19906,182,0,0,63,\"<65\",1,\"YEARS\",\"WHITE\",1,\"F\",\"HISPANIC OR LATINO\",\"Y\",\"Y\",\"Y\",\"Y\",\"Y\",\"Y\",null,null,null,25.100000000000001,\"25-<30\",147.30000000000001,54.399999999999999,16,18382,43.899999999999999,\">=12\",19718,\"2014-01-02\",\"2014-07-02\",12,19906,\"COMPLETED\",\"Completed\",23]"

# ---- Example 2: gzip the stream via the file extension ----
#
# A .ndjson.gz path compresses transparently; read_ndjson() inflates it.
gz <- tempfile(fileext = ".ndjson.gz")
write_ndjson(adsl, gz)
nrow(read_ndjson(gz))
#> [1] 60
```
