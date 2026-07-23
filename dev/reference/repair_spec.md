# Repair a spec from its conformance findings

Take the `integer_fraction` and `integer_overflow` findings a
[`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)
or
[`check_study()`](https://vthanik.github.io/artoo/dev/reference/check_study.md)
run reports and return a new spec with every offending variable retyped
to `"float"`, so a frame that the original spec would refuse to coerce
now conforms. This closes the loop on the spec-side fix: inspect the
findings, then apply them all at once instead of editing the source
workbook variable by variable. Persist the result with
[`write_spec()`](https://vthanik.github.io/artoo/dev/reference/write_spec.md).

## Usage

``` r
repair_spec(spec, findings)
```

## Arguments

- spec:

  *The specification to repair.* `<artoo_spec>: required`.

- findings:

  *A findings data frame.* `<data.frame>: required`. The result of
  [`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)
  or
  [`check_study()`](https://vthanik.github.io/artoo/dev/reference/check_study.md);
  must carry the `check`, `dataset`, and `variable` columns.

## Value

*A new `<artoo_spec>`* with the flagged variables retyped to `"float"`,
or `spec` unchanged when there is nothing to repair. The input is never
mutated.

## Details

**Scope.** Only the two lossy-integer findings are repaired
(`integer_fraction`, `integer_overflow`) — both mean "the spec says
`integer` but the data is not", and `"float"` is the loss-free fix.
Other findings are ignored; this is not a general spec rewriter. When no
repairable finding is present the spec is returned unchanged, with a
note.

**Built on
[`set_type()`](https://vthanik.github.io/artoo/dev/reference/set_type.md).**
Each `(dataset, variable)` pair is applied through the same validated
override
[`set_type()`](https://vthanik.github.io/artoo/dev/reference/set_type.md)
uses, so the result is a fully re-validated `artoo_spec`, never a
hand-edited internal.

## See also

**Primitive:**
[`set_type()`](https://vthanik.github.io/artoo/dev/reference/set_type.md)
to retype a chosen variable directly.

**Findings:**
[`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)
for one dataset,
[`check_study()`](https://vthanik.github.io/artoo/dev/reference/check_study.md)
across a study. **Persist:**
[`write_spec()`](https://vthanik.github.io/artoo/dev/reference/write_spec.md).

## Examples

``` r
# ---- Example 1: auto-repair an integer/fractional mismatch ----
#
# adam_spec types ADSL.AGE as integer. Give it fractional ages and
# check_spec() raises an integer_fraction error; repair_spec() flips AGE
# (and only AGE) to float, and the corrected spec then applies cleanly.
dat <- cdisc_adsl
dat$AGE <- dat$AGE + 0.5
findings <- check_spec(dat, adam_spec, "ADSL")
fixed <- repair_spec(adam_spec, findings)
spec_variables(fixed, "ADSL")$data_type[
  spec_variables(fixed, "ADSL")$variable == "AGE"
]
#> [1] "float"

# ---- Example 2: nothing to repair is a no-op ----
#
# The bundled data conforms, so its findings carry no integer_fraction or
# integer_overflow rows and the spec is returned unchanged.
clean <- check_spec(cdisc_adsl, adam_spec, "ADSL")
identical(repair_spec(adam_spec, clean), adam_spec)
#> No "integer_fraction" or "integer_overflow" findings to repair.
#> ℹ The spec is returned unchanged.
#> [1] TRUE
```
