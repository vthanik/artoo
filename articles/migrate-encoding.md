# Migrating clinical data from WLATIN1 to UTF-8

Most legacy clinical data was produced by SAS sessions running WLATIN1
(Windows-1252); modern pipelines — Dataset-JSON, Parquet, R itself — are
UTF-8. The two agree on every ASCII character and disagree everywhere
else, so a migration has exactly three failure modes: mojibake (bytes
interpreted as the wrong charset), truncation (byte-counted lengths that
multibyte UTF-8 overflows), and unrepresentable characters (an ASCII
target that cannot carry what UTF-8 can). This article shows how artoo
handles each one.

## 1. Reading WLATIN1 data

[`read_xpt()`](https://vthanik.github.io/artoo/reference/read_xpt.md)
detects the encoding: if every byte in the file validates as UTF-8 it
reads as UTF-8, otherwise it assumes Windows-1252 — the right default
for legacy clinical files. Formats whose spec pins UTF-8 (Dataset-JSON,
Parquet) are read as UTF-8 and *refuse loudly* when the bytes disagree,
rather than guessing:

``` r

latin1 <- function(x) {
  out <- iconv(x, "UTF-8", "windows-1252")
  Encoding(out) <- "unknown"
  out
}
foreign <- data.frame(SITEID = latin1(c("PARIS", "MÜNCHEN")))
pq <- tempfile(fileext = ".parquet")
nanoparquet::write_parquet(foreign, pq)
read_parquet(pq)
```

    Error in `read_parquet()`:
    ! Could not read '/tmp/Rtmpv5ttC2/file1e8169d629ff.parquet' as
      "parquet".
    ✖ entry 2 has wrong Encoding; marked as "UTF-8" but leading byte 0xDC followed
      by invalid continuation byte (0x4E) at position 3

That refusal is the prompt to name the true source charset. `encoding=`
is a *transcode*, not a label — the bytes are converted to UTF-8 and
normalised (NFC), so what lands in R is ordinary text:

``` r

site <- read_parquet(pq, encoding = "wlatin1")
site$SITEID
```

    [1] "PARIS"   "MÜNCHEN"

Any SAS or IANA spelling works — `"wlatin1"`, `"cp1252"`,
`"windows-1252"` are the same charset; so are the OEM/DOS names
(`"pcoem850"`) a very old archive might declare. The rosetta is
[`artoo_encodings()`](https://vthanik.github.io/artoo/reference/artoo_encodings.md).
Note that `"latin1"` (ISO-8859-1) is **not** WLATIN1: the two differ
across the 0x80–0x9F range that holds the Euro sign and every smart
quote.

## 2. Catching a mis-declared read

The classic silent corruption is reading WLATIN1 bytes *as if* they were
UTF-8 (in SAS terms: a data set whose encoding attribute lies). Those
bytes do not validate as UTF-8, and the `invalid_encoding` conformance
dimension flags them before any writer runs:

``` r

bad <- cdisc_dm
bad$ETHNIC <- rawToChar(as.raw(c(0x4D, 0xDC, 0x4E))) # WLATIN1 bytes, raw
f <- check_spec(bad, sdtm_spec, "DM")
f[f$check == "invalid_encoding", c("variable", "severity", "message")]
```

       variable severity
    14   ETHNIC    error
                                                                                                    message
    14 'ETHNIC' has 60 value(s) whose bytes are not valid UTF-8; re-read the source with its true encoding.

The fix is always upstream — re-read the source with its true
`encoding=` — never a re-label.

## 3. Lengths are bytes, and UTF-8 needs more of them

A WLATIN1 character is always one byte; in UTF-8 the same character can
take up to four. A spec length calibrated on WLATIN1 data (`Ö` = 1 byte)
under-declares the UTF-8 form (`Ö` = 2 bytes). SAS handles this with the
CVP engine and a guessed multiplier; artoo measures the actual bytes,
never truncates, and tells you when the declared length had to give:

``` r

sp <- artoo_spec(
  data.frame(dataset = "DM"),
  data.frame(
    dataset = "DM", variable = "INVNAM",
    data_type = "string", length = 6L
  )
)
x <- apply_spec(
  data.frame(INVNAM = "Öztürk"), sp, "DM",
  conformance = "off"
)
xpt <- tempfile(fileext = ".xpt")
write_xpt(x, xpt)
```

    Warning in write_xpt(x, xpt): Widened 1 column past the declared spec length: "INVNAM (6 -> 8)".
    ℹ Values need more bytes than the spec length; data was kept whole.
    ℹ Update the spec length, or shorten the data, so the file matches its declared
      metadata.

The `length_overflow` check reports the same fact at conformance time,
so a migration can fix the spec (the durable answer) instead of relying
on the writer’s defence.

## 4. Smart punctuation: the WLATIN1 characters ASCII can fold

Text that passed through a word processor carries typographic
punctuation — curly quotes, en/em dashes, ellipses. In WLATIN1 these
live in rows 8–9 of the code page (one byte each); in UTF-8 they are
three bytes each; in US-ASCII they do not exist at all. They are also
the one class of character with an *exact* ASCII equivalent, published
by SAS as the NLS punctuation fold:

| WLATIN1 (hex) | Unicode | Character | Description                       | ASCII fold |
|---------------|---------|:---------:|-----------------------------------|:----------:|
| `82`          | U+201A  |     ‚     | single low-9 quotation mark       |    `,`     |
| `84`          | U+201E  |     „     | double low-9 quotation mark       |    `"`     |
| `85`          | U+2026  |     …     | horizontal ellipsis               |   `...`    |
| `8B`          | U+2039  |     ‹     | single left-pointing angle quote  |    `<`     |
| `91`          | U+2018  |     ‘     | left single quotation mark        |    `'`     |
| `92`          | U+2019  |     ’     | right single quotation mark       |    `'`     |
| `93`          | U+201C  |     “     | left double quotation mark        |    `"`     |
| `94`          | U+201D  |     ”     | right double quotation mark       |    `"`     |
| `95`          | U+2022  |     •     | bullet                            |    `*`     |
| `96`          | U+2013  |     –     | en dash                           |    `-`     |
| `97`          | U+2014  |     —     | em dash                           |    `-`     |
| `9B`          | U+203A  |     ›     | single right-pointing angle quote |    `>`     |

Every writer accepts `on_invalid = "translit"`, which applies exactly
this table and nothing else:

``` r

note <- data.frame(
  USUBJID = "01-701-1015",
  COMMENT = "Patient’s dose – “held”…"
)
ascii_xpt <- tempfile(fileext = ".xpt")
write_xpt(note, ascii_xpt, encoding = "US-ASCII", on_invalid = "translit")
```

    Warning in write_xpt(note, ascii_xpt, encoding = "US-ASCII", on_invalid = "translit"): Transliterated smart punctuation to ASCII in 1 value for "US-ASCII".
    ℹ The fold follows the SAS NLS punctuation table (quotes, dashes, ellipsis,
      bullet).

``` r

read_xpt(ascii_xpt)$COMMENT
```

    [1] "Patient's dose - \"held\"..."

`"translit"` is deliberately narrower than `"replace"`: punctuation
folds because the ASCII form carries the same meaning; a character with
no equivalent — a diacritic in a name — still aborts, because `"Öztürk"`
silently becoming `"Ozturk"` (or worse, `"?zt?rk"`) is data corruption,
not conversion:

``` r

name <- data.frame(INVNAM = "Öztürk")
write_xpt(name, tempfile(fileext = ".xpt"),
  encoding = "US-ASCII", on_invalid = "translit"
)
```

    Error in `write_xpt()`:
    ! Cannot encode 1 value to "US-ASCII" even after punctuation folding.
    ✖ Offending value: "Öztürk".
    ℹ Only smart punctuation has an ASCII fold; use `on_invalid = "fold"` to also
      strip accents, or write to Dataset-JSON (UTF-8).

## 5. Accent stripping: the full fold, opted into

Sometimes stripping accents *is* the documented migration decision — the
SAS `BASECHAR()` function exists for exactly this. artoo’s equivalent is
`on_invalid = "fold"`: the punctuation table above **plus** the ICU
Latin-ASCII transliteration for the rest of the WLATIN1 range (`À–ÿ` to
their base letters, `Æ` → `AE`, `ß` → `ss`, `Þ` → `TH`, `×` → `*`, `«»`
→ `<<` `>>`, `½` → `1/2`). The table is pinned inside artoo, so — unlike
`iconv //TRANSLIT`, whose output differs between Linux and macOS — the
fold is byte-identical on every platform:

``` r

names_df <- data.frame(INVNAM = c("Öztürk", "Straße", "Ærø"))
folded_xpt <- tempfile(fileext = ".xpt")
write_xpt(names_df, folded_xpt, encoding = "US-ASCII", on_invalid = "fold")
```

    Warning in write_xpt(names_df, folded_xpt, encoding = "US-ASCII", on_invalid = "fold"): Folded 3 values to ASCII for "US-ASCII" (accents stripped).
    ℹ The fold follows the SAS NLS punctuation table plus ICU Latin-ASCII; the
      original characters are not recoverable from the output.

``` r

read_xpt(folded_xpt)$INVNAM
```

    [1] "Ozturk"  "Strasse" "AEro"   

The warning is the audit trail: the fold is one-way, and the original
characters are not recoverable from the output. A character neither
authority maps to ASCII — the Euro sign, the trademark sign, `µ`, `°` —
still aborts, because artoo invents no mappings:

``` r

cost <- data.frame(COMMENT = "total €100")
write_xpt(cost, tempfile(fileext = ".xpt"),
  encoding = "US-ASCII", on_invalid = "fold"
)
```

    Error in `write_xpt()`:
    ! Cannot encode 1 value to "US-ASCII" even after ASCII folding.
    ✖ Offending value: "total €100".
    ℹ The character has no standards-backed ASCII fold (ICU Latin-ASCII leaves it
      unmapped); write to Dataset-JSON (UTF-8), or set `on_invalid`.

The escalation ladder, least to most lossy: `"error"` (refuse) →
`"translit"` (fold punctuation only) → `"fold"` (also strip accents) →
`"replace"` (`?` per character) → `"ignore"` (drop). Pick the earliest
rung your migration plan allows.

## 6. The migration recipe

1.  **Read with the true source encoding.** Let
    [`read_xpt()`](https://vthanik.github.io/artoo/reference/read_xpt.md)
    detect, or pass `encoding = "wlatin1"` explicitly for formats that
    cannot carry the answer. Verify with
    [`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
    — zero `invalid_encoding` findings means the bytes arrived as
    characters.
2.  **Re-measure lengths in bytes.** Run the `length_overflow` dimension
    against the UTF-8 form and update the spec where multibyte
    characters grew.
3.  **Write UTF-8 by default** (Dataset-JSON, Parquet, xpt v8 all carry
    it losslessly). For a US-ASCII submission XPT, write with
    `encoding = "US-ASCII", on_invalid = "translit"` — punctuation
    folds, genuine data problems stay loud. Escalate to
    `on_invalid = "fold"` only when accent stripping is a documented
    step of the migration plan.

## References

- SAS 9.4 NLS Reference Guide, *Migrating Data from WLATIN1 to UTF-8*
  (the WLATIN1 code-page figures and the smart-punctuation table):
  <https://documentation.sas.com/doc/en/pgmmvacdc/9.4/nlsref/n15e31tqdv020en1fok7tp4l9zd5.htm>
- Bouedo, M. (2020), *The SAS Encoding Journey: A Byte at a Time*, SAS
  Global Forum paper 4561-2020:
  <https://www.sas.com/content/dam/SAS/support/en/sas-global-forum-proceedings/2020/4561-2020.pdf>
- FDA Study Data Technical Conformance Guide (the ASCII expectation for
  submission XPORT): <https://www.fda.gov/media/153632/download>
- Unicode Standard Annex \#15, *Unicode Normalization Forms* (the NFC
  form artoo canonicalises to): <https://unicode.org/reports/tr15/>
