# List the members of a SAS XPORT transport file

Report every dataset (member) a SAS Transport (`.xpt`) file holds, with
its label, variable count, and row count — the survey step before
[`read_xpt()`](https://vthanik.github.io/artoo/reference/read_xpt.md)
with `member =` picks one. A single-member file (the FDA submission
convention) returns one row.

## Usage

``` r
xpt_members(path)
```

## Arguments

- path:

  *Source `.xpt` path.* `<character(1)>: required`. A file that is not a
  valid XPORT library aborts with `artoo_error_codec`.

## Value

*A `<data.frame>`* with one row per member and columns `member` (1-based
index), `name`, `label`, `nvars`, and `nobs`. Pass `member` or `name` to
[`read_xpt()`](https://vthanik.github.io/artoo/reference/read_xpt.md).

## Details

**v5 has no recorded row count.** A v8 member records its rows; a v5
member's count is derived from the byte span up to the next member (or
end of file) minus trailing padding, so an all-character v5 member whose
last row is entirely blank reports one row fewer (the documented v5
ambiguity, see
[`write_xpt()`](https://vthanik.github.io/artoo/reference/write_xpt.md)).

## See also

[`read_xpt()`](https://vthanik.github.io/artoo/reference/read_xpt.md)
with `member =` to read one of them.

## Examples

``` r
spec <- artoo_spec(
  cdisc_adam_datasets, cdisc_adam_variables,
  codelists = cdisc_codelists
)

# ---- Example 1: a single-member file reports one row ----
#
# The FDA convention is one dataset per transport file.
dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#> 1 variable the spec declares is absent from the data (not added):
#> `BRTHDTC`.
p <- tempfile(fileext = ".xpt")
write_xpt(dm, p)
#> Warning: Widened 1 column past the declared spec length: "STUDYID (7 -> 12)".
#> ℹ Values need more bytes than the spec length; data was kept whole.
#> ℹ Update the spec length, or shorten the data, so the file matches its
#>   declared metadata.
xpt_members(p)
#>   member name        label nvars nobs
#> 1      1   DM Demographics    25   60

# ---- Example 2: survey a multi-member file, then read one member ----
#
# Concatenate two single-member files into one library and list it.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
p2 <- tempfile(fileext = ".xpt")
write_xpt(adsl, p2)
multi <- tempfile(fileext = ".xpt")
writeBin(
  c(
    readBin(p, "raw", file.size(p)),
    readBin(p2, "raw", file.size(p2))[-(1:240)]
  ),
  multi
)
xpt_members(multi)
#>   member name                          label nvars nobs
#> 1      1   DM                   Demographics    25   60
#> 2      2 ADSL Subject-Level Analysis Dataset    48   60
```
