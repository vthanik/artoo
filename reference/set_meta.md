# Attach metadata to a dataset

Stamp a `artoo_meta` onto a data frame as a single Dataset-JSON string
in its `metadata_json` attribute. Every `write_*()` codec reads that
string back with
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)
and embeds it verbatim, so the metadata survives the trip to any format.
Use it to attach metadata to a bare frame before a write, or to re-stamp
after a tidyverse verb has dropped attributes.

## Usage

``` r
set_meta(x, meta)
```

## Arguments

- x:

  *The data frame to stamp.* `<data.frame>: required`.

- meta:

  *The metadata to attach.* `<artoo_meta>: required`. Usually from
  [`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)
  or built by
  [`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md).

## Value

*The data frame `x`*, with its `metadata_json` attribute set. Pass it on
to a `write_*()` codec or back through
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md).

## See also

[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)
for the read half;
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
which stamps it.

## Examples

``` r
# ---- Example 1: re-stamp metadata a dplyr verb would drop ----
#
# Conform a dataset, capture its metadata, then re-attach after an
# attribute-dropping transform so the write stays lossless.
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
adsl <- apply_spec(cdisc_adsl, spec, "ADSL")
meta <- get_meta(adsl)
trimmed <- head(as.data.frame(adsl), 5)
attr(trimmed, "metadata_json") <- NULL
set_meta(trimmed, meta)
#>        STUDYID     USUBJID SUBJID SITEID SITEGR1                  ARM
#> 1 CDISCPILOT01 01-701-1015   1015    701     701              Placebo
#> 2 CDISCPILOT01 01-701-1023   1023    701     701              Placebo
#> 3 CDISCPILOT01 01-701-1028   1028    701     701 Xanomeline High Dose
#> 4 CDISCPILOT01 01-701-1033   1033    701     701  Xanomeline Low Dose
#> 5 CDISCPILOT01 01-701-1034   1034    701     701 Xanomeline High Dose
#>                 TRT01P TRT01PN               TRT01A TRT01AN     TRTSDT
#> 1              Placebo       0              Placebo       0 2014-01-02
#> 2              Placebo       0              Placebo       0 2012-08-05
#> 3 Xanomeline High Dose      81 Xanomeline High Dose      81 2013-07-19
#> 4  Xanomeline Low Dose      54  Xanomeline Low Dose      54 2014-03-18
#> 5 Xanomeline High Dose      81 Xanomeline High Dose      81 2014-07-01
#>       TRTEDT TRTDUR AVGDD CUMDOSE AGE AGEGR1 AGEGR1N  AGEU  RACE RACEN
#> 1 2014-07-02    182   0.0       0  63    <65       1 YEARS WHITE     1
#> 2 2012-09-01     28   0.0       0  64    <65       1 YEARS WHITE     1
#> 3 2014-01-14    180  77.7   13986  71  65-80       2 YEARS WHITE     1
#> 4 2014-03-31     14  54.0     756  74  65-80       2 YEARS WHITE     1
#> 5 2014-12-30    183  76.9   14067  77  65-80       2 YEARS WHITE     1
#>   SEX                 ETHNIC SAFFL ITTFL EFFFL COMP8FL COMP16FL
#> 1   F     HISPANIC OR LATINO     Y     Y     Y       Y        Y
#> 2   M     HISPANIC OR LATINO     Y     Y     Y       N        N
#> 3   M NOT HISPANIC OR LATINO     Y     Y     Y       Y        Y
#> 4   M NOT HISPANIC OR LATINO     Y     Y     Y       N        N
#> 5   F NOT HISPANIC OR LATINO     Y     Y     Y       Y        Y
#>   COMP24FL DISCONFL DSRAEFL DTHFL BMIBL BMIBLGR1 HEIGHTBL WEIGHTBL
#> 1        Y     <NA>    <NA>  <NA>  25.1   25-<30    147.3     54.4
#> 2        N        Y       Y  <NA>  30.4     >=30    162.6     80.3
#> 3        Y     <NA>    <NA>  <NA>  31.4     >=30    177.8     99.3
#> 4        N        Y    <NA>  <NA>  28.8   25-<30    175.3     88.5
#> 5        Y     <NA>    <NA>  <NA>  26.1   25-<30    154.9     62.6
#>   EDUCLVL   DISONSDT DURDIS DURDSGR1   VISIT1DT    RFSTDTC    RFENDTC
#> 1      16 2010-04-30   43.9     >=12 2013-12-26 2014-01-02 2014-07-02
#> 2      14 2006-03-11   76.4     >=12 2012-07-22 2012-08-05 2012-09-02
#> 3      16 2009-12-16   42.8     >=12 2013-07-11 2013-07-19 2014-01-14
#> 4      12 2009-08-02   55.3     >=12 2014-03-10 2014-03-18 2014-04-14
#> 5       9 2011-09-29   32.9     >=12 2014-06-24 2014-07-01 2014-12-30
#>   VISNUMEN     RFENDT                     DCDECOD         DCREASCD
#> 1       12 2014-07-02                   COMPLETED        Completed
#> 2        5 2012-09-02               ADVERSE EVENT    Adverse Event
#> 3       12 2014-01-14                   COMPLETED        Completed
#> 4        5 2014-04-14 STUDY TERMINATED BY SPONSOR Sponsor Decision
#> 5       12 2014-12-30                   COMPLETED        Completed
#>   MMSETOT
#> 1      23
#> 2      23
#> 3      23
#> 4      23
#> 5      21

# ---- Example 2: stamp a bare frame straight from a spec ----
#
# A writer with a raw frame and no apply step can build metadata from the
# spec and attach it directly.
meta_dm <- artoo:::.meta_from_spec(spec, "DM")
dm <- set_meta(cdisc_dm, meta_dm)
is_artoo_meta(get_meta(dm))
#> [1] TRUE
```
