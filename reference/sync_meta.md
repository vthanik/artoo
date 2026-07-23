# Re-align metadata with a transformed data frame

Re-attach and reconcile a `artoo_meta` after a transformation that
dropped or reshaped it: the metadata's columns are narrowed and
reordered to the frame's current columns, the record count is refreshed,
the keys are recomputed, and a column the metadata does not describe
gets an entry synthesized from its class and attributes. The one-liner
to run after a dplyr (or base) pipeline, before handing the frame to a
`write_*()` codec.

## Usage

``` r
sync_meta(x, meta = NULL)
```

## Arguments

- x:

  *The transformed data frame.* `<data.frame>: required`.

- meta:

  *The metadata to reconcile against.* `<artoo_meta> | NULL`. `NULL`
  (default) uses the frame's own `metadata_json` attribute.

  **Requirement:** when the transform dropped the attribute (base `[`
  subsetting does), capture
  [`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)
  before the pipeline and pass it here; a bare frame with no `meta`
  aborts with `artoo_error_input`.

## Value

*A `<data.frame>`*: `x` re-stamped with the reconciled `artoo_meta`.
Hand it to any `write_*()` codec.

## Details

**Why it exists.** Base row subsetting (`x[i, ]`) drops the frame's
`metadata_json` attribute, and many tidyverse verbs rebuild the frame.
`sync_meta()` takes the last-known metadata (the frame's own attribute
when it survived, or an explicit `meta`) and makes it agree with the
data again, so the round trip stays lossless without hand-editing.

## See also

**Read / attach:**
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md),
[`set_meta()`](https://vthanik.github.io/artoo/reference/set_meta.md).

**Produce conformed frames:**
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md).

## Examples

``` r
spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)

# ---- Example 1: re-attach after an attribute-dropping subset ----
#
# Base subsetting drops the metadata; capture it first, transform, then
# sync. The metadata narrows to the kept columns and the new row count.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
meta <- get_meta(adsl)
elderly <- adsl[adsl$AGE > 65, c("STUDYID", "USUBJID", "AGE")]
synced <- sync_meta(elderly, meta)
get_meta(synced)@dataset$records
#> [1] 46

# ---- Example 2: a derived column gains a synthesized entry ----
#
# A new column the metadata does not describe is profiled from its class,
# so the frame still writes losslessly.
adsl$AGEGR9 <- ifelse(adsl$AGE > 65, ">65", "<=65")
synced2 <- sync_meta(adsl)
#> Synthesized metadata for 1 new column: `AGEGR9`.
#> ℹ Edit the spec (or the meta) if the inferred types need refining.
get_meta(synced2)@columns$AGEGR9$dataType
#> [1] "string"
```
