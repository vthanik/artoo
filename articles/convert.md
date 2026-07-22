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

    Warning in write_xpt(dm, xpt): Widened 1 column past the declared spec length: "STUDYID (7 -> 12)".
    ℹ Values need more bytes than the spec length; data was kept whole.
    ℹ Update the spec length, or shorten the data, so the file matches its declared
      metadata.

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

### Reading a file whose bytes are not UTF-8

`encoding=` on a reader is a *transcode*, not a label. Say a Parquet
file was written by a system whose text is Windows-1252 (SAS `WLATIN1`)
rather than the UTF-8 the Parquet spec assumes:

``` r

latin1 <- function(x) {
  out <- iconv(x, "UTF-8", "windows-1252")
  Encoding(out) <- "unknown"
  out
}
foreign <- data.frame(
  SITEID = latin1(c("PARIS", "MÜNCHEN")),
  INVNAM = latin1(c("Curie", "Öztürk"))
)
pq <- tempfile(fileext = ".parquet")
nanoparquet::write_parquet(foreign, pq)
```

Naming the source charset converts the bytes to UTF-8 and normalises
them to NFC, so what lands in R is ordinary text — printing,
[`View()`](https://rdrr.io/r/utils/View.html),
[`nchar()`](https://rdrr.io/r/base/nchar.html), regex, and collation all
behave, and every writer downstream re-encodes from there:

``` r

site <- read_parquet(pq, encoding = "wlatin1")
site
```

       SITEID INVNAM
    1   PARIS  Curie
    2 MÜNCHEN Öztürk

``` r

nchar(site$SITEID) # characters, not bytes
```

    [1] 5 7

``` r

grepl("Ü", site$SITEID)
```

    [1] FALSE  TRUE

Two ways it can look wrong, both diagnostic rather than silent:

*Mojibake* (`MÃœNCHEN`) means you declared an `encoding=` for a file
that was already UTF-8 — drop the argument. A hex escape (`caf<e9>`)
means a byte that is not valid in the charset you named; artoo escapes
it rather than dropping it, so the corruption stays visible.

And omitting `encoding=` on a genuinely non-UTF-8 file is not a silent
mis-read either — the reader refuses it:

``` r

read_parquet(pq)
```

    Error in `read_parquet()`:
    ! Could not read '/tmp/Rtmpa3pflr/file1e396dc1bd6b.parquet' as
      "parquet".
    ✖ entry 2 has wrong Encoding; marked as "UTF-8" but leading byte 0xDC followed
      by invalid continuation byte (0x4E) at position 3

## 3. `on_invalid`: one policy, all four writers

A value that cannot be represented in the target — an unencodable
character for xpt’s target charset, or bytes that are not valid UTF-8
for Dataset-JSON / NDJSON / Parquet — hits the same policy everywhere:
`"error"` (default), `"replace"`, `"ignore"`, or `"translit"` (fold
smart punctuation to its exact ASCII form; see the [WLATIN1 → UTF-8
migration
article](https://vthanik.github.io/artoo/articles/migrate-encoding.md)).
The default names the offenders hex-escaped:

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
