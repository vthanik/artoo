# artoo 0.0.0.9000

artoo is the clean-slate, KISS/DRY redesign of the package once called
vport: a lightweight, lossless, CDISC-native reader/writer for
clinical-trial datasets (SAS XPORT, CDISC Dataset-JSON v1.1, NDJSON,
Apache Parquet, RDS) around one canonical metadata model. Pre-release;
no backward compatibility is kept with the vport surface.

## Object model

* `artoo_spec()` canonicalises study-level fields to the CDISC ODM
  GlobalVariables vocabulary, snake_cased: `study_name`,
  `study_description`, `protocol_name`. Source spellings resolve
  automatically (`StudyName` from the P21 Define sheet, `studyid` from
  hand-built specs); unknown fields pass through verbatim; aliases that
  disagree abort with `artoo_error_spec`. The spec print header, the
  metadata `studyOID`, and `validate_spec()` all read the one canonical
  field, so a Define-sourced spec no longer prints
  `Study: (unspecified)` while holding the study name. The Define-XML
  reader now also extracts `StudyDescription`, and `write_spec()` writes
  the study row back as the P21 Define sheet, so study metadata survives
  the xlsx round-trip.
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
  `artoo_<severity>_<kind>`, `artoo_<severity>`, `artoo_condition` — so
  `tryCatch(artoo_error = )` catches every error kind and
  `expect_error(class = "artoo_error")` works family-wide.
* SAS `TIME` variables now import as `hms::hms` (seconds since midnight);
  the bespoke time class was removed. Elapsed times past 24h, negative,
  and fractional-second values round-trip every format; exchange text
  stays byte-stable. `hms` joined Imports. A time column compared with a
  character string now coerces (the old class aborted on
  `t == "08:30:00"`); convert explicitly when comparing.

## Conform

* `apply_spec()` gained `extra = c("keep", "drop")`: `"keep"` (default)
  preserves today's never-drop behavior; `"drop"` trims the output to
  exactly the spec's columns. The drop is never silent: it is announced
  (`artoo_message_apply`) even under `conformance = "off"`, the
  `extra_variable` finding remains the audit trail, and a
  `conformance = "abort"` failure fires before any drop.

* `apply_spec()`'s data-protection conditions now carry their evidence as
  data, not just prose: the lossy-coercion abort (`artoo_error_type`) and
  the NA-introduction warning (`artoo_warning_coercion`) attach
  `cnd$variables` — a data frame of `variable`, `data_type`, `n`,
  `reason` — and the `conformance = "abort"` failure attaches the complete
  findings frame as `cnd$findings`, so a pipeline collects every mismatch
  in one `tryCatch()` pass instead of parsing messages.

* `apply_spec()` was reduced to five load-bearing arguments:
  `apply_spec(x, spec, dataset, conformance =, na_position =)`. The
  pipeline is fixed — coerce, order, sort, stamp — with no
  subsetting knob (`steps`, `profile` dropped); codelist translation
  lives in `decode_column()` (`decode`, `no_match`, `trim`, `ignore_case`
  dropped); `checks` controls are passed to `check_spec()` directly.
* `apply_spec()` no longer scaffolds: a variable the spec declares but the
  data lacks is no longer added as an empty typed-`NA` column. It is reported
  instead, an informational heads-up at apply time plus a `missing_variable`
  finding (when mandatory) or `missing_permissible` (when not), and left
  absent. artoo is a lossless carrier, not a deriver: fabricating an empty
  derived column both modified the data and masked that an expected variable
  was never produced.
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
  composition: `read_spec("define.xml") |> write_spec("spec.xlsx")`. The
  workbook's `Data Type` column is written in the Define-XML / ODM
  vocabulary the format expects: a character variable is `text` (not the
  Dataset-JSON `string`), with `decimal` / `double` collapsing to `float`
  and `boolean` / `URI` to `text`. A read folds these back, so a round-trip
  preserves `string`, `integer`, `float`, `date`, `datetime`, and `time`
  exactly.

## Dataset I/O

* `write_json()`, `write_ndjson()`, and `write_parquet()` gained the
  `on_invalid = c("error", "replace", "ignore")` policy `write_xpt()`
  already had, closing the asymmetry where one invalid byte made a dataset
  "submittable as XPT but not as Dataset-JSON". Invalid UTF-8 now aborts
  with `artoo_error_codec` naming the offenders hex-escaped (previously an
  uncontrolled `utf8::utf8_normalize()` error), or is replaced/dropped on
  request; the gate lives in the one shared transcode helper, so all four
  writers rule identically.

