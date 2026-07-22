# Write a dataset to CDISC Dataset-JSON

Serialize a data frame to a CDISC Dataset-JSON v1.1 (`.json`) file,
Dataset-JSON being the native home of the `artoo_meta` shape: the file
is the metadata block plus a flat `rows` array. The emit end of the
artoo workflow (spec -\> apply_spec -\> write_json); a thin wrapper over
[`write_dataset()`](https://vthanik.github.io/artoo/dev/reference/write_dataset.md)
with `format = "json"`.

## Usage

``` r
write_json(
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
  [`apply_spec()`](https://vthanik.github.io/artoo/dev/reference/apply_spec.md),
  carrying `artoo_meta`.

- path:

  *Destination `.json` path.* `<character(1)>: required`.

- on_invalid:

  *Policy for values that are not valid UTF-8.*
  `<character(1)>: default "error"`. One of `"error"` (abort with
  `artoo_error_codec`, naming the offenders with their invalid bytes
  hex-escaped), `"replace"` (substitute `?` and warn with
  `artoo_warning_encoding`), `"ignore"` (drop the invalid bytes), or
  `"translit"` / `"fold"` (like `"error"`; a byte-level invalidity has
  no character fold, the options exist so one policy value can thread a
  whole multi-format pipeline). The same policy vocabulary as
  [`write_xpt()`](https://vthanik.github.io/artoo/dev/reference/write_xpt.md);
  text correctly read through artoo is always valid UTF-8, so this only
  fires on bytes that entered the frame through a mis-declared source
  encoding.

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
[`read_json()`](https://vthanik.github.io/artoo/dev/reference/read_json.md)
must parse the whole array at once. For multi-million-row datasets
prefer the NDJSON variant
([`write_ndjson()`](https://vthanik.github.io/artoo/dev/reference/write_ndjson.md)
/
[`read_ndjson()`](https://vthanik.github.io/artoo/dev/reference/read_ndjson.md)),
which bounds memory in both directions.

## See also

[`read_json()`](https://vthanik.github.io/artoo/dev/reference/read_json.md)
for the inverse;
[`write_dataset()`](https://vthanik.github.io/artoo/dev/reference/write_dataset.md)
for the generic dispatcher.

## Examples

``` r
# ---- Example 1: write a conformed dataset as Dataset-JSON ----
#
# apply_spec() attaches the metadata; write_json() serializes the full
# itemGroup plus the data rows.
adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off")
#> 6 variables the spec declares are absent from the data (not added):
#> `TRTDURD`, `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
path <- tempfile(fileext = ".json")
write_json(adsl, path)

# ---- Example 2: a frozen timestamp for reproducible bytes ----
#
# Fixing `created` makes two writes byte-identical; the columns() pane on
# the written file shows the full metadata the file carries (DM is SDTM,
# so it conforms against the bundled sdtm_spec).
dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#> 1 variable the spec declares is absent from the data (not added):
#> `BRTHDTC`.
path2 <- tempfile(fileext = ".json")
write_json(dm, path2, created = as.POSIXct("2020-01-01", tz = "UTC"))
columns(path2)
#> <artoo_columns> DM -- 25 variables, 60 obs
#> #   Variable  Type  Len  Format  Label                              Key
#> 1   STUDYID   Char  7            Study Identifier                   1
#> 2   DOMAIN    Char  2            Domain Abbreviation
#> 3   USUBJID   Char  14           Unique Subject Identifier          2
#> 4   SUBJID    Char  6            Subject Identifier for the Study
#> 5   RFSTDTC   Char  10           Subject Reference Start Date/Time
#> 6   RFENDTC   Char  10           Subject Reference End Date/Time
#> 7   SITEID    Char  3            Study Site Identifier
#> 8   AGE       Num                Age
#> 9   AGEU      Char  5            Age Units
#> 10  SEX       Char  16           Sex
#> 11  RACE      Char  41           Race
#> 12  ETHNIC    Char  22           Ethnicity
#> 13  ARMCD     Char  8            Planned Arm Code
#> 14  ARM       Char  20           Description of Planned Arm
#> 15  COUNTRY   Char  3            Country
#> 16  RFXSTDTC  Char  10
#> 17  RFXENDTC  Char  10
#> 18  RFICDTC   Char  1
#> 19  RFPENDTC  Char  16
#> 20  DTHDTC    Char  10
#> 21  DTHFL     Char  1
#> 22  ACTARMCD  Char  8
#> 23  ACTARM    Char  20
#> 24  DMDTC     Char  10
#> 25  DMDY      Num
```
