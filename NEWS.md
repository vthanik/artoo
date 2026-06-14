# artoo 0.1.0

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
  exactly the spec's columns. The drop runs before the conformance check,
  so `conformance()` on the result reports only the columns the returned
  frame keeps (a dropped column is never a phantom `extra_variable` /
  `variable_name` finding). The drop is never silent: it is announced
  (`artoo_message_apply`) even under `conformance = "off"`, which is its
  audit trail; under `conformance = "abort"` an error finding (only ever on
  a spec-declared column) still aborts and the input is never mutated.

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
* `apply_spec()` gained `on_coercion_loss = c("error", "keep")`, the
  governed gate for a coercion that would lose data (an `integer` dataType
  truncating fractions, or overflowing R's 32-bit range). `"error"`
  (default) keeps the abort-before-touching-data behavior; `"keep"` skips
  coercion for the offending column, preserves its wider source type, and
  reports the divergence as an `integer_fraction` / `integer_overflow`
  finding instead of failing, so a QC pass can keep every value and still
  see the spec disagree. The gate is independent of `conformance`
  (`conformance = "off"` never bypassed it), and the abort now names the
  knob: `on_coercion_loss = "keep"`, `set_type()`, and `check_spec()`.

* New `check_study()`: run `check_spec()` over a named list of a study's
  datasets and return one stacked findings frame, so "is my whole study
  submittable?" is one call instead of a per-dataset loop with one abort at
  a time. The result subclasses the findings frame (it filters like one and
  feeds `repair_spec()` directly); printing it renders the dataset-by-check
  count matrix.

* `check_spec()`'s `type_mismatch` finding is now severity `note`, not
  `warning`: a column stored more widely than the spec declares (an
  integer-valued double under an `integer` dataType, say) coerces cleanly,
  so it is informational. The only fatal coercion checks are
  `integer_fraction` and `integer_overflow`; down-ranking `type_mismatch`
  unclutters a findings report so the genuine blockers stand out.

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

* New `set_type()`: return a spec with one or more variables retyped, e.g.
  `set_type(spec, "ADSL", AGE = "float")`. The supported, in-R way to
  correct a spec's dataType when the data disagrees with it, instead of
  reaching into the object: the type is canonicalised through the CDISC
  vocabulary and the rebuilt spec is re-validated. The original is
  unchanged.

* New `repair_spec()`: take the `integer_fraction` / `integer_overflow`
  findings `check_spec()` reports and return a spec with every offending
  variable retyped to `float`, so a frame the original spec would refuse to
  coerce conforms after one call. Built on `set_type()`; compose with
  `write_spec()` to persist the corrected workbook.

## Dataset I/O

* `write_json()`, `write_ndjson()`, and `write_parquet()` gained the
  `on_invalid = c("error", "replace", "ignore")` policy `write_xpt()`
  already had, closing the asymmetry where one invalid byte made a dataset
  "submittable as XPT but not as Dataset-JSON". Invalid UTF-8 now aborts
  with `artoo_error_codec` naming the offenders hex-escaped (previously an
  uncontrolled `utf8::utf8_normalize()` error), or is replaced/dropped on
  request; the gate lives in the one shared transcode helper, so all four
  writers rule identically.

* `read_ndjson()` gained the `encoding =` argument the other readers already
  carried, closing the last read-side asymmetry. Pass an IANA or SAS charset
  (e.g. `"windows-1252"`) to read a non-conformant NDJSON file a producer
  wrote in that charset; each line is transcoded to UTF-8 on read, preserving
  the bounded `n_max` streaming. Character columns are now NFC-normalized on
  read, matching `read_json()`.

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

* The pkgdown reference index gains `set_type()` and `repair_spec()` (in the
  Specification group) and `check_study()` (in the Check group), and the site
  root now serves an `llms.txt` function map for machine-readable discovery.
  `apply_spec()` cross-links the spec-fix verbs and `check_spec()` cross-links
  `check_study()`.

* `apply_spec()`'s `extra` argument documents why `"keep"` is the lossless
  default, and `spec_methods()` / `spec_comments()` enumerate every column of
  the data frame they return.

* The introductory vignette is `vignette("artoo")`, anchored by a
  hand-authored round-trip diagram (shared with the home page), and surfaces
  as a top-level "Get started" navbar entry. It is standard-neutral: the quick
  tour conforms an SDTM domain beside the ADaM one, so both standards are
  first-class from the first page.

* Four task-oriented articles joined the site (web-only, not in the package
  tarball): specifications (read, inspect, repair a spec); conform & validate
  (`apply_spec()`, the conformance checks, and every `artoo_error_<kind>`
  triggered live with its fix); formats & lossless conversion (any-to-any
  round trips, encodings, and qualification evidence); and recipes (end-to-end
  ADaM and SDTM builds, dates and `--DTC`, and codelist decoding, rendered
  live on the demo data).

## Fixes

* `write_spec()` no longer silently drops foreign columns when writing a
  Pinnacle 21 workbook. The reader already retains columns it does not map
  to the P21 vocabulary (they ride along as character columns), but the
  writer previously projected only the mapped columns and dropped the rest;
  it now re-emits foreign columns verbatim, so an xlsx round-trip keeps user
  columns. Canonical columns with no P21 header (`itemoid`,
  `target_data_type`, `key_sequence`) stay unemitted and survive through the
  lossless native JSON, as before.

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
