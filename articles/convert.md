# Formats & lossless conversion

artoo’s conversion story is one sentence: every codec reads and writes
the same canonical metadata, so any format converts to any other without
loss. This article shows the round trips, what “lossless” means
concretely, how the encoding policy keeps a single bad byte from
deciding which formats your dataset can travel in, and the evidence a
regulated pipeline can point to.

## 1. One metadata model, four carriers

A conformed frame carries its `artoo_meta`; each writer embeds it in the
format’s own idiom (XPORT NAMESTR records, the Dataset-JSON itemGroup, a
Parquet key-value sidecar, rds attributes):

``` r

dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
```

    1 variable the spec declares is absent from the data (not added): `BRTHDTC`.

``` r

xpt <- tempfile(fileext = ".xpt")
json <- tempfile(fileext = ".json")
parquet <- tempfile(fileext = ".parquet")
dm |>
  write_xpt(xpt) |>
  write_json(json) |>
  write_parquet(parquet)
```

Conversion is read one, write the other — and the metadata survives the
hop:

``` r

from_xpt <- read_xpt(xpt)
identical(get_meta(from_xpt)@columns, get_meta(read_json(json))@columns)
```

    [1] FALSE

One caveat is structural, not artoo’s: XPORT v5 cannot carry
`keySequence`, codelist references, or origin (its NAMESTR record has no
field for them), so an `.xpt`-sourced frame shows a blank Key pane by
design. Route through Dataset-JSON or Parquet when those must survive.

## 2. Encodings: recorded, inherited, never silently transformed

artoo text is always UTF-8 in memory; encodings matter only at the file
boundary. Each reader records the source encoding in the metadata, and
`write_*(encoding = NULL)` inherits it, so a round trip is
byte-faithful. The name rosetta lives in
[`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md):

``` r

enc <- artoo_encodings()
enc[enc$sas == "WLATIN1", ]
```

                 r     sas python
    3 windows-1252 WLATIN1 cp1252
                                                          description
    3 Western European Windows; the usual US/EU SAS session (WLATIN1)

## 3. `on_invalid`: one policy, all four writers

A value that cannot be represented in the target — an unencodable
character for xpt’s target charset, or bytes that are not valid UTF-8
for Dataset-JSON / NDJSON / Parquet — hits the same three-way policy
everywhere: `"error"` (default), `"replace"`, or `"ignore"`. The default
names the offenders hex-escaped:

``` r

bad <- dm
bad$USUBJID[1] <- rawToChar(as.raw(c(0x63, 0xE9))) # a stray latin1 byte
write_json(bad, tempfile(fileext = ".json"))
```

    Error in `write_json()`:
    ! Cannot encode 1 value as UTF-8.
    ✖ Invalid bytes (hex-escaped): "c<e9>".
    ℹ Re-read the source with the correct `encoding`, or set `on_invalid`.

`"replace"` substitutes `?` and warns, so the write completes and the
file is valid:

``` r

fixed <- tempfile(fileext = ".json")
write_json(bad, fixed, on_invalid = "replace")
```

    Warning in write_json(bad, fixed, on_invalid = "replace"): Replaced invalid UTF-8 bytes with "?" in 1 value.
    ℹ Use `on_invalid = "error"` to fail loudly instead.

``` r

read_json(fixed)$USUBJID[1]
```

    [1] "c?"

The right fix is upstream — re-read the source with its true `encoding=`
so the bytes arrive as the characters they were — but the policy means a
mis-declared byte in one record no longer makes a dataset “submittable
as XPT but not as Dataset-JSON”, or vice versa.

## 4. Qualification: the evidence behind “lossless”

The first question a pharma organization asks of any package in a
submission pipeline is “can we qualify this?”. None of the below is a
regulatory claim — qualification is your process — but every property is
machine-checkable in your own environment.

**Lossless or loud.** Read-write-read returns the same values and the
same metadata; a lossy coercion or an unencodable byte aborts rather
than damaging data; even the explicit `extra = "drop"` trim announces
itself and leaves a finding. The data-protection conditions carry their
evidence as data, so a harness asserts on it programmatically:

``` r

vars <- spec_variables(adam_spec)
vars$data_type[vars$variable == "AGE"] <- "integer"
strict <- artoo_spec(
  adam_spec@datasets, vars,
  codelists = adam_spec@codelists,
  study = spec_study(adam_spec)
)
raw <- cdisc_adsl
raw$AGE[1] <- raw$AGE[1] + 0.5
tryCatch(
  apply_spec(raw, strict, "ADSL", conformance = "off"),
  artoo_error_type = function(cnd) cnd$variables
)
```

      variable data_type n    reason
    1      AGE   integer 1 truncated

**The development gates**, enforced on every change and in CI:
`R CMD check` at 0 errors / 0 warnings / 0 notes; a test suite in the
thousands of assertions, including byte-level golden files for the
codecs, a cross-format round-trip matrix, and fuzzed-input tests that
assert every failure is a classed artoo condition; line coverage of at
least 95% on every file in `R/`; and reproducible demo data, every
bundled object rebuilt by script from public, checksum-pinned sources.

**Standards the behavior is pinned to**, cited in the docs rather than
re-invented: CDISC Dataset-JSON v1.1 (type vocabulary, UTF-8), the FDA
Study Data Technical Conformance Guide (XPORT expectations, ASCII gate),
SAS XPORT v5/v8 (TS-140/TS-340), RFC 8259, IANA character set names, and
Unicode NFC (UAX \#15).

## Where to next

- [Specifications](https://vthanik.github.io/artoo/articles/specs.md) —
  the spec whose metadata every codec carries.
- [Conform &
  validate](https://vthanik.github.io/artoo/articles/conform.md) —
  produce the conformed frame these writers persist.
- [Recipes](https://vthanik.github.io/artoo/articles/recipes.md) —
  conversion inside an end-to-end ADaM and SDTM build.
- [Get started](https://vthanik.github.io/artoo/articles/artoo.md) — the
  round-trip from the top.
