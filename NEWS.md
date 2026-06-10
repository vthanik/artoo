# vport 0.0.0.9000

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
