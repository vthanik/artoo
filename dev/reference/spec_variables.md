# Variables in a spec

Return the variable-metadata table for one dataset, or for the whole
spec. Each row carries the variable's CDISC `data_type`, label, length,
display format, key sequence, and codelist reference.

## Usage

``` r
spec_variables(spec, dataset = NULL)
```

## Arguments

- spec:

  *The specification to read.* `<artoo_spec>: required`.

- dataset:

  *Restrict to one dataset.* `<character(1)> | NULL`. When `NULL`
  (default) every dataset's variables are returned; otherwise only the
  named dataset's rows.

  **Restriction:** a non-`NULL` `dataset` must name a dataset in the
  spec (see
  [`spec_datasets()`](https://vthanik.github.io/artoo/dev/reference/spec_datasets.md));
  an unknown name aborts with `artoo_error_input`.

## Value

*A data frame of variable metadata*, one row per variable, with 22
columns (absent ones are filled with typed `NA` at construction):

- `dataset`, `variable` — the identifying pair (unique within a spec).

- `itemoid` — the Define-XML / Dataset-JSON item OID, when recorded.

- `label` — the variable label (\<= 40 bytes for XPORT v5).

- `data_type` — canonical CDISC dataType (`string`, `integer`,
  `decimal`, `float`, `double`, `boolean`, `date`, `datetime`, `time`,
  `URI`).

- `target_data_type` — `integer`/`decimal` when a temporal variable
  stores as a SAS-epoch numeric; `NA` means ISO 8601 text (`--DTC`).

- `length` — declared storage length (bytes for character).

- `display_format`, `informat` — SAS format / informat strings.

- `key_sequence` — 1-based position in the dataset sort key.

- `order` — column position in the dataset.

- `codelist_id`, `method_id`, `comment_id` — references into the
  codelists / methods / comments slots.

- `mandatory` — logical obligation flag (`NA` is treated as mandatory by
  [`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)).

- `significant_digits` — for `decimal` variables.

- `origin`, `source`, `predecessor`, `assigned_value`, `pages`, `role` —
  Define-XML provenance fields, carried as-is.

Filter or arrange it with ordinary base / `dplyr` verbs.

## See also

[`spec_datasets()`](https://vthanik.github.io/artoo/dev/reference/spec_datasets.md)
for the dataset names;
[`spec_codelists()`](https://vthanik.github.io/artoo/dev/reference/spec_codelists.md)
for a variable's controlled terminology.

## Examples

``` r
spec <- artoo_spec(cdisc_sdtm_datasets, cdisc_sdtm_variables, codelists = cdisc_codelists)

# ---- Example 1: one dataset's variables ----
#
# Pass a dataset name to get just that domain's variables, already
# canonicalised to CDISC dataTypes.
head(spec_variables(spec, "DM")[, c("variable", "label", "data_type")])
#>   variable                             label data_type
#> 1  STUDYID                  Study Identifier    string
#> 2   DOMAIN               Domain Abbreviation    string
#> 3  USUBJID         Unique Subject Identifier    string
#> 4   SUBJID  Subject Identifier for the Study    string
#> 5  RFSTDTC Subject Reference Start Date/Time    string
#> 6  RFENDTC   Subject Reference End Date/Time    string

# ---- Example 2: every variable across the spec ----
#
# Omit `dataset` to get the full table, e.g. to count variables per domain.
table(spec_variables(spec)$dataset)
#> 
#> DM 
#> 25 
```
