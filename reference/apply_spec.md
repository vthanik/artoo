# Conform a data frame to its spec

Run the ordered, transactional artoo pipeline that turns a raw analysis
data frame into one conformed to its specification and carrying
`artoo_meta`. This is the middle of the workflow (spec -\> apply_spec
-\> read\_/write\_): the conformed frame is ready for any `write_*()`
codec, and the metadata it now carries makes that write lossless. The
input is never mutated; if any step aborts, the call leaves your data
untouched.

## Usage

``` r
apply_spec(
  x,
  spec,
  dataset,
  conformance = c("warn", "abort", "off"),
  na_position = c("first", "last")
)
```

## Arguments

- x:

  *The raw data frame to conform.* `<data.frame>: required`.

- spec:

  *The specification to conform to.* `<artoo_spec>: required`.

- dataset:

  *The dataset whose rules apply.* `<character(1)>: required`. Must name
  a dataset in `spec`.

- conformance:

  *What to do with conformance findings.* `<character(1)>`. One of:

  - `"warn"` (default) run
    [`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md),
    attach the findings (read them with
    [`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md)),
    warn on any error-severity finding.

  - `"abort"` abort with `artoo_error_conformance` on any error-severity
    finding.

  - `"off"` skip the check entirely.

  **Note:** this governs only the *findings* disposition; pipeline
  errors (an unknown dataset, lossy coercion) abort regardless.

- na_position:

  *Where missing key values sort.* `<character(1)>`. One of `"first"`
  (default) or `"last"`. `"first"` matches SAS `PROC SORT` (and the FDA
  submission convention) by ordering missings before present values;
  `"last"` matches R's [`order()`](https://rdrr.io/r/base/order.html)
  and the pandas/Polars default. Both are lossless; pick the one your
  comparison target uses.

## Value

*A conformed `<data.frame>`* carrying `artoo_meta` (read it with
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md))
and, unless `conformance = "off"`, the findings frame
[`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md)
reads back. Hand it to any `write_*()` codec.

## Details

**Ordered pipeline.** Five fixed steps run in order: scaffold missing
spec variables (typed `NA`), coerce each column to its CDISC dataType,
reorder columns to the spec, sort rows by the dataset keys, then stamp
the metadata.

**Never drops a column.** A column the spec does not declare survives
the pipeline (ordered after the declared ones), is *reported* by the
`extra_variable` conformance finding, and round-trips through every
`write_*()` codec with metadata inferred from its R class. Membership is
reported, not enforced by destruction.

**Lossless or abort.** A coercion that would damage values — an
`integer` dataType truncating fractions or overflowing R's 32-bit range
— aborts with `artoo_error_type` before any value is touched. There is
no opt-out: fix the spec (dataType `"float"` or `"decimal"` keeps
fractions) rather than accept silent damage.

**Values are never translated.** Coded variables keep their submission
values (`SEX` stays `"M"`); codelist translation is its own verb,
[`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md).

## See also

**Check:**
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
for the findings;
[`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md)
to read them back.

**Translate:**
[`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md)
for codelist value mapping.

**Metadata:**
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md) /
[`set_meta()`](https://vthanik.github.io/artoo/reference/set_meta.md)
for what the stamp attaches.

## Examples

``` r
# ---- Example 1: conform ADSL, then read its metadata ----
#
# The bundled adam_spec describes ADSL; the raw frame is scaffolded,
# coerced, ordered, sorted, and stamped with the CDISC metadata
# get_meta() reads back.
adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL")
#> Scaffolded 6 variables: `TRTDURD`, `DISONDT`, `EOSSTT`, `DCSREAS`,
#> `EOSDISP`, and `MMS1TSBL`
get_meta(adsl)@dataset$records
#> [1] 60

# ---- Example 2: an undeclared column survives, and is reported ----
#
# apply_spec() never drops data: a column outside the spec rides along
# (reported by the extra_variable finding) and still writes losslessly.
# DM is SDTM, so it conforms against the bundled sdtm_spec.
raw <- cdisc_dm
raw$DERIVED <- seq_len(nrow(raw))
dm <- apply_spec(raw, sdtm_spec, "DM")
#> Scaffolded 1 variable: `BRTHDTC`
findings <- conformance(dm)
findings[findings$check == "extra_variable", c("variable", "message")]
#>    variable                                        message
#> 1  RFXSTDTC Column 'RFXSTDTC' is not declared in the spec.
#> 2  RFXENDTC Column 'RFXENDTC' is not declared in the spec.
#> 3   RFICDTC  Column 'RFICDTC' is not declared in the spec.
#> 4  RFPENDTC Column 'RFPENDTC' is not declared in the spec.
#> 5    DTHDTC   Column 'DTHDTC' is not declared in the spec.
#> 6     DTHFL    Column 'DTHFL' is not declared in the spec.
#> 7  ACTARMCD Column 'ACTARMCD' is not declared in the spec.
#> 8    ACTARM   Column 'ACTARM' is not declared in the spec.
#> 9     DMDTC    Column 'DMDTC' is not declared in the spec.
#> 10     DMDY     Column 'DMDY' is not declared in the spec.
#> 11  DERIVED  Column 'DERIVED' is not declared in the spec.
```
