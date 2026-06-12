# Common errors and how to fix them

Every error artoo raises carries a class of the form
`artoo_error_<kind>` (plus `artoo_error` and `artoo_condition`, so one
`tryCatch(artoo_error = )` catches them all), and the message names the
fix. This page triggers each kind live and expands the fix. The kinds:
`input`, `spec`, `type`, `codelist`, `codec`, `conformance` (plus
`validation`, which classifies
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md)
internals rather than user-facing aborts).

## `artoo_error_input` — the call is malformed

Wrong argument types, unknown datasets, unknown fields:

``` r

apply_spec(cdisc_dm, sdtm_spec, "NOPE")
```

    Error:
    ! `dataset` must be one of the spec's datasets.
    ✖ "NOPE" is not in the spec.
    ℹ Available: "TS", "DM", "VS", and "SUPPDM".

**Fix:** the message lists what the spec defines; correct the call.

## `artoo_error_spec` — the spec is inconsistent

Cross-slot integrity at construction: a variable referencing an unknown
dataset or codelist, duplicate definitions, mixed standards, disagreeing
study fields:

``` r

artoo_spec(
  data.frame(dataset = "DM"),
  data.frame(dataset = "DM", variable = "SEX", data_type = "string",
             codelist_id = "C99999")
)
```

    Error:
    ! Some variables reference a codelist not in `codelists`.
    ✖ Unresolved codelist_id: "C99999".
    ℹ Add the codelist's terms to `codelists`.

**Fix:** repair the spec source — add the missing slot rows, or scope
the read (`read_spec(path, datasets = )`) to one standard.

## `artoo_error_type` — coercion would lose data

The spec says `integer`; the data carries fractions (or overflows R’s
32-bit range). No `conformance =` setting bypasses this — it is the
package’s core guarantee, and the condition carries the offenders as
data:

``` r

vars <- spec_variables(adam_spec)
vars$data_type[vars$variable == "AGE"] <- "integer"
strict <- artoo_spec(adam_spec@datasets, vars,
                     codelists = adam_spec@codelists)
raw <- cdisc_adsl
raw$AGE[1] <- raw$AGE[1] + 0.5
apply_spec(raw, strict, "ADSL", conformance = "off")
```

    Error:
    ! Coercion to the spec dataTypes would lose data.
    ✖ Integer coercion would truncate fractional values in: AGE (1).
    ℹ This gate is separate from `conformance`; `conformance = "off"` does not
      bypass it.
    ℹ To keep these values in R, set `apply_spec(on_coercion_loss = "keep")`, or
      retype the spec with `set_type()` (dataType "float" or "decimal").
    ℹ To see every finding at once, run `check_spec(x, spec, dataset)`.

**Fix:** retype the spec variable to `"float"` or `"decimal"`. Collect
every offender programmatically with
`tryCatch(..., artoo_error_type = function(cnd) cnd$variables)`.

## `artoo_error_codelist` — values outside the terms

[`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md)
met values absent from the codelist it maps through:

``` r

dm <- cdisc_dm
dm$SEX[1] <- "X9"
decode_column(dm, sdtm_spec, "DM", from = "SEX", to = "SEXDECD")
```

    Error:
    ! Values in `SEX` are not in codelist "CL.SEX".
    ✖ Unmatched: "X9".
    ℹ Set `no_match = "keep"` or `"na"` to allow them.

**Fix:** clean the source values, or pass `no_match = "keep"` / `"na"`
when carrying them through is intended. (If the *codelist* is the
problem — the destination’s terms do not line up with the source values
— translate in two hops; see
[`?decode_column`](https://vthanik.github.io/artoo/reference/decode_column.md).)

## `artoo_error_codec` — the bytes cannot travel

Unencodable values for the target encoding, invalid UTF-8, corrupt or
mis-shaped files:

``` r

dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
```

    1 variable the spec declares is absent from the data (not added): `BRTHDTC`.

``` r

dm$USUBJID[1] <- rawToChar(as.raw(c(0x63, 0xE9)))
write_json(dm, tempfile(fileext = ".json"))
```

    Error in `write_json()`:
    ! Cannot encode 1 value as UTF-8.
    ✖ Invalid bytes (hex-escaped): "c<e9>".
    ℹ Re-read the source with the correct `encoding`, or set `on_invalid`.

**Fix:** re-read the source with its true `encoding =` (see
[`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md)
for the name under each ecosystem), or choose an explicit `on_invalid`
policy on the writer.

## `artoo_error_conformance` — the data does not match the spec

`apply_spec(conformance = "abort")` met error-severity findings:

``` r

dm <- cdisc_dm
dm$SEX[1] <- "X9"
apply_spec(dm, sdtm_spec, "DM", conformance = "abort")
```

    1 variable the spec declares is absent from the data (not added): `BRTHDTC`.
    ℹ See `conformance(x)` for the findings.

    Error:
    ! Data does not conform to the spec for "DM".
    ✖ 'SEX' has 1 value(s) outside codelist 'CL.SEX': X9.

**Fix:** the complete report rides on the condition
(`tryCatch(..., artoo_error_conformance = function(cnd) cnd$findings)`);
fix the data (or the spec) finding by finding. Under the default
`conformance = "warn"` the same report is attached to the returned frame
— read it with `conformance(x)`.

## Where to next

- [Validation &
  qualification](https://vthanik.github.io/artoo/articles/validation.md)
  — the condition system as an evidence surface.
- [An end-to-end ADaM
  build](https://vthanik.github.io/artoo/articles/adam-build.md) — the
  loop these guards protect.
