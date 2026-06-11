# vport 0.0.0.9000

* `apply_spec()` decode matching gained `trim` (default `TRUE`: a value that
  matches a codelist only after whitespace trimming still decodes, with a
  `vport_warning_codelist` naming the variants) and `ignore_case` (opt-in
  case-insensitive matching, same warning). Membership *checking* still
  compares exactly. The coercion warning now names 32-bit integer overflow
  precisely instead of a generic NA-introduction message.
* `check_spec()` gained five conformance dimensions, each with a
  `vport_checks()` toggle: `variable_name` and `dataset_name` (XPORT naming
  rules on the actual columns and dataset name: 8-character v5 limit,
  32-character v8 limit, ASCII letters/digits/underscore), `label_length`
  (a column label attribute over the 40-byte XPORT v5 / FDA limit),
  `integer_overflow` (an integer-typed variable holding values beyond R's
  32-bit range, an error since coercion would lose them to NA), and
  `codelist_membership_extensible` (a non-member of an `extended = TRUE`
  codelist is a note naming a sponsor term, never an error).
* `validate_spec()` gained four spec-integrity rules:
  `key_sequence_contiguous` (keySequence must be 1..k, no gaps or
  duplicates), `key_sequence_matches_keys` (keySequence must agree with the
  dataset's declared keys), `variable_order_unique` (no duplicate order
  values within a dataset), and `itemoid_unique` (itemOIDs unique across the
  spec).
* `data-raw/build-spec-rules.R` is again the single source of the shipped
  rule catalog: eight rules previously hand-added to `inst/spec_rules.json`
  were folded back into the build script, and the regenerated catalog now
  has 58 rules.
* New `read_ndjson()` / `write_ndjson()`: the newline-delimited variant of
  CDISC Dataset-JSON v1.1 (`.ndjson`, `.jsonl`). Line 1 carries the complete
  metadata block; each following line is one row array. Memory stays bounded
  in both directions (the writer streams slabs, the reader parses line
  batches, `n_max` stops the line loop early), making ndjson the format for
  multi-million-row datasets.
* `read_json()` and `read_ndjson()` read `.json.gz` / `.ndjson.gz`
  transparently (gzip magic-byte detection), and the writers gzip when the
  path ends in `.gz`; the generic dispatcher resolves the double extension.
  A `.gz` behind a binary container format (xpt, parquet, rds) is refused
  with `vport_error_input`.
* `write_json()` now streams the `rows` array in bounded slabs of per-column
  JSON literals instead of materializing an O(rows x cols) cell list, with a
  progress bar over slabs; output is byte-identical to the previous
  serialization (pinned by golden files).
* `write_parquet()` gained `compression` (`"snappy"` default, `"gzip"`,
  `"zstd"`, `"uncompressed"`), passed through to nanoparquet.
* `write_xpt()` packs character columns with one vectorized buffer fill per
  column instead of a per-row loop; a 1M-row character-heavy write is an
  order of magnitude faster and the output is byte-identical.
* Added `bench/bench-io.R`, a 1M x 30 benchmark harness writing
  `bench/baseline.json` for the opt-in performance-regression smoke.
* SAS special missing tags (`.A`-`.Z`, `._`) now survive every format, not
  just xpt and rds: json and parquet carry them in the namespaced
  `_vport.specialMissings` extension while the data values stay plain nulls
  (a foreign reader degrades gracefully to ordinary missings), and partial
  reads (`n_max`) keep the tags row-aligned. Previously an
  xpt -> json -> xpt round trip silently degraded them to plain missings.
* SAS informats now round-trip: `write_xpt()` writes NAMESTR bytes 73-84
  (`niform`/`nifl`/`nifd`), `read_xpt()` reads them back (including the
  long-format/informat strings in a LABELV9 extension, which were previously
  discarded), the spec gained an optional `informat` column, frames carry an
  `informat.sas` column attribute (projected by `set_meta()`, read back by
  the bare-frame writer), and every other format carries informats in the
  `_vport.informats` extension.
* A round-trip losslessness matrix test now exercises every ordered pair of
  formats over a torture frame covering all ten CDISC dataTypes, non-ASCII
  text, and special missings on plain and temporal columns.
* `read_parquet()` now synthesizes metadata from the column types and
  attributes when a foreign (plain-nanoparquet/arrow) file carries no vport
  sidecar, so `get_meta()` and a downstream `write_xpt()`/`write_json()`
  work on any parquet file; previously the frame came back bare.
* `read_parquet()` canonicalizes integer-backed `Date` columns (nanoparquet's
  native DATE arrival) to R's double backing, so `identical()` holds across
  codecs.
* `write_json()` gained `strict`: `TRUE` writes a pure closed-vocabulary
  CDISC file and warns (`vport_warning_codec`) naming any dropped vport
  extensions; the default (`FALSE`) emits a single namespaced `_vport` block
  only when there is content strict CDISC cannot express (special missing
  tags, the recorded source encoding, informats). The block is stamped with
  `vportMetaVersion` for forward compatibility.
