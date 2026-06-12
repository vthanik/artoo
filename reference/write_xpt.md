# Write a dataset to SAS XPORT

Serialize a data frame to a SAS Transport (`.xpt`) file in v5 (the FDA
submission standard) or v8 (extended names and labels), preserving the
`artoo_meta` a column can hold. The emit end of the artoo workflow (spec
-\> apply_spec -\> write_xpt); a thin wrapper over
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
with `format = "xpt"`.

## Usage

``` r
write_xpt(
  x,
  path,
  version = 5,
  encoding = NULL,
  on_invalid = c("error", "replace", "ignore"),
  created = NULL
)
```

## Arguments

- x:

  *The dataset to write.* `<data.frame>: required`. Typically the output
  of
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md),
  carrying `artoo_meta`.

- path:

  *Destination `.xpt` path.* `<character(1)>: required`.

- version:

  *XPORT transport version.* `<integer(1)>: default 5`. `5` (the FDA
  standard: names \<= 8 characters, labels \<= 40 bytes) or `8` (names
  \<= 32, long labels).

- encoding:

  *Target charset.* `<character(1)> | NULL`. `NULL` (default) inherits
  the source encoding recorded in `artoo_meta`, else UTF-8. IANA and SAS
  names (`"US-ASCII"`, `"wlatin1"`) both work.

  **Tip:** any SAS or IANA spelling listed by
  [`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md)
  is accepted.

- on_invalid:

  *Policy for values not representable in `encoding`.*
  `<character(1)>: default "error"`. One of `"error"` (abort with
  `artoo_error_codec`, naming the offenders), `"replace"` (substitute
  `?` and warn with `artoo_warning_encoding`), or `"ignore"` (drop
  them). The same policy vocabulary as the UTF-8 writers
  ([`write_json()`](https://vthanik.github.io/artoo/reference/write_json.md),
  [`write_ndjson()`](https://vthanik.github.io/artoo/reference/write_ndjson.md),
  [`write_parquet()`](https://vthanik.github.io/artoo/reference/write_parquet.md)).

- created:

  *Header timestamp.* `<POSIXct(1)> | NULL`. `NULL` (default) stamps the
  current time; freeze it for byte-stable output.

## Value

*The input `x`*, invisibly, so a write can sit mid-pipeline.

## Details

**What XPORT can carry.** An `.xpt` file's NAMESTR stores only variable
name, label, length, and SAS format. CDISC metadata beyond that
(keySequence, codelist, origin, targetDataType, ...) and the source
encoding are not representable in the bytes; they ride the in-session
`artoo_meta` and the sidecar in self-describing formats (Dataset-JSON,
Parquet, rds). XPORT also cannot distinguish an empty string from `NA`
(both store as blanks) and drops trailing spaces.

**Character ISO dates (`--DTC`) write as text.** A character column
whose `dataType` is `date`/`datetime`/`time` with no numeric
`targetDataType` is the CDISC ISO 8601 text form — the SDTM `--DTC`
convention — and stores as a character variable, partial dates
(`"1951"`, `"1951-12"`) included, byte for byte. The SAS-numeric
encoding (with `DATE9.`-style formats) is used for columns that are R
`Date`/`POSIXct`/`hms` or whose metadata records
`targetDataType = "integer"` (the ADaM numeric-date convention). A
character column *under* `targetDataType = "integer"` aborts loudly — a
partial date can never become a SAS numeric silently.

## See also

[`read_xpt()`](https://vthanik.github.io/artoo/reference/read_xpt.md)
for the inverse;
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
for the generic dispatcher.

## Examples

``` r
spec <- artoo_spec(
  cdisc_adam_datasets, cdisc_adam_variables,
  codelists = cdisc_codelists
)

# ---- Example 1: write a conformed dataset as v5 (FDA standard) ----
#
# apply_spec() attaches the metadata; write_xpt() carries the label, length,
# and SAS format for each variable into the transport file.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".xpt")
write_xpt(adsl, path)

# ---- Example 2: v8 for long names, with a frozen timestamp ----
#
# Version 8 keeps names over 8 characters; a fixed `created` makes the bytes
# reproducible. Reading it back shows the labels, types, and record count
# survived the transport. DM is SDTM, so it conforms against the bundled
# sdtm_spec.
dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#> Scaffolded 1 variable the spec declares but the data lacks (added as
#> empty): `BRTHDTC`
path8 <- tempfile(fileext = ".xpt")
write_xpt(dm, path8, version = 8, created = as.POSIXct("2020-01-01", tz = "UTC"))
get_meta(read_xpt(path8))@dataset$records
#> [1] 60
```
