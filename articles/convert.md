# Any-to-any conversion

artoo’s conversion story is one sentence: every codec reads and writes
the same canonical metadata, so any format converts to any other without
loss. This article shows the round trips, what “lossless” means
concretely, and how the encoding policy keeps a single bad byte from
deciding which formats your dataset can travel in.

## 1. One metadata model, four carriers

A conformed frame carries its `artoo_meta`; each writer embeds it in the
format’s own idiom (XPORT NAMESTR records, the Dataset-JSON itemGroup, a
Parquet key-value sidecar, rds attributes):

``` r

dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
```

    Scaffolded 1 variable: `BRTHDTC`

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

## Where to next

- [An end-to-end ADaM
  build](https://vthanik.github.io/artoo/articles/adam-build.md) — the
  derivation loop.
- [Validation &
  qualification](https://vthanik.github.io/artoo/articles/validation.md)
  — what “lossless” buys in a regulated setting.