* `write_json()` now serializes doubles with 17 significant digits, the
  guaranteed IEEE-754 round-trip precision; `digits = NA` delegated to R's
  15-digit default and silently lost the last ulp (`0.1 + 0.2` read back
  as `0.3`).
* Added a pkgdown website, two Quarto vignettes ("From spec to submission
  dataset" and "One dataset, every format"), and a rendered README covering
  the spec-to-submission workflow and lossless any-to-any conversion.
* Added continuous integration: `R CMD check` across macOS, Windows, and
  Ubuntu (release, devel, and oldrel-1), test-coverage reporting to Codecov,
  and pkgdown site deployment.
* `read_dataset()` and every per-format reader (`read_xpt()`, `read_json()`,
  `read_parquet()`, `read_rds()`) gained `col_select` and `n_max` for partial
  reads. A generic post-decode filter is the single source of selection
  correctness (file order, unknown-name error, record-count sync) on every
  format; xpt narrows rows off disk and Parquet projects columns natively
  where the engine allows, json and rds filter after the whole-file parse.
* `read_xpt()` now reads only the requested rows on a large v5 file: the row
  count comes from an end-of-file backward scan instead of loading the whole
  observation section, so `n_max` is a true partial read and a multi-gigabyte
  file no longer blows memory.
* `read_xpt()` aborts (`vport_error_codec`) on a multi-member transport file
  instead of silently reading the second member as extra rows, and honors the
  member header's NAMESTR size field (140, or 136 for the VMS variant).
* `read_xpt()` and the other readers project the column `label` and SAS
  `format.sas` from the metadata onto the returned columns (haven parity), so
  labelled/gtsummary/viewer tooling sees them; the `vport_meta` stays the
  source of truth.
* `write_xpt()` warns (`vport_warning_encoding`) when a value would write a
  byte in 160-191, which the FDA Study Data TCG prohibits in submission xpt;
  the check runs only on a single-byte stream, never on UTF-8.
* `write_xpt()` v5 aborts on a variable-name collision that survives
  uppercasing (`age` and `AGE`), and warns when an all-character frame ends in
  a blank row that v5 cannot read back.
* A failed atomic move now aborts (`vport_error_codec`) instead of leaving the
  caller believing a file was written.
* The bundled `cdisc_*` demo data is now built with vport's own `read_xpt()`
  (dogfooding). Blank character cells read back as `NA` (vport's XPORT
  convention) rather than `""`; values and labels are otherwise unchanged.
* `apply_spec()` renamed its `check` argument to `on_error`, with values
  `c("warn", "abort", "off")` (`"strict"` is now `"abort"`); the
  error-escalation message caps at three findings (breaking).
* `validate_spec()` replaced `strict` with `on_error = c("off", "warn",
  "abort")` (default `"off"`); `"warn"` signals a `vport_warning_validation`
  with the error count, `"abort"` aborts as `strict = TRUE` did. Every
  finding is still collected and returned in all cases (breaking).
* `check_formats()` was renamed `vport_formats()` (breaking).
* `spec_codelist()` was renamed `spec_codelists()` and gained a
  `codelist_id = NULL` default that returns the whole codelists table,
  matching the `spec_variables()` filter pattern (breaking).
* `vport_checks()` dropped its `encoding_check` argument; the submission
  encoding gate moves to the xpt write path in a later release (breaking).
* `check_spec()` now returns the same six-column findings frame as
  `validate_spec()` (`check`, `dimension`, `severity`, `dataset`,
  `variable`, `message`), built from the shared open rule catalog, and
  gained a `decode` argument so a decoded column is checked against the
  matching codelist column rather than wrongly flagged.
* `check_spec()` codelist membership now treats an `NA` in a mandatory
  variable as a violation (and a non-mandatory `NA` as conforming), sharing
  one membership implementation with `validate_spec()`.
* `check_spec()` gained four submission-readiness data checks, all on by
  default: `char_length_limit` (a character value over the 200-byte SAS XPORT
  v5 / FDA cap), `key_uniqueness` (the spec key variables do not uniquely
  identify the rows), `label_match` (a column label that diverges from the
  spec), and `missing_permissible` (a missing non-mandatory variable, a
  warning, split out from the mandatory `missing_variable` error).
* `vport_checks()` gained the four matching toggles
  (`char_length_limit`, `key_uniqueness`, `label_match`,
  `missing_permissible`); each defaults to `TRUE`.
* `validate_spec()` gained four submission-readiness spec checks:
  `variable_name_length` (a name over 8 characters), `variable_label_length`
  (a label over 40 bytes), and, in whole-spec mode, `cross_dataset_label` and
  `cross_dataset_type` (a variable shared across datasets with inconsistent
  labels or data types).
* `as.data.frame()` on a `vport_check` returns its findings data frame.
* `read_json()` and `write_json()` read and write CDISC Dataset-JSON v1.1
  files through the `vport_meta` spine, with byte-stable output (injectable
  `created`), meta-driven type fidelity (a whole-number double does not drift
  to integer on re-read), `targetDataType` numeric-date emission, exact
  `decimal`-as-string round-tripping, and a structural probe that rejects a
  non-Dataset-JSON file cleanly.
* `read_parquet()` and `write_parquet()` read and write Apache Parquet files
  via the lightweight `nanoparquet` engine, embedding the full `vport_meta`
  as a CDISC-shaped `metadata_json` sidecar; a parquet written by another
  tool degrades gracefully to a bare frame.
* `check_formats()` reports the Parquet row as unavailable until
  `nanoparquet` is installed.
* `read_json()`, `read_parquet()`, and `read_rds()` gained an `encoding`
  argument that transcodes a foreign (non-UTF-8) file's bytes to UTF-8 on
  read; previously only `read_xpt()` could read non-UTF-8 source bytes.
* `write_parquet()` and `write_rds()` gained an `encoding` argument that
  records the data's source charset in the `vport_meta` (the containers stay
  UTF-8 by spec), so a later `write_xpt()` reproduces the original single-byte
  stream. `write_json()` stays UTF-8 only, as CDISC Dataset-JSON requires.
