# Override a variable's dataType in a spec

Return a new `artoo_spec` with one or more variables retyped. This is
the supported, in-R way to correct a spec when the data disagrees with
its declared `dataType` (e.g. a variable typed `integer` whose extract
holds fractional values): fix it here rather than editing the source
workbook, then drive
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
with the corrected spec. The spec is immutable, so the original is never
changed.

## Usage

``` r
set_type(spec, dataset, ...)
```

## Arguments

- spec:

  *The specification to amend.* `<artoo_spec>: required`.

- dataset:

  *The dataset whose variables to retype.* `<character(1)>: required`.
  Must name a dataset in `spec`.

- ...:

  *Named `variable = type` pairs.* Each name is a variable in `dataset`;
  each value is a CDISC `dataType` (`"string"`, `"integer"`,
  `"decimal"`, `"float"`, `"double"`, `"boolean"`, `"date"`,
  `"datetime"`, `"time"`, `"URI"`) or a recognised spelling of one. At
  least one pair is required and every argument must be named.

  **Tip:** to undo an `integer` dataType that the data does not satisfy,
  set `"float"` (IEEE double) or `"decimal"` (exact, exchanged as text).

## Value

*A new `<artoo_spec>`* with the named variables retyped, ready for
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
or
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md).
The input `spec` is unchanged.

## Details

**Per-dataset scope.** A type is set only on the named `dataset`'s row.
A variable that appears in several datasets keeps its other rows' types;
call `set_type()` once per dataset to change them all. Spec-wide
consequences (a variable typed inconsistently across datasets) are a
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md)
concern, not a construction error here.

**Canonicalised, then validated.** Each supplied type is mapped through
the closed CDISC `dataType` vocabulary, so `"Float"`, `"decimal"`, and
`"text"` all resolve; an unrecognised token aborts with
`artoo_error_type`. The rebuilt spec is re-validated, so an override
that would break the spec aborts with `artoo_error_spec`.

## See also

**Auto-repair:**
[`repair_spec()`](https://vthanik.github.io/artoo/reference/repair_spec.md)
to apply every `integer_fraction` / `integer_overflow` fix from a
findings frame at once.

**Workflow:**
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
to conform with the corrected spec;
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md)
to persist it;
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
to find the mismatches.

## Examples

``` r
# ---- Example 1: retype one variable the data disagrees with ----
#
# The bundled adam_spec types ADSL.AGE as integer. If an extract stored it
# with fractional values, retype it to float so apply_spec() coerces
# without loss. set_type() returns a new spec; the original is untouched.
fixed <- set_type(adam_spec, "ADSL", AGE = "float")
v <- spec_variables(fixed, "ADSL")
v[v$variable == "AGE", c("variable", "data_type")]
#>    variable data_type
#> 16      AGE     float

# ---- Example 2: retype several at once, original left intact ----
#
# Pass any number of variable = type pairs; canonical dataTypes and common
# spellings both resolve. The source spec is immutable, so adam_spec still
# reports AGE as its original type.
patched <- set_type(adam_spec, "ADSL", AGE = "decimal", TRTSDT = "date")
spec_variables(adam_spec, "ADSL")$data_type[
  spec_variables(adam_spec, "ADSL")$variable == "AGE"
]
#> [1] "integer"
```
