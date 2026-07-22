# Validate a specification for submission-readiness

Run artoo's bundled, self-contained checks over a `artoo_spec`, **scoped
to the dataset(s) you are working on**, and return a `artoo_check` that
prints a sectioned report. Every finding is keyed to an open rule in the
shipped catalog (see `spec_rules.json`); the result object keeps the
findings as a plain data frame in `@findings` for programmatic use.

## Usage

``` r
validate_spec(
  spec,
  data = NULL,
  dataset = NULL,
  on_error = c("off", "warn", "abort")
)
```

## Arguments

- spec:

  *The specification to validate.* `<artoo_spec>: required`.

- data:

  *Optional input data for controlled-terminology checks.*
  `<data.frame> | named list | NULL`. When supplied, data values are
  cross-checked against the spec codelists. A single data frame requires
  a length-1 `dataset`; pass a named list to validate several at once.

- dataset:

  *Restrict to one or more datasets.* `<character> | NULL`. `NULL`
  (default) validates every dataset.

  **Restriction:** each name must be a dataset in the spec.

- on_error:

  *What to do with an error-severity finding.* `<character(1)>`. One of:

  - `"off"` (default) collect and return every finding; never signal.

  - `"warn"` additionally `cli_warn` (`artoo_warning_validation`) with
    the error count.

  - `"abort"` additionally abort with `artoo_error_validation`. All
    findings are collected and returned in every case.

## Value

*A `artoo_check` object.* Its `@findings` data frame has columns
`check`, `dimension`, `severity`, `dataset`, `variable`, `message`.
Print it for the sectioned report.

## Details

**Dataset-scoped.** A spec workbook carries many datasets. Pass
`dataset` to validate only the one(s) you are working on — the methods,
comments, and codelists those datasets reference are checked for
completeness, but unrelated datasets are not. `dataset = NULL` validates
the whole spec.

**Collect, do not stop.** Every finding is collected and returned;
`validate_spec()` does not abort on an error-severity finding unless
`on_error = "abort"`.

## See also

[`artoo_spec()`](https://vthanik.github.io/artoo/dev/reference/artoo_spec.md)
to build a spec;
[`spec_methods()`](https://vthanik.github.io/artoo/dev/reference/spec_methods.md)
/
[`spec_comments()`](https://vthanik.github.io/artoo/dev/reference/spec_comments.md)
for the metadata checked.

## Examples

``` r
# ---- Example 1: validate one dataset ----
#
# Build a spec from the bundled ADaM tables and validate it; the
# result prints a sectioned report and keeps the findings table.
spec <- artoo_spec(
  cdisc_adam_datasets, cdisc_adam_variables,
  codelists = cdisc_codelists
)
chk <- validate_spec(spec, dataset = "ADSL")
chk@findings
#>                check dimension severity dataset variable
#> 1 study_name_present     study  warning    <NA>     <NA>
#>                                               message
#> 1 No study-level metadata; the study name is unknown.

# ---- Example 2: gate on errors with on_error = "abort" ----
#
# Point a key at a missing variable, then validate with on_error = "abort"
# and catch the resulting error.
bad_ds <- cdisc_sdtm_datasets
bad_ds$keys <- "NOTAVAR"
bad <- artoo_spec(bad_ds, cdisc_sdtm_variables, codelists = cdisc_codelists)
tryCatch(
  validate_spec(bad, dataset = "DM", on_error = "abort"),
  artoo_error_validation = function(e) conditionMessage(e)[1]
)
#> [1] "\033[1m\033[22mSpec is not submission-ready, 1 error-severity finding.\n\033[31m✖\033[39m Dataset 'DM' keys reference variables not in the spec: NOTAVAR.\n\033[36mℹ\033[39m Inspect every finding in the returned artoo_check."
```
