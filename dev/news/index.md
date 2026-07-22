# Changelog

## artoo 0.1.3.9000

## artoo 0.1.3

- [`artoo_checks()`](https://vthanik.github.io/artoo/dev/reference/artoo_checks.md)
  gained an `invalid_encoding` dimension (on by default):
  [`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)
  flags character values whose bytes are not valid UTF-8, the signature
  of a source read under a mis-declared encoding, before a writer aborts
  on them.

- [`artoo_encodings()`](https://vthanik.github.io/artoo/dev/reference/artoo_encodings.md)
  name resolution now accepts the SAS OEM/DOS encoding names
  (`pcoem437`, `pcoem850`, `pcoem852`, `pcoem858`, `pcoem862`,
  `pcoem866`, `msdos737`), and the reference table lists the `PCOEM437`
  / `PCOEM850` rows.

- [`write_xpt()`](https://vthanik.github.io/artoo/dev/reference/write_xpt.md),
  [`write_json()`](https://vthanik.github.io/artoo/dev/reference/write_json.md),
  [`write_ndjson()`](https://vthanik.github.io/artoo/dev/reference/write_ndjson.md),
  and
  [`write_parquet()`](https://vthanik.github.io/artoo/dev/reference/write_parquet.md)
  accept `on_invalid = "translit"`, folding smart punctuation (curly
  quotes, en/em dashes, ellipsis, bullet) to its exact ASCII form per
  the SAS NLS punctuation table; characters with no fold still abort
  loudly.

- [`write_xpt()`](https://vthanik.github.io/artoo/dev/reference/write_xpt.md),
  [`write_json()`](https://vthanik.github.io/artoo/dev/reference/write_json.md),
  [`write_ndjson()`](https://vthanik.github.io/artoo/dev/reference/write_ndjson.md),
  and
  [`write_parquet()`](https://vthanik.github.io/artoo/dev/reference/write_parquet.md)
  also accept `on_invalid = "fold"`: the punctuation fold plus the ICU
  Latin-ASCII accent strip (`Ö` to `O`, `ß` to `ss`, `Æ` to `AE`),
  pinned as data so the result is identical on every platform;
  characters neither table maps (the Euro sign) still abort.

- [`write_xpt()`](https://vthanik.github.io/artoo/dev/reference/write_xpt.md)
  now warns (`artoo_warning_encoding`) when a value forces a column
  wider than its spec-declared length, instead of widening silently;
  data is still never truncated.

- [`write_xpt()`](https://vthanik.github.io/artoo/dev/reference/write_xpt.md)
  and the other writers’ `on_invalid = "replace"` now substitutes one
  `?` per unrepresentable character instead of one per byte (a curly
  quote previously became `???`).

- New article: *Migrating clinical data from WLATIN1 to UTF-8*,
  including the smart-punctuation fold table and the byte-length
  migration recipe.

## artoo 0.1.2

CRAN release: 2026-07-02

- Guarded the decimal full-precision JSON round-trip test on
  `capabilities("long.double")` so it skips on noLD builds, where
  bit-exact double-to-string round-trips are not guaranteed by the
  platform C library.

## artoo 0.1.1

CRAN release: 2026-06-24

Initial CRAN release. artoo is a lightweight, lossless, CDISC-native
reader and writer for clinical-trial datasets, built around one
canonical metadata model (`artoo_meta`) so that conversion between any
two supported formats is lossless by construction. Pure R and
lightweight, with no external SAS or Java runtime.

### Formats

- Reads and writes SAS XPORT (v5 and v8), CDISC Dataset-JSON v1.1,
  NDJSON, Apache Parquet, and RDS. Every codec carries the full
  `artoo_meta` — labels, CDISC data types, lengths, SAS display formats,
  controlled-terminology references, and sort keys — so any-to-any
  conversion preserves the complete metadata. For Parquet the metadata
  rides as a `metadata_json` sidecar; a file written by another tool
  with no sidecar degrades gracefully to a bare frame rather than an
  error.

- Generic
  [`read_dataset()`](https://vthanik.github.io/artoo/dev/reference/read_dataset.md)
  /
  [`write_dataset()`](https://vthanik.github.io/artoo/dev/reference/write_dataset.md)
  dispatch on the file extension, with
  [`read_xpt()`](https://vthanik.github.io/artoo/dev/reference/read_xpt.md)
  /
  [`write_xpt()`](https://vthanik.github.io/artoo/dev/reference/write_xpt.md)
  and the matching
  [`read_json()`](https://vthanik.github.io/artoo/dev/reference/read_json.md),
  [`read_ndjson()`](https://vthanik.github.io/artoo/dev/reference/read_ndjson.md),
  [`read_parquet()`](https://vthanik.github.io/artoo/dev/reference/read_parquet.md),
  and
  [`read_rds()`](https://vthanik.github.io/artoo/dev/reference/read_rds.md)
  pairs as direct entry points. Cross-cutting `encoding`, `checks`, and
  `created` arguments flow through `...`.

- Partial reads (`col_select`, `n_max`) on every reader;
  gzip-transparent JSON and NDJSON; multi-member SAS XPORT libraries via
  [`xpt_members()`](https://vthanik.github.io/artoo/dev/reference/xpt_members.md)
  plus `read_xpt(member = )`.

- Numeric fidelity is exact end to end: a `decimal` value is exchanged
  as a string at IEEE round-trip precision, `integer` values beyond R’s
  32-bit range stay numeric rather than overflowing, and `NaN` /
  infinite values are rejected as invalid CDISC numerics. Rows are
  sorted in C-locale (byte) order, so a written file is deterministic
  across locales and matches SAS `PROC SORT` for ASCII keys.

- Encodings follow the IANA and SAS standards: the readers and writers
  accept a charset name in either the SAS or R spelling (see
  [`artoo_encodings()`](https://vthanik.github.io/artoo/dev/reference/artoo_encodings.md)),
  character columns are transcoded to UTF-8 and NFC-normalized on read,
  and the `on_invalid = c("error", "replace", "ignore")` policy governs
  invalid bytes uniformly across every writer.

### Specifications

- [`artoo_spec()`](https://vthanik.github.io/artoo/dev/reference/artoo_spec.md)
  builds the canonical metadata model from a Pinnacle 21 Excel workbook,
  a Define-XML 2.0 / 2.1 file, or a native artoo JSON spec.
  [`read_spec()`](https://vthanik.github.io/artoo/dev/reference/read_spec.md)
  /
  [`write_spec()`](https://vthanik.github.io/artoo/dev/reference/write_spec.md)
  dispatch on the file extension: `.xlsx` writes a Pinnacle 21 workbook
  (Define-XML to P21 is one composition), and the native JSON form is
  the lossless interchange that round-trips a spec identically.

- The spec is single-standard by construction: `@standard` is resolved
  once from the explicit argument or the source, and study-level fields
  are canonicalized to the CDISC ODM vocabulary. Accessors include
  [`spec_standard()`](https://vthanik.github.io/artoo/dev/reference/spec_standard.md),
  [`spec_variables()`](https://vthanik.github.io/artoo/dev/reference/spec_variables.md),
  [`spec_codelists()`](https://vthanik.github.io/artoo/dev/reference/spec_codelists.md),
  [`spec_methods()`](https://vthanik.github.io/artoo/dev/reference/spec_methods.md),
  and
  [`spec_comments()`](https://vthanik.github.io/artoo/dev/reference/spec_comments.md).

- [`set_type()`](https://vthanik.github.io/artoo/dev/reference/set_type.md)
  returns a spec with one or more variables retyped through the CDISC
  vocabulary;
  [`repair_spec()`](https://vthanik.github.io/artoo/dev/reference/repair_spec.md)
  retypes every variable a
  [`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)
  run flags as fractional or out-of-range under an `integer` data type,
  so a frame the original spec would refuse coerces after one call.

### Conform and check

- `apply_spec(x, spec, dataset, conformance = , na_position = )` coerces
  each column to its CDISC data type, orders the columns and sorts the
  rows by the spec’s keys, and stamps the `artoo_meta`.
  `extra = c("keep", "drop")` controls whether undeclared columns
  survive; `on_coercion_loss = c("error", "keep")` governs a coercion
  that would lose data. The pipeline never silently fabricates or drops
  a column: an undeclared column is reported and kept, a
  declared-but-absent column is reported and left absent.

- [`check_spec()`](https://vthanik.github.io/artoo/dev/reference/check_spec.md)
  validates a data frame against its spec across conformance dimensions
  toggled by
  [`artoo_checks()`](https://vthanik.github.io/artoo/dev/reference/artoo_checks.md);
  [`check_study()`](https://vthanik.github.io/artoo/dev/reference/check_study.md)
  runs it over a whole study and returns one stacked findings frame;
  [`conformance()`](https://vthanik.github.io/artoo/dev/reference/conformance.md)
  reads the findings back off a stamped frame.
  [`validate_spec()`](https://vthanik.github.io/artoo/dev/reference/validate_spec.md)
  checks a spec for internal consistency against a bundled rule catalog,
  with no external dependency.

- [`decode_column()`](https://vthanik.github.io/artoo/dev/reference/decode_column.md)
  translates coded values to or from their codelist decodes;
  [`sync_meta()`](https://vthanik.github.io/artoo/dev/reference/sync_meta.md)
  reconciles a stamped frame’s metadata after manual edits.

### Inspect

- [`members()`](https://vthanik.github.io/artoo/dev/reference/members.md)
  is the format-neutral inventory of the dataset(s) a path holds, one
  row per dataset, dispatched through the codec registry.
  [`columns()`](https://vthanik.github.io/artoo/dev/reference/columns.md)
  is the SAS PROC CONTENTS / Universal Viewer variable pane over a
  stamped frame, a plain data frame, or a file path.
  [`get_meta()`](https://vthanik.github.io/artoo/dev/reference/get_meta.md)
  /
  [`set_meta()`](https://vthanik.github.io/artoo/dev/reference/set_meta.md)
  read and attach the `artoo_meta`.

### Errors

- Every condition artoo raises carries a three-level class chain —
  `artoo_<severity>_<kind>`, `artoo_<severity>`, `artoo_condition` — so
  a handler can catch a specific kind, a whole severity, or every artoo
  condition. The data-protection conditions attach their evidence as
  data (`cnd$variables`, `cnd$findings`) for programmatic inspection.

### Data

- Bundled demo specs `adam_spec` (ADaMIG 1.1) and `sdtm_spec` (SDTMIG
  3.1.2), built reproducibly from the official CDISC Define-XML 2.1
  release examples and shipped also as Pinnacle 21 workbooks under
  `inst/extdata/`. Demo datasets come from the PHUSE Test Data Factory;
  the constructor tables `cdisc_adam_datasets` / `cdisc_adam_variables`,
  `cdisc_sdtm_datasets` / `cdisc_sdtm_variables`, and the shared
  `cdisc_codelists` build a spec by hand. Every bundled dataset conforms
  to its bundled spec, gated at build and test time.

### Documentation

- An introductory
  [`vignette("artoo")`](https://vthanik.github.io/artoo/dev/articles/artoo.md)
  plus task-oriented web articles (specifications; conform and validate;
  formats and lossless conversion; recipes), and a pkgdown reference
  site.
