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
  standard = NULL,
  standards = NULL,
  where_clauses = NULL,
  method_expressions = NULL,
  arm_displays = NULL,
  arm_results = NULL,
  dictionaries = NULL
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
  study fields. Well-known fields are canonicalised to `study_name`,
  `study_description`, and `protocol_name` (aliases such as `StudyName`
  or `studyid` resolve automatically); other fields pass through
  verbatim. A `standard` field, when present, is consumed into
  `@standard`.

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

  *The primary CDISC standard the spec implements.*
  `<character(1)> | NULL`. E.g. `"ADaMIG 1.1"` or `"SDTMIG 3.2"`. When
  `NULL` (default) it is resolved from `study$standard`, or from the
  value most rows of `datasets$standard` name; absent everywhere,
  `@standard` is `NA`.

  **Restriction:** an explicit value that matches nothing the source
  names aborts with `artoo_error_spec`.

- standards:

  *CDISC standards this spec claims.* `<data.frame> | NULL`. Must carry
  `standard_id`, `name` and `version`. Define-XML 2.1 emits these as a
  `def:Standards` block that datasets and codelists reference by id; 2.0
  has room for only one, taken from the row flagged `is_primary`.

- where_clauses:

  *Structured value-level conditions.* `<data.frame> | NULL`. Must carry
  `where_clause_id` and `comparator`. One row per check value, because a
  check value is free text and may itself contain a comma, so any
  collapsed form would be lossy.

- method_expressions:

  *Formal expressions for derivation methods.* `<data.frame> | NULL`.
  Must carry `method_id`. A separate table because a method may carry
  several expressions in different languages, which extra rows on
  `methods` could not express without changing what the published
  one-row-per-method rule means.

- arm_displays:

  *Analysis result displays.* `<data.frame> | NULL`. Must carry
  `display_id`. Analysis Results Metadata is version-neutral: the
  vocabulary is identical for Define-XML 2.0 and 2.1.

- arm_results:

  *Analysis results.* `<data.frame> | NULL`. Must carry `display_id` and
  `result_id`. One row per result and analysis dataset, since each
  analysis dataset carries its own where-clause reference.

- dictionaries:

  *External codelists.* `<data.frame> | NULL`. Must carry
  `dictionary_id`. A terminology too large to enumerate, named rather
  than listed: MedDRA, WHODrug, ISO 3166. Both readers populate it, and
  a variable points at one from the same `codelist_id` column it would
  use for an enumerated list.

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

**One primary standard, linked per dataset.** The scalar `@standard`
property holds the spec's primary CDISC standard, resolved from the
`standard` argument, a `standard` column in `datasets` (the P21 workbook
shape), and a `standard` field in `study` (the Define-XML shape) — those
columns are consumed, so `@standard` is the single home. A `datasets`
column naming several standards is legitimate (a study may mix
implementation-guide versions): each row is linked to its standard via
`datasets$standard_id`, minting a `standards` row where none defines the
name, and `@standard` takes the study's stated standard, or failing that
the one most datasets name. An explicit `standard` argument
contradicting every value in the source aborts with `artoo_error_spec`.

**One study vocabulary.** Well-known study fields are canonicalised to
the CDISC ODM GlobalVariables names, snake_cased: `study_name`,
`study_description`, `protocol_name`. Source spellings resolve
automatically (`StudyName`, `studyid`, ...); fields the vocabulary does
not know pass through verbatim. Aliases that disagree on a value abort
with `artoo_error_spec`.

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
# `cdisc_sdtm_datasets` and `cdisc_sdtm_variables` hold the CDISC pilot SDTM
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
