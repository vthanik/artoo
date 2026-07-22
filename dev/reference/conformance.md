# Read the conformance findings a dataset carries

Pull the conformance findings
[`apply_spec()`](https://vthanik.github.io/artoo/dev/reference/apply_spec.md)
attached to a conformed data frame — the readable answer to "what did
the check find?". The result is the same findings frame
[`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)
returns (one row per divergence), with a print method that renders a
sectioned report, so `conformance(adsl)` at the console is the
inspection step the `artoo_warning_conformance` warning points you at.

## Usage

``` r
conformance(x)
```

## Arguments

- x:

  *A data frame produced by
  [`apply_spec()`](https://vthanik.github.io/artoo/dev/reference/apply_spec.md).*
  `<data.frame>: required`.

  **Requirement:** the conformance check must have run: a frame from
  `apply_spec(..., conformance = "off")` (or one rebuilt by a transform
  that dropped attributes) carries no findings and aborts with
  `artoo_error_input`.

## Value

*A `<artoo_findings>` data frame* with columns `check`, `dimension`,
`severity` (`"error"`, `"warning"`, or `"note"`), `dataset`, `variable`,
and `message`. Zero rows means the data conformed. Print it for the
sectioned report; treat it as an ordinary data frame for programmatic
use.

## See also

[`apply_spec()`](https://vthanik.github.io/artoo/dev/reference/apply_spec.md)
which attaches the findings;
[`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)
for the same check on demand;
[`artoo_checks()`](https://vthanik.github.io/artoo/dev/reference/artoo_checks.md)
to select dimensions.

## Examples

``` r
spec <- artoo_spec(
  cdisc_sdtm_datasets, cdisc_sdtm_variables,
  codelists = cdisc_codelists
)

# ---- Example 1: inspect what the conform step found ----
#
# Conforming raw DM records the findings on the result; conformance()
# renders them as a report instead of a raw attribute.
dm <- suppressWarnings(apply_spec(cdisc_dm, spec, "DM"))
conformance(dm)
#> <artoo_findings>: 0 errors, 0 warnings, 0 notes
#> No findings. The data conforms to the spec.

# ---- Example 2: gate a pipeline on error-severity findings ----
#
# The findings frame is an ordinary data frame: filter by severity to
# drive your own logic.
f <- conformance(dm)
nrow(f[f$severity == "error", ])
#> [1] 0
```
