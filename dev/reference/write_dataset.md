# Write a dataset to any supported format

Serialize a data frame to a clinical file format, preserving its
`artoo_meta` losslessly. The codec is chosen from the file extension (or
an explicit `format`), so one call covers xpt, Dataset-JSON, Parquet,
and rds. This is the emit end of the artoo workflow; the per-format
wrappers like
[`write_rds()`](https://vthanik.github.io/artoo/dev/reference/write_rds.md)
are thin sugar over it.

## Usage

``` r
write_dataset(x, path, format = NULL, ...)
```

## Arguments

- x:

  *The dataset to write.* `<data.frame>: required`. Typically the output
  of
  [`apply_spec()`](https://vthanik.github.io/artoo/dev/reference/apply_spec.md),
  carrying `artoo_meta`.

- path:

  *Destination file path.* `<character(1)>: required`. Its extension
  selects the codec unless `format` is given.

- format:

  *Force a codec instead of inferring from the extension.*
  `<character(1)> | NULL`. One of the registered formats (see
  [`artoo_formats()`](https://vthanik.github.io/artoo/dev/reference/artoo_formats.md)).

- ...:

  *Codec-specific arguments* passed through to the encoder (see the
  per-format wrappers, e.g.
  [`write_xpt()`](https://vthanik.github.io/artoo/dev/reference/write_xpt.md),
  for what each codec accepts). An argument the codec does not know is
  an error, never silently ignored.

## Value

*The input `x`*, invisibly, so a write can sit mid-pipeline. Called for
the side effect of writing `path`.

## See also

[`read_dataset()`](https://vthanik.github.io/artoo/dev/reference/read_dataset.md)
for the inverse;
[`write_rds()`](https://vthanik.github.io/artoo/dev/reference/write_rds.md)
for the per-format wrapper;
[`artoo_formats()`](https://vthanik.github.io/artoo/dev/reference/artoo_formats.md)
for what is available.

## Examples

``` r
spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)

# ---- Example 1: write a conformed dataset, inferring rds from the path ----
#
# apply_spec() attaches the metadata; write_dataset() carries it into the
# file so a later read is lossless.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
path <- tempfile(fileext = ".rds")
write_dataset(adsl, path)

# ---- Example 2: force the format for an unconventional extension ----
#
# When the extension does not name the format, pass it explicitly.
alt <- tempfile(fileext = ".data")
write_dataset(adsl, alt, format = "rds")
```
