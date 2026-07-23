# Report which formats are available

List every registered codec and whether it can read and write in this
session. The pure-R formats (xpt, json, rds) are always available;
optional-engine formats (parquet) report `FALSE` until their package is
installed. Purely informational, modelled on the diagnostic helpers in
the wider ecosystem; it never aborts.

## Usage

``` r
artoo_formats()
```

## Value

*A `<data.frame>`* with one row per format and columns `format`, `read`,
`write` (logical), and `extensions`.

## See also

[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md)
and
[`write_dataset()`](https://vthanik.github.io/artoo/reference/write_dataset.md)
which use the registry.

## Examples

``` r
# ---- Example 1: see what this session can read and write ----
#
# rds is always available; the table shows the extensions each codec claims.
artoo_formats()
#>    format read write    extensions
#> 1    json TRUE  TRUE          json
#> 2  ndjson TRUE  TRUE ndjson, jsonl
#> 3 parquet TRUE  TRUE   parquet, pq
#> 4     rds TRUE  TRUE           rds
#> 5     xpt TRUE  TRUE    xpt, xport
```
