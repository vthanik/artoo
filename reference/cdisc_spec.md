# CDISC demo specification tables

The dataset-level (`cdisc_datasets`) and variable-level
(`cdisc_variables`) metadata for the bundled `cdisc_adsl` and `cdisc_dm`
datasets, in the shape
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
expects. The variable table is *derived from the data* (names, labels,
inferred CDISC types, byte lengths) by `data-raw/`. Pass both to
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
to build a specification for examples and tests.

## Usage

``` r
cdisc_datasets

cdisc_variables

cdisc_codelists
```

## Format

`cdisc_datasets` is a data frame with one row per dataset:

- dataset:

  Dataset name (`"ADSL"`, `"DM"`).

- label:

  Dataset label.

`cdisc_variables` is a data frame with one row per variable:

- dataset:

  Owning dataset name.

- variable:

  Variable name.

- label:

  Variable label (from the data's `label` attribute).

- data_type:

  CDISC `dataType` inferred from the column's class.

- length:

  Storage length (max byte width for character, 8 for numeric).

- order:

  Variable order within the dataset.

`cdisc_codelists` is a data frame of controlled-terminology terms (the
real NCI codelist C66731 for `SEX`):

- codelist_id:

  Codelist identifier (`"C66731"`).

- term:

  Submission value (`"M"`, `"F"`, ...).

- decode:

  Decoded value (`"Male"`, `"Female"`, ...).

- order:

  Term order.

## Source

Derived from the CDISC pilot `.xpt` files in the public PHUSE Test Data
Factory (`phuse-org/phuse-scripts`) by `data-raw/bundle-demo.R`.