## Inspect

* New `members()`: the format-neutral inventory of the dataset(s) a path
  holds, one row per dataset (`file`, `member`, `label`, `records`,
  `variables`, `format`), dispatched by extension through the codec registry.
  A SAS XPORT library lists every member, a single-dataset file (`.json`,
  `.ndjson`, `.parquet`, `.rds`) reports one row, and a directory inventories
  each dataset file it holds. The format-neutral companion to the xpt-specific
  `xpt_members()`.

* New `artoo_encodings()`: the encodings clinical data travels in, one row
  per encoding with the name under each ecosystem — `sas` (session
  encoding), `r` (the standard IANA name `iconv()` uses), and `python`
  (codec) — written for SAS programmers who have never had to think
  about encodings. Every reader/writer `encoding` argument accepts the
  `sas` or `r` spelling.

* New `columns()`: the SAS `PROC CONTENTS` / Universal Viewer variable
  pane (`#`, Variable, Type, Len, Format, Label, plus the CDISC Key
  sequence, and Informat only when a variable carries one), polymorphic over
  a stamped frame, any plain data frame (attributes inferred), or a file path
  dispatched through the codec registry. The pane mirrors physical storage: a
  Char column always shows a byte length (inferred when the spec declares
  none, so an ISO-8601 `--DTC` column is never blank), a numeric shows none
  (an 8-byte IEEE double has no character width; a Define-XML numeric length
  is a digit-width kept in metadata), and format and informat names render
  uppercase. A multi-member XPORT path without `member =` points at
  `xpt_members()`.

## Data

* The demo constructor tables are split by standard — `cdisc_adam_datasets`
  + `cdisc_adam_variables` (ADSL, ADaMIG 1.1) and `cdisc_sdtm_datasets` +
  `cdisc_sdtm_variables` (DM, SDTMIG 3.1.2), each carrying its `standard`
  column — replacing the removed `cdisc_datasets`/`cdisc_variables`, which
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
  `apply_spec(conformance = "abort")` — gated at build time and at test
  time.

## Docs

* `apply_spec()`'s `extra` argument documents why `"keep"` is the lossless
  default, and `spec_methods()` / `spec_comments()` enumerate every column of
  the data frame they return.

* The introductory vignette is now the package-named `vignette("artoo")` and
  surfaces as a top-level "Get started" navbar entry rather than an item in
  the Articles dropdown. It is standard-neutral: the quick tour conforms an
  SDTM domain beside the ADaM one, so both standards are first-class from the
  first page.

* Six task-oriented articles joined the site (web-only, not in the
  package tarball): an end-to-end ADaM build, an end-to-end SDTM build,
  any-to-any conversion, dates/times/`--DTC` carriage, validation &
  qualification, and a common-errors page that triggers every
  `artoo_error_<kind>` live with its fix.

## Fixes

* `apply_spec()` now coerces a `factor` column through its labels, never its
  integer level codes. A factor of numeric labels declared `integer` or
  `float` previously wrote the codes (`factor(c("10", "20"))` became `1, 2`)
  with no abort and no warning, because the lossy guard compared codes to
  codes and the `double` path had no guard at all. Factors are normalized to
  character at every coercion read site (the value coercion, the lossy and
  32-bit-overflow checks, and the temporal realizer), so a non-numeric label
  now becomes `NA` and is reported by the coercion warning.

* The declaration-driven writers (Dataset-JSON, NDJSON, the Parquet
  sidecar, rds) now reconcile the carried metadata to the frame before
  serializing, the same overlay semantics `write_xpt()` always had. A
  frame mutated after `apply_spec()` — a column added, dropped, or
  reordered without `sync_meta()` — previously wrote a corrupt
  Dataset-JSON (row arity disagreed with the columns declaration) or,
  for a pure reorder, a silently misaligned one in which every value
  landed under the wrong column name.

* Inferred xpt storage lengths for character columns without metadata now
  count bytes, not characters: an XPORT `LENGTH` is a byte width, so
  multibyte UTF-8 values were undercounted (and would truncate on write),
  and `nchar(type = "chars")` failed outright on invalid bytes before the
  writers' `on_invalid` gate could rule.

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
