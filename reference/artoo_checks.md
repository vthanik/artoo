# Control which conformance checks run

Build a reusable control that selects which dimensions
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
evaluates. Construct one per study and thread it through every
check_spec() call so the conformance surface is consistent. Each toggle
is validated at construction, so a mistyped name or value aborts early
rather than being silently ignored.

## Usage

``` r
artoo_checks(
  missing_variable = TRUE,
  missing_permissible = TRUE,
  extra_variable = TRUE,
  type_mismatch = TRUE,
  length_overflow = TRUE,
  char_length_limit = TRUE,
  codelist_membership = TRUE,
  codelist_membership_extensible = TRUE,
  label_match = TRUE,
  key_uniqueness = TRUE,
  display_format = TRUE,
  variable_name = TRUE,
  dataset_name = TRUE,
  label_length = TRUE,
  integer_overflow = TRUE,
  integer_fraction = TRUE,
  iso8601_format = TRUE
)
```

## Arguments

- missing_variable:

  *Flag mandatory spec variables absent from the data.*
  `<logical(1)>: default TRUE`.

- missing_permissible:

  *Flag permissible (non-mandatory) spec variables absent from the
  data.* `<logical(1)>: default TRUE`.

- extra_variable:

  *Flag data columns the spec does not declare.*
  `<logical(1)>: default TRUE`.

- type_mismatch:

  *Flag columns whose storage differs from the spec dataType.*
  `<logical(1)>: default TRUE`.

- length_overflow:

  *Flag character values longer than the spec length.*
  `<logical(1)>: default TRUE`.

- char_length_limit:

  *Flag character values longer than the SAS XPORT v5 / FDA 200-byte
  limit.* `<logical(1)>: default TRUE`.

- codelist_membership:

  *Flag values outside their closed codelist.*
  `<logical(1)>: default TRUE`.

- codelist_membership_extensible:

  *Flag values outside an extensible codelist's enumerated terms.*
  `<logical(1)>: default TRUE`. A codelist whose `extended` flag is
  `TRUE` allows sponsor terms, so a non-member is a note, never an
  error; this toggle silences those notes independently of
  `codelist_membership`.

- label_match:

  *Flag a column whose label attribute differs from the spec label.*
  `<logical(1)>: default TRUE`.

- key_uniqueness:

  *Flag a dataset whose spec key variables do not uniquely identify its
  rows.* `<logical(1)>: default TRUE`.

- display_format:

  *Flag a date/datetime/time variable whose displayFormat is not a
  recognized SAS format of that family.* `<logical(1)>: default TRUE`.

- variable_name:

  *Flag a data column name that violates the XPORT naming rules.*
  `<logical(1)>: default TRUE`. Over 8 characters (the v5 limit), over
  32 (the v8 limit), or containing anything but ASCII letters, digits,
  and underscore.

- dataset_name:

  *Flag a dataset name that violates the XPORT naming rules.*
  `<logical(1)>: default TRUE`. Same limits as `variable_name`.

- label_length:

  *Flag a column label attribute over the 40-byte XPORT v5 / FDA limit.*
  `<logical(1)>: default TRUE`.

- integer_overflow:

  *Flag an integer-typed variable holding values beyond R's 32-bit
  integer range.* `<logical(1)>: default TRUE`. Such values become `NA`
  under coercion, so this is an error, not a warning.

- integer_fraction:

  *Flag an integer-typed variable holding fractional values.*
  `<logical(1)>: default TRUE`. Coercion would truncate them (162.6
  becomes 162) – a data-integrity event; fix the spec dataType (`float`
  / `decimal`) or the data before conforming.

- iso8601_format:

  *Flag a character date/datetime/time variable whose values are not
  valid ISO 8601 text.* `<logical(1)>: default TRUE`. A character column
  under a temporal dataType is the CDISC `--DTC` form; complete values,
  right-truncated partials (`"1951"`, `"1951-12"`), and SDTMIG hyphen
  placeholders (`"2003---15"`) all pass, while `"12NOV2019"` or an
  impossible calendar date is flagged.

## Value

*A `<artoo_checks>` control object*. Pass it as the `checks` argument to
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md).

## Details

**Selection, not severity.** This control decides which findings are
*produced*;
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)'s
`conformance` argument (warn, abort, off) decides what to *do* with the
findings its full-default check raises. A disabled dimension is skipped
entirely, so the findings frame stays clean.

## See also

[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md),
which consumes it;
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
for the findings disposition.

## Examples

``` r
# ---- Example 1: the default runs every conformance dimension ----
#
# With no arguments, every conformance dimension is enabled.
artoo_checks()
#> <artoo_checks>
#>   [x] missing_variable
#>   [x] missing_permissible
#>   [x] extra_variable
#>   [x] type_mismatch
#>   [x] length_overflow
#>   [x] char_length_limit
#>   [x] codelist_membership
#>   [x] codelist_membership_extensible
#>   [x] label_match
#>   [x] key_uniqueness
#>   [x] display_format
#>   [x] variable_name
#>   [x] dataset_name
#>   [x] label_length
#>   [x] integer_overflow
#>   [x] integer_fraction
#>   [x] iso8601_format

# ---- Example 2: silence one dimension for a whole study ----
#
# Turn off the length check (e.g. while a spec's lengths are provisional)
# and reuse the control across every dataset.
spec <- artoo_spec(cdisc_sdtm_datasets, cdisc_sdtm_variables, codelists = cdisc_codelists)
ck <- artoo_checks(length_overflow = FALSE)
nrow(check_spec(cdisc_dm, spec, "DM", checks = ck))
#> [1] 0
```
