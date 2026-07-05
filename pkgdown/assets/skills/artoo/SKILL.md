---
name: artoo
description: >
  Read and write clinical-trial datasets losslessly across SAS XPORT, CDISC
  Dataset-JSON v1.1, Apache Parquet, and RDS from R. Use when writing R code
  that uses the artoo package.
license: MIT
compatibility: Requires R >=4.3.
---

# artoo

Read and write clinical-trial datasets losslessly across SAS XPORT (v5/v8),
CDISC Dataset-JSON v1.1, NDJSON, Apache Parquet, and RDS from R. One
canonical metadata model (`artoo_meta`) is carried by every codec, so
any-to-any conversion is lossless by construction. Pure R, no Java, no SAS,
and no compiled runtime beyond a small Parquet engine.

## Installation

```r
install.packages("artoo")
# development version:
# pak::pak("vthanik/artoo")
```

## Mental model

The workflow is one line of three verbs: **read a spec**, **apply it** to a
raw data frame, then **read or write** any format. Each verb returns an
immutable `artoo_spec` or a conformed `data.frame` that carries the spec's
metadata. Nothing is silently transformed at the edges — write is lossless
by inheriting the source encoding; ASCII is a gate, not a silent recode.
Every condition is a typed `artoo_error_<kind>` / `artoo_warning_<kind>` /
`artoo_message_<kind>` so a caller catches by class, not by message.

```r
library(artoo)

dm <- apply_spec(cdisc_dm, sdtm_spec, dataset = "DM")
write_xpt(dm, tempfile(fileext = ".xpt"))
```

Every reader takes `encoding =` (`read_xpt()` auto-detects `windows-1252`
when bytes are not valid UTF-8); every writer takes
`on_invalid = c("error", "replace", "ignore")`.

## API overview

### Specs

Build a spec from metadata tables, or read one from native JSON, a
Pinnacle 21 xlsx workbook, or Define-XML; write it back, or amend it in R
when the data disagrees.

- `artoo_spec`: Build and validate a CDISC spec from metadata tables
- `read_spec`: Read a spec from native JSON, a Pinnacle 21 xlsx workbook, or Define-XML
- `write_spec`: Write a spec to JSON (lossless) or xlsx (interchange)
- `set_type`: Retype a variable in R when the data disagrees with the spec's dataType
- `repair_spec`: Flip every `integer_fraction` / `integer_overflow` variable to `float` from a study findings frame, in one call

### Spec accessors

Read one slot of a spec.

- `spec_standard`, `spec_study`, `spec_datasets`, `spec_variables`, `spec_codelists`, `spec_keys`, `spec_methods`, `spec_comments`, `spec_documents`

### Conform

Apply the spec to a raw frame, decode single variables through its
codelists, and read or replace the metadata a conformed frame carries.

- `apply_spec`: Coerce, order, sort, and stamp a raw frame to its spec (`extra = "drop"` trims to the spec's columns; `on_coercion_loss = "keep"` preserves data an `integer` dataType cannot hold — the divergence is reported, not silently truncated)
- `decode_column`: Map a coded variable through a spec codelist
- `get_meta`, `set_meta`, `sync_meta`: Read, replace, or refresh the `artoo_meta` a conformed frame carries

### Check

Surface conformance findings for one dataset or a whole study, plus the
spec's own structural integrity, with the control object that scopes both.

- `check_spec`: Conformance findings for one dataset (needs the data)
- `check_study`: Conformance findings across a whole study in one pass; prints a dataset-by-check count matrix; feeds `repair_spec()`
- `validate_spec`: Structural integrity of the spec itself (no data)
- `conformance`: Read the findings `apply_spec()` attached to a frame
- `artoo_checks`: Toggle which conformance dimensions run (only `integer_fraction` / `integer_overflow` are fatal coercion checks; `type_mismatch` is informational)

### Read and write (lossless any-to-any)

Generic dispatch on the file extension, plus a short wrapper per format.

- `read_dataset`, `write_dataset`: Generic, dispatch on the file extension
- `read_xpt`, `write_xpt`: SAS XPORT v5/v8
- `read_json`, `write_json`: CDISC Dataset-JSON v1.1 (array form)
- `read_ndjson`, `write_ndjson`: CDISC Dataset-JSON v1.1 (newline-delimited)
- `read_parquet`, `write_parquet`: Apache Parquet (via `nanoparquet`)
- `read_rds`, `write_rds`: R serialization

### Inspect

The SAS PROC CONTENTS variable pane and the dataset inventory of a file.

- `columns`: Variable-pane summary of a conformed frame
- `members`, `xpt_members`: Dataset inventory of a file or library

### Reference tables

Reference tables for the codecs this session can read and write, and the
encoding names R, SAS, and Python share.

- `artoo_formats`: Codecs available in this session (extension, direction, engine)
- `artoo_encodings`: Charset names across IANA, R, SAS, and Python

### Predicates

Class checks for the artoo S7 objects.

- `is_artoo_spec`, `is_artoo_meta`, `is_artoo_checks`

### Bundled demo data

CDISC pilot specs and datasets rebuilt from public sources. Use these
instead of inventing toy data.

- `adam_spec`, `sdtm_spec`: pilot ADaM and SDTM specs
- `cdisc_adam_datasets`, `cdisc_adam_variables`, `cdisc_sdtm_datasets`, `cdisc_sdtm_variables`, `cdisc_codelists`: the metadata tables the bundled specs are built from
- `cdisc_adsl`, `cdisc_adae`: ADaM demo frames
- `cdisc_dm`, `cdisc_vs`, `cdisc_ts`, `cdisc_suppdm`: SDTM demo frames

## Conventions (don't fight these)

- **Type model is CDISC Dataset-JSON v1.1 verbatim** — `dataType` in
  {string, integer, decimal, float, double, boolean, date, datetime, time,
  URI}, `targetDataType` in {integer, decimal}, plus length /
  displayFormat / keySequence. Dates and times round-trip via
  dataType + targetDataType + displayFormat, never a class attribute.
- **Encoding follows global standards** — IANA names (`US-ASCII`,
  `windows-1252`, `UTF-8`; SAS `WLATIN1` maps to `windows-1252`), Unicode
  NFC (UAX #15). Regulatory defaults: xpt = US-ASCII (FDA TCG),
  json = UTF-8 (CDISC / RFC 8259).
- **Metadata rides in the file** — one CDISC-shaped `metadata_json` sidecar
  is embedded verbatim in every container (parquet KV, rds attr). That is
  what makes any-to-any lossless: the full itemGroup travels with the data.
- **Conformance findings are data, not conditions** — `apply_spec()`
  attaches a findings tibble read back by `conformance()`; `check_spec()`
  and `check_study()` return one. Feed the study-level findings straight
  into `repair_spec()` to fix the spec in one call.
- **`extra = "drop"` in `apply_spec()` trims to exactly the spec's
  columns** — the intended shape for submission; the default `"keep"`
  passes foreign columns through untouched.
- **Errors are classed cli conditions** — `artoo_error_<kind>` where kind
  is one of `input`, `spec`, `type`, `codelist`, `codec`, `validation`,
  `conformance`. Catch by class, never by message.

## Resources

- [Full documentation](https://vthanik.github.io/artoo/)
- [llms.txt](https://vthanik.github.io/artoo/llms.txt) — Indexed reference for LLMs
- [llms-full.txt](https://vthanik.github.io/artoo/llms-full.txt) — Full documentation for LLMs
