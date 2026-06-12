# Check a whole study against its spec

Run
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
over every dataset in a study and return one stacked findings frame.
Where
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
answers "does this dataset conform?", `check_study()` answers "is my
whole study submittable?" in a single pass, surfacing every dataset's
divergences at once instead of one abort at a time. The result is an
ordinary findings frame underneath, so filter it by severity or hand it
straight to
[`repair_spec()`](https://vthanik.github.io/artoo/reference/repair_spec.md).

## Usage

``` r
check_study(
  spec,
  data,
  decode = c("none", "to_decode", "to_code"),
  checks = NULL
)
```

## Arguments

- spec:

  *The specification to check against.* `<artoo_spec>: required`.

- data:

  *The study's datasets.* `<named list of data.frame>: required`. One
  entry per dataset, named by the dataset (e.g.
  `list(ADSL = adsl, ADAE = adae)`). Every name must be a dataset in
  `spec`.

- decode:

  *Which codelist column to check against.* `<character(1)>`. Passed to
  [`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md);
  one of `"none"` (default), `"to_decode"`, `"to_code"`.

- checks:

  *Which conformance dimensions to run.* `<artoo_checks> | NULL`. Passed
  to
  [`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md);
  `NULL` (default) runs every dimension. Build a subset with
  [`artoo_checks()`](https://vthanik.github.io/artoo/reference/artoo_checks.md).

## Value

*A `<artoo_study_findings>` data frame* with the same columns as
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
(`check`, `dimension`, `severity`, `dataset`, `variable`, `message`),
one row per divergence across all datasets. Zero rows means the whole
study conforms. Print it for the count matrix; treat it as an ordinary
data frame otherwise.

## Details

**One row per divergence, every dataset stacked.** Each dataset's
findings carry its name in the `dataset` column, so the frame is the
union of the per-dataset
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
results. Printing renders the dataset-by-check count matrix (the
study-level summary); the underlying frame is unchanged.

**Data-requiring, like
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md).**
`check_study()` checks data against the spec, so it needs the data
frames. For the spec's own structural integrity (no data), use
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md).

## See also

**One dataset:**
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md).
**Spec structure only:**
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md).

**Repair:**
[`repair_spec()`](https://vthanik.github.io/artoo/reference/repair_spec.md)
to apply the integer fixes the matrix surfaces.

## Examples

``` r
# ---- Example 1: scan a whole study in one pass ----
#
# Loop the conformance check over every dataset's data. A fractional AGE
# (the spec types it integer) surfaces as an integer_fraction finding; the
# print is a dataset-by-check count matrix.
adsl <- cdisc_adsl
adsl$AGE <- adsl$AGE + 0.5
check_study(adam_spec, list(ADSL = adsl, ADAE = cdisc_adae))
#> <artoo_study_findings> 2 datasets: 1 error, 11 warnings, 39 notes
#> 
#>      codelist_membership_extensible extra_variable integer_fraction
#> ADAE                              0              0                0
#> ADSL                              1              5                1
#>      label_match missing_permissible type_mismatch
#> ADAE           7                   0            17
#> ADSL           3                   6            11
#> 
#> i Treat this as a findings frame: filter by severity, or pass it to repair_spec().

# ---- Example 2: feed the findings straight into repair_spec() ----
#
# The result is an ordinary findings frame, so repair_spec() consumes it to
# flip every integer_fraction / integer_overflow variable across the study.
findings <- check_study(adam_spec, list(ADSL = adsl))
fixed <- repair_spec(adam_spec, findings)
spec_variables(fixed, "ADSL")$data_type[
  spec_variables(fixed, "ADSL")$variable == "AGE"
]
#> [1] "float"
```
