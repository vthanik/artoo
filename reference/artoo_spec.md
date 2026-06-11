# Construct a CDISC specification

Build and validate a `artoo_spec` from dataset, variable, and codelist
tables. Each table is coerced to a plain data frame, missing optional
columns are filled with typed `NA`s, every variable type is
canonicalised to the CDISC `dataType` vocabulary, and cross-slot
integrity (dataset and codelist references) is checked before the object
is returned. The spec is the lingua franca the rest of artoo reads,
applies, and serialises.

## Usage

``` r
artoo_spec(
  datasets = NULL,
  variables = NULL,
  codelists = NULL,
  study = NULL,
  values = NULL,
  methods = NULL,
  comments = NULL,
  documents = NULL,
  standard = NULL
)
```

## Arguments

- datasets:

  *Dataset-level metadata table.* `<data.frame>: required`. One row per
  dataset; must carry a `dataset` column. Optional columns `label`,
  `class`, `structure`, `keys` are filled with `NA` when absent.

- variables:

  *Variable-level metadata table.* `<data.frame>: required`. One row per
  variable; must carry `dataset`, `variable`, and `data_type`. The
  `data_type` column is canonicalised to a CDISC `dataType` (e.g.
  `"text"` becomes `"string"`).

  **Requirement:** every `dataset` value must appear in `datasets`.

- codelists:

  *Controlled-terminology terms.* `<data.frame> | NULL`. Must carry
  `codelist_id` and `term` when supplied.

  **Interaction:** every `codelist_id` referenced by `variables` must
  resolve here.

- study:

  *Study-level metadata.* `<data.frame> | NULL`. A single row of named
  study fields (e.g. `studyid`). A `standard` field, when present, is
  consumed into `@standard`.

- values:

  *Value-level (VLM) metadata.* `<data.frame> | NULL`.

- methods:

  *Derivation methods.* `<data.frame> | NULL`. The Define-XML method
  definitions variables reference by `method_id`; must carry `method_id`
  when supplied. Completeness (e.g. a referenced method has a
  description) is checked by
  [`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md),
  not here.

- comments:

  *Comment definitions.* `<data.frame> | NULL`. Referenced by
  `comment_id`; must carry `comment_id` when supplied.

- documents:

  *Document references.* `<data.frame> | NULL`. Referenced by
  `document_id`; must carry `document_id` when supplied.

- standard:

  *The CDISC standard the spec implements.* `<character(1)> | NULL`.
  E.g. `"ADaMIG 1.1"` or `"SDTMIG 3.2"`. When `NULL` (default) it is
  resolved from `datasets$standard` or `study$standard`; absent
  everywhere, `@standard` is `NA`.

  **Restriction:** all sources must agree on one value; conflicting
  standards abort with `artoo_error_spec`.

## Value

*A validated `artoo_spec` object.* Inspect it with
[`spec_datasets()`](https://vthanik.github.io/artoo/reference/spec_datasets.md)
/
[`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md),
or check it with
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md).

## Details

**Coerce, then validate.** Each table is first coerced to a plain data
frame (a `tibble` is accepted and demoted); known columns are cast to
their storage mode and absent optional columns are added as typed `NA`,
so every downstream reader can trust the schema. Validation runs only
after coercion, on the completed slots.

**Type canonicalisation.** `variables$data_type` is mapped through the
closed CDISC `dataType` vocabulary (`string`, `integer`, `decimal`,
`float`, `double`, `boolean`, `date`, `datetime`, `time`, `URI`). Common
SAS / P21 spellings resolve automatically (`"text"`, `"Char"`,
`"integer (8)"`, ...); an unrecognised token aborts with
`artoo_error_type`.

**Cross-slot integrity.** Construction fails (`artoo_error_spec`) if a
variable names a dataset absent from `datasets`, or references a
`codelist_id` absent from `codelists`.

**One spec, one standard.** A `artoo_spec` carries exactly one CDISC
standard, stored as the scalar `@standard` property. The constructor
resolves it from the `standard` argument, a `standard` column in
`datasets` (the P21 workbook shape), and a `standard` field in `study`
(the Define-XML shape) – those columns are consumed, so `@standard` is
the single home. More than one distinct value aborts with
`artoo_error_spec`; scope the source to one standard (e.g.
`read_spec(path, datasets = ...)`) instead of mixing.

## See also

**Inspect:**
[`spec_datasets()`](https://vthanik.github.io/artoo/reference/spec_datasets.md),
[`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md),
[`spec_codelists()`](https://vthanik.github.io/artoo/reference/spec_codelists.md),
[`spec_keys()`](https://vthanik.github.io/artoo/reference/spec_keys.md),
[`spec_study()`](https://vthanik.github.io/artoo/reference/spec_study.md).

**Check:**
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md).
**Predicate:**
[`is_artoo_spec()`](https://vthanik.github.io/artoo/reference/is_artoo_spec.md).

## Examples

``` r
# ---- Example 1: build a spec from the bundled CDISC-pilot tables ----
#
# `cdisc_sdtm_datasets` and `cdisc_sdtm_variables` hold the CDISC pilot ADaM
# metadata in the shape artoo_spec() expects; the constructor
# canonicalises every type and checks cross-slot integrity.
spec <- artoo_spec(cdisc_sdtm_datasets, cdisc_sdtm_variables, codelists = cdisc_codelists)
spec_datasets(spec)
#> [1] "DM"

# ---- Example 2: a focused spec for a single dataset ----
#
# Slice the bundled tables to one dataset (DM) to build a smaller spec.
dm_ds <- cdisc_sdtm_datasets[cdisc_sdtm_datasets$dataset == "DM", ]
dm_var <- cdisc_sdtm_variables[cdisc_sdtm_variables$dataset == "DM", ]
dm_spec <- artoo_spec(dm_ds, dm_var, codelists = cdisc_codelists)
head(spec_variables(dm_spec, "DM")[, c("variable", "label", "data_type")])
#>   variable                             label data_type
#> 1  STUDYID                  Study Identifier    string
#> 2   DOMAIN               Domain Abbreviation    string
#> 3  USUBJID         Unique Subject Identifier    string
#> 4   SUBJID  Subject Identifier for the Study    string
#> 5  RFSTDTC Subject Reference Start Date/Time    string
#> 6  RFENDTC   Subject Reference End Date/Time    string
```
