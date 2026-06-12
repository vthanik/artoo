# Package index

## Specification

Build a artoo_spec — the canonical CDISC-shaped description of your
datasets, one CDISC standard each — or read one from native JSON, a
Pinnacle 21 workbook, or Define-XML, and write it back out. Amend it in
R when the data disagrees: retype a variable, or repair every integer
mismatch a check surfaced.

- [`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
  : Construct a CDISC specification
- [`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
  : Read a specification from JSON, Excel, or Define-XML
- [`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md)
  : Write a specification to native JSON or a P21 Excel workbook
- [`set_type()`](https://vthanik.github.io/artoo/reference/set_type.md)
  : Override a variable's dataType in a spec
- [`repair_spec()`](https://vthanik.github.io/artoo/reference/repair_spec.md)
  : Repair a spec from its conformance findings
- [`is_artoo_spec()`](https://vthanik.github.io/artoo/reference/is_artoo_spec.md)
  : Test for a artoo_spec object

## Spec accessors

One slot each from the spec — the standard, the study block, and the
per-dataset metadata tables.

- [`spec_standard()`](https://vthanik.github.io/artoo/reference/spec_standard.md)
  : The CDISC standard a spec implements
- [`spec_study()`](https://vthanik.github.io/artoo/reference/spec_study.md)
  : Study-level metadata
- [`spec_datasets()`](https://vthanik.github.io/artoo/reference/spec_datasets.md)
  : Dataset names in a spec
- [`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md)
  : Variables in a spec
- [`spec_codelists()`](https://vthanik.github.io/artoo/reference/spec_codelists.md)
  : Codelist terms
- [`spec_keys()`](https://vthanik.github.io/artoo/reference/spec_keys.md)
  : Sort keys for a dataset
- [`spec_methods()`](https://vthanik.github.io/artoo/reference/spec_methods.md)
  : Derivation methods in a spec
- [`spec_comments()`](https://vthanik.github.io/artoo/reference/spec_comments.md)
  : Comment definitions in a spec
- [`spec_documents()`](https://vthanik.github.io/artoo/reference/spec_documents.md)
  : Document references in a spec

## Conform

Apply the spec to a raw frame — coerce, order, sort, stamp metadata —
and derive single variables through spec codelists.

- [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
  : Conform a data frame to its spec
- [`decode_column()`](https://vthanik.github.io/artoo/reference/decode_column.md)
  : Derive or translate a variable through its codelist

## Metadata

The artoo_meta every conformed frame carries: read it, replace it, and
keep it in step with the data.

- [`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)
  : Read the metadata a dataset carries
- [`set_meta()`](https://vthanik.github.io/artoo/reference/set_meta.md)
  : Attach metadata to a dataset
- [`sync_meta()`](https://vthanik.github.io/artoo/reference/sync_meta.md)
  : Re-align metadata with a transformed data frame
- [`is_artoo_meta()`](https://vthanik.github.io/artoo/reference/is_artoo_meta.md)
  : Test for a artoo_meta object

## Check

Conformance findings for the data — one dataset or a whole study —
integrity findings for the spec itself, and the control object that
scopes both.

- [`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
  : Check a dataset against its spec
- [`check_study()`](https://vthanik.github.io/artoo/reference/check_study.md)
  : Check a whole study against its spec
- [`conformance()`](https://vthanik.github.io/artoo/reference/conformance.md)
  : Read the conformance findings a dataset carries
- [`artoo_checks()`](https://vthanik.github.io/artoo/reference/artoo_checks.md)
  : Control which conformance checks run
- [`is_artoo_checks()`](https://vthanik.github.io/artoo/reference/is_artoo_checks.md)
  : Test for a artoo_checks control
- [`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md)
  : Validate a specification for submission-readiness

## Read and write

Lossless dataset I/O across every supported format. Generic dispatch on
the file extension, plus a short wrapper per format.

- [`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
  : Read a dataset from any supported format
- [`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
  : Write a dataset to any supported format
- [`read_xpt()`](https://vthanik.github.io/artoo/reference/read_xpt.md)
  : Read a dataset from SAS XPORT
- [`write_xpt()`](https://vthanik.github.io/artoo/reference/write_xpt.md)
  : Write a dataset to SAS XPORT
- [`read_json()`](https://vthanik.github.io/artoo/reference/read_json.md)
  : Read a dataset from CDISC Dataset-JSON
- [`write_json()`](https://vthanik.github.io/artoo/reference/write_json.md)
  : Write a dataset to CDISC Dataset-JSON
- [`read_ndjson()`](https://vthanik.github.io/artoo/reference/read_ndjson.md)
  : Read a dataset from CDISC Dataset-JSON NDJSON
- [`write_ndjson()`](https://vthanik.github.io/artoo/reference/write_ndjson.md)
  : Write a dataset to CDISC Dataset-JSON NDJSON
- [`read_parquet()`](https://vthanik.github.io/artoo/reference/read_parquet.md)
  : Read a dataset from Apache Parquet
- [`write_parquet()`](https://vthanik.github.io/artoo/reference/write_parquet.md)
  : Write a dataset to Apache Parquet
- [`read_rds()`](https://vthanik.github.io/artoo/reference/read_rds.md)
  : Read a dataset from rds
- [`write_rds()`](https://vthanik.github.io/artoo/reference/write_rds.md)
  : Write a dataset to rds

## Inspect

The SAS-viewer-style variable pane, and the dataset inventory of a file
or directory.

- [`columns()`](https://vthanik.github.io/artoo/reference/columns.md) :
  View a dataset's variable attributes, SAS-style
- [`members()`](https://vthanik.github.io/artoo/reference/members.md) :
  List the datasets in a file or directory
- [`xpt_members()`](https://vthanik.github.io/artoo/reference/xpt_members.md)
  : List the members of a SAS XPORT transport file

## Formats and encodings

Reference tables: which codecs this session can read and write, and the
encoding names R, SAS, and Python use for the same bytes.

- [`artoo_formats()`](https://vthanik.github.io/artoo/reference/artoo_formats.md)
  : Report which formats are available
- [`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md)
  : Encodings for clinical datasets, across R, SAS, and Python

## Demo data

Bundled CDISC pilot specs, metadata tables, and datasets used throughout
the docs — all rebuilt from public sources.

- [`adam_spec`](https://vthanik.github.io/artoo/reference/cdisc_specs.md)
  [`sdtm_spec`](https://vthanik.github.io/artoo/reference/cdisc_specs.md)
  : Bundled CDISC specifications (ADaM and SDTM)
- [`cdisc_adam_datasets`](https://vthanik.github.io/artoo/reference/cdisc_spec.md)
  [`cdisc_adam_variables`](https://vthanik.github.io/artoo/reference/cdisc_spec.md)
  [`cdisc_sdtm_datasets`](https://vthanik.github.io/artoo/reference/cdisc_spec.md)
  [`cdisc_sdtm_variables`](https://vthanik.github.io/artoo/reference/cdisc_spec.md)
  [`cdisc_codelists`](https://vthanik.github.io/artoo/reference/cdisc_spec.md)
  : CDISC demo specification tables (one standard per pair)
- [`cdisc_adsl`](https://vthanik.github.io/artoo/reference/cdisc_adsl.md)
  : Demo subject-level analysis dataset (ADaM ADSL)
- [`cdisc_adae`](https://vthanik.github.io/artoo/reference/cdisc_adae.md)
  : Demo adverse events analysis dataset (ADaM ADAE)
- [`cdisc_dm`](https://vthanik.github.io/artoo/reference/cdisc_dm.md) :
  Demo demographics dataset (SDTM DM)
- [`cdisc_vs`](https://vthanik.github.io/artoo/reference/cdisc_vs.md) :
  Demo vital signs dataset (SDTM VS)
- [`cdisc_ts`](https://vthanik.github.io/artoo/reference/cdisc_ts.md) :
  Demo trial summary dataset (SDTM TS)
- [`cdisc_suppdm`](https://vthanik.github.io/artoo/reference/cdisc_suppdm.md)
  : Demo supplemental qualifiers dataset (SDTM SUPPDM)
