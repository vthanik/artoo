# CDISC demo specification tables (one standard per pair)

The constructor-shaped metadata tables for the bundled demo data, split
by CDISC standard because a `artoo_spec` carries exactly one:
`cdisc_adam_datasets` + `cdisc_adam_variables` describe ADSL (ADaMIG
1.1), and `cdisc_sdtm_datasets` + `cdisc_sdtm_variables` describe DM
(SDTMIG 3.1.2). Each variables table is *derived from the data* (names,
labels, inferred CDISC types, byte lengths) by `data-raw/`. Pass one
standard's pair to
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md);
passing both pairs together aborts with `artoo_error_spec` — mixing
standards in one spec is the mistake the split exists to prevent.

## Usage

``` r
cdisc_adam_datasets

cdisc_adam_variables

cdisc_sdtm_datasets

cdisc_sdtm_variables

cdisc_codelists
```

## Format

Each `*_datasets` table is a data frame with one row per dataset:

- dataset:

  Dataset name (`"ADSL"` or `"DM"`).

- label:

  Dataset label.

- standard:

  The CDISC standard, consumed into the spec's
  [`spec_standard()`](https://vthanik.github.io/artoo/reference/spec_standard.md).

Each `*_variables` table is a data frame with one row per variable:

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

- codelist_id:

  NCI codelist reference (`"C66731"` on `SEX`).

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
