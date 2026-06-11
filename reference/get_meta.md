# Read the metadata a dataset carries

Pull the `artoo_meta` off a data frame produced by
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
or read back by any `read_*()` codec. The metadata travels as a single
Dataset-JSON string in the frame's `metadata_json` attribute;
`get_meta()` parses it to the S7 object, the form every codec writes
from. This is the read half of the lossless round-trip.

## Usage

``` r
get_meta(x)
```

## Arguments

- x:

  *A data frame carrying artoo metadata.* `<data.frame>: required`.
  Typically the output of
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
  or a `read_*()` codec.

  **Requirement:** `x` must carry a `metadata_json` attribute (set by
  [`set_meta()`](https://vthanik.github.io/artoo/reference/set_meta.md),
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md),
  or a reader); a bare frame aborts with `artoo_error_input`.

## Value

*A `<artoo_meta>`* with dataset-level (`@dataset`) and per-column
(`@columns`) CDISC attributes. Pass it to
[`set_meta()`](https://vthanik.github.io/artoo/reference/set_meta.md) to
re-attach, or inspect it directly.

## See also

[`set_meta()`](https://vthanik.github.io/artoo/reference/set_meta.md)
for the write half;
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
which stamps it.

## Examples

``` r
# ---- Example 1: read metadata off a conformed dataset ----
#
# apply_spec() stamps the metadata; get_meta() reads it back as the S7
# object whose @columns holds one CDISC attribute set per variable.
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
adsl <- apply_spec(cdisc_adsl, spec, "ADSL")
meta <- get_meta(adsl)
meta@columns$STUDYID
#> $itemOID
#> [1] "IT.ADSL.STUDYID"
#> 
#> $name
#> [1] "STUDYID"
#> 
#> $label
#> [1] "Study Identifier"
#> 
#> $dataType
#> [1] "string"
#> 
#> $length
#> [1] 12
#> 

# ---- Example 2: round-trip metadata across two frames ----
#
# The metadata is a portable object: read it off one frame and stamp it
# onto another with set_meta().
bare <- as.data.frame(adsl)
attr(bare, "metadata_json") <- NULL
restamped <- set_meta(bare, meta)
identical(get_meta(restamped)@columns, meta@columns)
#> [1] TRUE
```
