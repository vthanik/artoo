# Encodings for clinical datasets, across R, SAS, and Python

List the character encodings clinical data actually travels in, with the
name each ecosystem uses for the same thing: the R name (the standard
IANA name, which [`iconv()`](https://rdrr.io/r/base/iconv.html) and the
wider R ecosystem use), the SAS session-encoding name, and the Python
codec. Any spelling from the `r` or `sas` column works as the `encoding`
argument of every artoo reader and writer.

## Usage

``` r
artoo_encodings()
```

## Value

*A `<data.frame>`* with one row per encoding and columns `r` (the R name
— the standard IANA name [`iconv()`](https://rdrr.io/r/base/iconv.html)
uses, and what artoo records in the metadata), `sas` (the SAS
session-encoding name), `python` (the Python codec name), and
`description`.

## Details

**What an encoding is.** Text is stored as bytes; an encoding is the
rule that maps those bytes to characters. Plain A-Z digits and
punctuation are the same bytes in every encoding listed here — the
differences only show in accented letters (a-umlaut, e-acute), special
symbols (micro, degree), and non-Latin scripts. Reading bytes with the
wrong rule is what turns a degree sign into garbage.

**Which one do I have?** In SAS, run
`PROC OPTIONS OPTION=ENCODING; RUN;` and look up the reported name in
the `sas` column. Most US/EU Windows SAS installs report `WLATIN1` —
that is `windows-1252` here.

**Which one should I write?** Usually none: `write_*(encoding = NULL)`
(the default) inherits the encoding recorded when the data was read, so
a round-trip is byte-faithful. The regulatory defaults artoo applies
when nothing is recorded: SAS XPORT writes `US-ASCII` (the FDA Study
Data Technical Conformance Guide expectation) and Dataset-JSON / NDJSON
write `UTF-8` (required by CDISC and RFC 8259). A value that cannot be
represented in the target encoding aborts loudly — see `on_invalid` on
the writers.

**Note:** in memory, artoo text is always UTF-8 (NFC-normalised) —
encodings only matter at the file boundary, exactly as in Python 3.

## See also

**Use it:** the `encoding` argument of
[`read_xpt()`](https://vthanik.github.io/artoo/dev/reference/read_xpt.md),
[`write_xpt()`](https://vthanik.github.io/artoo/dev/reference/write_xpt.md),
[`read_json()`](https://vthanik.github.io/artoo/dev/reference/read_json.md),
and the other readers/writers.

**Formats:**
[`artoo_formats()`](https://vthanik.github.io/artoo/dev/reference/artoo_formats.md)
for the codec registry.

## Examples

``` r
# ---- Example 1: the full cross-ecosystem table ----
#
# One row per encoding; the same byte rule under each ecosystem's name.
artoo_encodings()
#>               r       sas     python
#> 1         UTF-8     UTF-8      utf_8
#> 2      US-ASCII     ASCII      ascii
#> 3  windows-1252   WLATIN1     cp1252
#> 4  windows-1250   WLATIN2     cp1250
#> 5  windows-1251 WCYRILLIC     cp1251
#> 6    ISO-8859-1    LATIN1    latin_1
#> 7   ISO-8859-15    LATIN9 iso8859_15
#> 8         CP437  PCOEM437      cp437
#> 9         CP850  PCOEM850      cp850
#> 10    Shift_JIS SHIFT-JIS  shift_jis
#> 11        CP932    MS-932      cp932
#> 12       EUC-JP    EUC-JP     euc_jp
#> 13       EUC-KR    EUC-KR     euc_kr
#> 14        CP936    MS-936        gbk
#> 15        CP950    MS-950      cp950
#>                                                            description
#> 1  Unicode; Dataset-JSON requirement and the modern default everywhere
#> 2    7-bit basic Latin; what the FDA expects inside a submission XPORT
#> 3      Western European Windows; the usual US/EU SAS session (WLATIN1)
#> 4                                             Central European Windows
#> 5                                                     Cyrillic Windows
#> 6                                   Western European Unix SAS (LATIN1)
#> 7                         Western European with the euro sign (LATIN9)
#> 8                                   US DOS (OEM); very old PC archives
#> 9                     Western European DOS (OEM); very old PC archives
#> 10              Japanese (PMDA submissions from Japanese SAS sessions)
#> 11                      Japanese Windows (Microsoft Shift JIS variant)
#> 12                                                       Japanese Unix
#> 13                                                              Korean
#> 14                                    Simplified Chinese Windows (GBK)
#> 15                                  Traditional Chinese Windows (Big5)

# ---- Example 2: look up a SAS session encoding ----
#
# PROC OPTIONS reported WLATIN1: find the R and Python names for the
# same bytes (the sas and r spellings both work as encoding=).
enc <- artoo_encodings()
enc[enc$sas == "WLATIN1", ]
#>              r     sas python
#> 3 windows-1252 WLATIN1 cp1252
#>                                                       description
#> 3 Western European Windows; the usual US/EU SAS session (WLATIN1)
```