* `write_json()` and `write_parquet()` now NFC-normalize character columns on
  write, so the serialized output is canonical Unicode (a no-op on ASCII /
  single-byte data, so existing output is byte-stable).
* `apply_spec()` gained a `na_position` argument controlling where missing
  key values sort: `"first"` (the default, matching SAS `PROC SORT` and the
  FDA submission convention) or `"last"` (matching R, pandas, and Polars).
* `apply_spec()` warns (class `vport_warning_coercion`) when an `integer`
  dataType truncates fractional values, instead of truncating silently.
* `apply_spec(check = "strict")` and `validate_spec(strict = TRUE)` render
  finding messages containing `{` literally instead of crashing on cli
  interpolation and losing the conformance report.
* `read_dataset()` and `read_rds()` refuse a payload that is not a data
  frame with a `vport_error_codec` instead of returning it silently.
* `read_xpt()` reads files whose variable or dataset labels hold non-UTF-8
  bytes (e.g. SAS wlatin1) instead of crashing; labels now flow through the
  same encoding detection and transcode pipeline as data values.
* `read_xpt()` and `write_xpt()` take their codec options as named formals
  (`version`, `encoding`, `on_invalid`, `created`); a misspelled argument is
  now an error instead of being silently ignored.
* `vport_time` and `vport_check` print/format methods now dispatch in
  installed builds; previously the data viewer and console showed raw
  seconds.
* `vport_time` gained `[<-`/`[[<-` guards that reject a character right-hand
  side (`vport_error_input`) instead of silently corrupting the column;
  `c()` now accepts a bare `NA`; `unique()` and `mean()` keep the class; and
  `%%`/`%/%` preserve it so a day-wrap (`t %% 86400`) stays a clock time.
* `vport_time` comparison with a character value (`t == "08:30:00"`) now
  aborts (`vport_error_input`) instead of silently coercing to a string
  compare; `format()` renders fractional seconds (`08:30:00.5`).
* Reading a Dataset-JSON or xpt time/datetime no longer loses data: an ISO
  datetime with a UTC offset (`+05:30`, `Z`) is read as the correct instant,
  fractional seconds (`HH:MM:SS.s`) are preserved, and a shape-valid but
  impossible date (`2014-13-45`) stays character instead of crashing.
* `write_xpt()` and the other codecs now accept an `hms`/`difftime` column
  for a `time` variable, converting it via seconds instead of mistyping it
  as a float.
* Special-missing tags (`.A`-`.Z`, `._`) survive date/datetime/time
  round-trips; previously a second write degraded them to plain missing.
* `write_dataset()`, `write_xpt()`, and `write_rds()` return the input data
  invisibly (the readr/haven convention), not the path.
* `write_xpt()` keeps 80-byte record framing for non-ASCII dataset and
  variable labels (byte-exact packing, character-boundary truncation at 40
  bytes), aborts on a non-ASCII dataset name, and warns when truncating a
  long dataset label.
* `write_xpt()` writes locale-independent header timestamps; previously a
  non-English `LC_TIME` corrupted the header framing.
* `write_xpt()` refuses character-backed or class-mismatched temporal
  columns (e.g. a partial date `"2014"` under dataType `date`) instead of
  writing garbage SAS epoch values.
* `read_xpt()` and `write_xpt()` read and write SAS XPORT (xpt) v5 and v8
  files losslessly through the `vport_meta` spine, with byte-stable output, a
  full IBM-370 float and SAS-epoch temporal round-trip, special-missing
  (`.A`-`.Z`, `._`) fidelity, and encoding round-trip for any single-byte
  charset.
* `vport_spec` and `vport_meta` now print a readable summary (header, slot
  counts, and a truncated preview) instead of dumping their raw S7
  properties; `format()` returns the same lines.
* `apply_spec()` no longer silently abandons row ordering when only some
  spec variables carry an `order`: it orders the numbered variables and
  trails the rest, warning with class `vport_warning_order`.
* `apply_spec()` scaffold and drop progress messages now carry the
  condition class `vport_message_apply`, so a pipeline can muffle them with
  `withCallingHandlers()` without suppressing other output.
* `read_spec()` informs (class `vport_message_p21_sheet`) which sheet it
  used when several sheets in a Pinnacle 21 workbook match one role.
