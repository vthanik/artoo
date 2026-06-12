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
  na_position = c("first", "last"),
  extra = c("keep", "drop")
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

  **Note:** this governs only the *findings* disposition — what is
  *reported*. Pipeline errors are a different category and abort under
  every setting, including `"off"`: an unknown dataset, and above all
  lossy coercion (`artoo_error_type`), which no `conformance` value
  bypasses. If the abort names variables whose spec dataType is
  `integer` but whose data carries fractions, the fix is the spec
  (retype to `"float"`/`"decimal"`), not this argument; the condition's
  `$variables` frame lists every offender.

- na_position:

  *Where missing key values sort.* `<character(1)>`. One of `"first"`
  (default) or `"last"`. `"first"` matches SAS `PROC SORT` (and the FDA
  submission convention) by ordering missings before present values;
  `"last"` matches R's [`order()`](https://rdrr.io/r/base/order.html)
  and the pandas/Polars default. Both are lossless; pick the one your
  comparison target uses.

- extra:

  *What happens to undeclared columns.* `<character(1)>`. An "extra" is
  a column of `x` the spec does not declare — typically a derivation
  temporary. One of:

  - `"keep"` (default) extras ride along after the declared columns,
    reported by the `extra_variable` finding.

  - `"drop"` the returned frame carries exactly the spec's columns; the
    drop is announced (`artoo_message_apply`) and the `extra_variable`
    finding still reports what was removed.

  **Interaction:** under `conformance = "abort"` an error-severity
  finding aborts *before* any drop — the trim never masks a failure.

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

**Extras are kept by default.** A column the spec does not declare
survives the pipeline (ordered after the declared ones), is *reported*
by the `extra_variable` conformance finding, and round-trips through
every `write_*()` codec with metadata inferred from its R class —
membership reported, never enforced by silent destruction.
`extra = "drop"` opts in to trim-to-spec (the
`metatools::drop_unspec_vars()` migration shape): the undeclared columns
are removed *after* the findings are computed, so the `extra_variable`
finding remains the audit trail of what was dropped, and the drop itself
is always announced (`artoo_message_apply`) — even under
`conformance = "off"`.

**Lossless or abort.** A coercion that would damage values — an
`integer` dataType truncating fractions or overflowing R's 32-bit range
— aborts with `artoo_error_type` before any value is touched. There is
no opt-out: fix the spec (dataType `"float"` or `"decimal"` keeps
fractions) rather than accept silent damage. The condition carries the
offending rows as data: `cnd$variables` is a data frame with columns
`variable`, `data_type`, `n`, and `reason` (`"truncated"` /
`"overflowed"`), so a pipeline can collect every mismatch in one
`tryCatch(..., artoo_error_type = function(cnd) cnd$variables)` pass.
The NA-introduction warning (`artoo_warning_coercion`) carries the same
frame with `reason = "na_introduced"`, and a `conformance = "abort"`
failure carries the complete findings frame as `cnd$findings`.

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

# ---- Example 2: extras are kept and reported, or dropped on request ----
#
# By default a column outside the spec rides along (reported by the
# extra_variable finding) and still writes losslessly; extra = "drop"
# trims to the spec, announced and still reported. DM is SDTM, so it
# conforms against the bundled sdtm_spec.
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
trimmed <- apply_spec(raw, sdtm_spec, "DM", extra = "drop")
#> Scaffolded 1 variable: `BRTHDTC`
#> Dropped 11 undeclared variables: `RFXSTDTC`, `RFXENDTC`, `RFICDTC`,
#> `RFPENDTC`, `DTHDTC`, `DTHFL`, `ACTARMCD`, `ACTARM`, `DMDTC`, `DMDY`,
#> and `DERIVED`
"DERIVED" %in% names(trimmed)
#> [1] FALSE
```
