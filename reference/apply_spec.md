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
  extra = c("keep", "drop"),
  on_coercion_loss = c("error", "keep")
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
  every setting, including `"off"`: an unknown dataset, and lossy
  coercion (`artoo_error_type`). Lossy coercion has its own governed
  gate, `on_coercion_loss`, not this argument; when the spec is the
  problem, retype it with
  [`set_type()`](https://vthanik.github.io/artoo/reference/set_type.md).

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
    drop is announced (`artoo_message_apply`), and that message is the
    audit trail of what was removed.

  **Interaction:** the drop runs *before* the check, so
  [`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md)
  reports only the columns the returned frame keeps. Under
  `conformance = "abort"` an error-severity finding still aborts (those
  findings arise only on spec-declared columns, which the drop never
  touches) and the input is never mutated, so the trim cannot mask a
  failure.

  **Note:** `"keep"` is the default deliberately. artoo is a lossless
  carrier, so the metadata step never silently discards a column; extras
  are surfaced every run (the `extra_variable` finding, and a warning
  under `conformance = "warn"`), making `"drop"` a conscious opt-in.

- on_coercion_loss:

  *What to do when coercion would lose data.* `<character(1)>`. The
  governed gate for an `integer` dataType whose data truncates
  (fractions) or overflows (R's 32-bit range). One of:

  - `"error"` (default) abort with `artoo_error_type` before any value
    is touched, refusing to damage the data.

  - `"keep"` skip coercion for the offending column, leaving it at its
    wider source type. The values are preserved and the mismatch is
    reported as an `integer_fraction` / `integer_overflow` finding (read
    with
    [`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md)),
    never silently truncated.

  **Interaction:** independent of `conformance`. `"error"` aborts even
  under `conformance = "off"`; under `"keep"` the finding it leaves is
  surfaced by `conformance = "warn"` (the default) and suppressed by
  `"off"`.

  **Tip:** `"keep"` is the iterate stance (preserve the data, flag the
  spec); `"error"` is the submission stance. To fix the spec itself, see
  [`set_type()`](https://vthanik.github.io/artoo/reference/set_type.md)
  and
  [`repair_spec()`](https://vthanik.github.io/artoo/reference/repair_spec.md).

## Value

*A conformed `<data.frame>`* carrying `artoo_meta` (read it with
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md))
and, unless `conformance = "off"`, the findings frame
[`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md)
reads back. Hand it to any `write_*()` codec.

## Details

**Ordered pipeline.** Four fixed steps run in order: coerce each column
to its CDISC dataType, reorder columns to the spec, sort rows by the
dataset keys, then stamp the metadata. A spec variable the data lacks is
never fabricated as an empty column: artoo is a lossless carrier, not a
deriver. It is reported instead, an informational heads-up at apply time
plus a `missing_variable` finding (when mandatory) or
`missing_permissible` (when not), and left absent, so the conformed
frame carries only the columns the data actually had.

**Extras are kept by default.** A column the spec does not declare
survives the pipeline (ordered after the declared ones), is *reported*
by the `extra_variable` conformance finding, and round-trips through
every `write_*()` codec with metadata inferred from its R class —
membership reported, never enforced by silent destruction. Keeping is
the default because artoo is lossless by construction: a
metadata-application step that silently discarded columns would break
that contract, so trimming data is always an explicit, announced choice
rather than a default side effect. `extra = "drop"` opts in to
trim-to-spec (the returned frame carries exactly the spec's columns):
the undeclared columns are removed *before* the check, so the findings
describe exactly the returned frame (a dropped column is never reported
as `extra_variable`), and the drop itself is always announced
(`artoo_message_apply`) as the audit trail of what was removed — even
under `conformance = "off"`.

**Lossless or abort, your call.** A coercion that would damage values —
an `integer` dataType truncating fractions or overflowing R's 32-bit
range — aborts with `artoo_error_type` before any value is touched,
under the default `on_coercion_loss = "error"`. This gate is independent
of `conformance`: `conformance = "off"` does not bypass it. When the
data (not the spec) is right, set `on_coercion_loss = "keep"`: the
column keeps its wider source type and the divergence is reported as an
`integer_fraction` / `integer_overflow` finding, never silently
truncated. When the spec is wrong, retype it with
[`set_type()`](https://vthanik.github.io/artoo/reference/set_type.md)
(or
[`repair_spec()`](https://vthanik.github.io/artoo/reference/repair_spec.md)
from the findings). The error abort carries the offending rows as data:
`cnd$variables` is a data frame with columns `variable`, `data_type`,
`n`, and `reason` (`"truncated"` / `"overflowed"`), so a pipeline can
collect every mismatch in one
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

**Fix the spec:**
[`set_type()`](https://vthanik.github.io/artoo/reference/set_type.md) to
retype a variable the data disagrees with,
[`repair_spec()`](https://vthanik.github.io/artoo/reference/repair_spec.md)
to apply every integer fix from a findings frame.

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
# The bundled adam_spec describes ADSL; the raw frame is coerced,
# ordered, sorted, and stamped with the CDISC metadata get_meta() reads
# back. Variables the spec declares but this extract never derived are
# reported (not added), readable via conformance().
adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL")
#> 6 variables the spec declares are absent from the data (not added):
#> `TRTDURD`, `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.
#> ℹ See `conformance(x)` for the findings.
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
#> 1 variable the spec declares is absent from the data (not added):
#> `BRTHDTC`.
#> ℹ See `conformance(x)` for the findings.
findings <- conformance(dm)
findings[findings$check == "extra_variable", c("variable", "message")]
#>    variable                                        message
#> 2  RFXSTDTC Column 'RFXSTDTC' is not declared in the spec.
#> 3  RFXENDTC Column 'RFXENDTC' is not declared in the spec.
#> 4   RFICDTC  Column 'RFICDTC' is not declared in the spec.
#> 5  RFPENDTC Column 'RFPENDTC' is not declared in the spec.
#> 6    DTHDTC   Column 'DTHDTC' is not declared in the spec.
#> 7     DTHFL    Column 'DTHFL' is not declared in the spec.
#> 8  ACTARMCD Column 'ACTARMCD' is not declared in the spec.
#> 9    ACTARM   Column 'ACTARM' is not declared in the spec.
#> 10    DMDTC    Column 'DMDTC' is not declared in the spec.
#> 11     DMDY     Column 'DMDY' is not declared in the spec.
#> 12  DERIVED  Column 'DERIVED' is not declared in the spec.
trimmed <- apply_spec(raw, sdtm_spec, "DM", extra = "drop")
#> 1 variable the spec declares is absent from the data (not added):
#> `BRTHDTC`.
#> ℹ See `conformance(x)` for the findings.
#> Dropped 11 undeclared variables: `RFXSTDTC`, `RFXENDTC`, `RFICDTC`,
#> `RFPENDTC`, `DTHDTC`, `DTHFL`, `ACTARMCD`, `ACTARM`, `DMDTC`, `DMDY`,
#> and `DERIVED`
"DERIVED" %in% names(trimmed)
#> [1] FALSE
```
