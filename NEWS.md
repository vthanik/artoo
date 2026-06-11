# artoo 0.0.0.9000

artoo is the clean-slate, KISS/DRY redesign of the package once called
vport: a lightweight, lossless, CDISC-native reader/writer for
clinical-trial datasets (SAS XPORT, CDISC Dataset-JSON v1.1, NDJSON,
Apache Parquet, RDS) around one canonical metadata model. Pre-release;
no backward compatibility is kept with the vport surface.

## Object model

* `artoo_spec()` is single-standard by construction: `standard` was
  promoted from a per-dataset column to the scalar `@standard` property,
  resolved from the explicit argument, a P21-style `datasets$standard`
  column, or a Define-XML-style `study$standard` field (those columns are
  consumed). Mixing standards aborts with `artoo_error_spec`; scope the
  read with `read_spec(path, datasets = )` instead. New `spec_standard()`
  accessor; the spec print header shows the standard; native spec JSON
  carries a top-level `standard` key.
* `artoo_spec()` derives per-variable `key_sequence` from a dataset's
  `keys` string when the source provides none (the P21 workbook shape),
  so the metadata `keySequence` is populated regardless of spec source.
* Every condition artoo raises now carries a three-level class chain --
  `artoo_<severity>_<kind>`, `artoo_<severity>`, `artoo_condition` -- so
  `tryCatch(artoo_error = )` catches every error kind and
  `expect_error(class = "artoo_error")` works family-wide.
* SAS `TIME` variables now import as `hms::hms` (seconds since midnight);
  the bespoke time class was removed. Elapsed times past 24h, negative,
  and fractional-second values round-trip every format; exchange text
  stays byte-stable. `hms` joined Imports. A time column compared with a
  character string now coerces (the old class aborted on
  `t == "08:30:00"`); convert explicitly when comparing.

## Conform

* `apply_spec()` was reduced to five load-bearing arguments:
  `apply_spec(x, spec, dataset, conformance =, na_position =)`. The
  pipeline is fixed -- scaffold, coerce, order, sort, stamp -- with no
  subsetting knob (`steps`, `profile` dropped); codelist translation
  lives in `decode_column()` (`decode`, `no_match`, `trim`, `ignore_case`
  dropped); `checks` controls are passed to `check_spec()` directly.
* `apply_spec()` never drops a column: a variable the spec does not
  declare survives the pipeline, is reported by the `extra_variable`
  finding, gets a class-inferred metadata entry at stamp time, and
  round-trips every codec.
* `apply_spec()` always aborts on lossy coercion (`artoo_error_type`):
  integer truncation of fractional values and 32-bit overflow have no
  warn-and-continue opt-out (`on_lossy` dropped); fix the spec's dataType
  instead.

## Spec I/O

* `write_spec()` dispatches on the file extension: `.json` writes the
  lossless native format; `.xlsx` (new; `writexl` in Suggests) writes a
  Pinnacle 21 workbook whose sheet names and headers derive from the P21
  reader's own maps, with foreign keys repeated on every row and the
  spec's standard on the Datasets sheet. Define-XML to P21 is one
  composition: `read_spec("define.xml") |> write_spec("spec.xlsx")`.

## Inspect

* New `artoo_encodings()`: the encodings clinical data travels in, one row
  per encoding with the name under each ecosystem -- `sas` (session
  encoding), `r` (the standard IANA name `iconv()` uses), and `python`
  (codec) -- written for SAS programmers who have never had to think
  about encodings. Every reader/writer `encoding` argument accepts the
  `sas` or `r` spelling.

* New `columns()`: the SAS `PROC CONTENTS` / Universal Viewer variable
  pane (`#`, Variable, Type, Len, Format, Informat, Label, plus the CDISC
  Key sequence), polymorphic over a stamped frame, any plain data frame
  (attributes inferred), or a file path dispatched through the codec
  registry. A multi-member XPORT path without `member =` points at
  `xpt_members()`.

## Data

* The demo constructor tables are split by standard -- `cdisc_adam_datasets`
  + `cdisc_adam_variables` (ADSL, ADaMIG 1.1) and `cdisc_sdtm_datasets` +
  `cdisc_sdtm_variables` (DM, SDTMIG 3.1.2), each carrying its `standard`
  column -- replacing the removed `cdisc_datasets`/`cdisc_variables`, which
  mixed both standards in one spec (the exact shape the single-standard
  model forbids). Stacking the two pairs into one `artoo_spec()` now aborts,
  and the build gates assert it. `cdisc_codelists` stays shared: controlled
  terminology is standard-agnostic.

* New bundled specs `adam_spec` (ADaMIG 1.1: ADSL, ADAE) and `sdtm_spec`
  (SDTMIG 3.1.2: TS, DM, VS, SUPPDM), built reproducibly from the
  official CDISC Define-XML 2.1 release examples and shipped also as P21
  workbooks under `inst/extdata/`. New demo datasets `cdisc_adae`,
  `cdisc_vs`, `cdisc_ts`, `cdisc_suppdm` from the PHUSE Test Data
  Factory. Every bundled dataset conforms to its bundled spec under
  `apply_spec(conformance = "abort")` -- gated at build time and at test
  time.

## Fixes

* `read_xpt()` no longer silently drops a small second member hiding
  entirely inside the floored-off tail of a wide-record v5 file; the
  EOF-derived row count now scans the fragment's 80-byte boundaries and
  raises the multi-member abort.

## Carried over from the pre-rename development line

* Lossless any-to-any I/O across xpt / Dataset-JSON / NDJSON / parquet /
  rds through the one `artoo_meta` serializer; partial reads
  (`col_select`, `n_max`) on every reader; gzip-transparent JSON/NDJSON;
  multi-member XPORT reads via `xpt_members()` + `read_xpt(member = )`;
  Define-XML 2.0/2.1 ingestion; `decode_column()`; `check_spec()` with
  `artoo_checks()` toggles; `validate_spec()` with the bundled rule
  catalog; `conformance()`; `sync_meta()`; fuzzing, stress, and
  byte-golden test suites.
