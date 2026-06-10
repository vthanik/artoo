

<!-- README.md is generated from README.qmd. Please edit that file -->

# vport <a href="https://vthanik.github.io/vport/"><img src="man/figures/logo.png" align="right" height="139" alt="vport website" /></a>

<!-- badges: start -->

[![R-CMD-check](https://github.com/vthanik/vport/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/vthanik/vport/actions/workflows/R-CMD-check.yaml) [![Codecov test coverage](https://codecov.io/gh/vthanik/vport/graph/badge.svg)](https://app.codecov.io/gh/vthanik/vport) [![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active) <!-- badges: end -->

**vport** (“versatile port”) is a lightweight, lossless, CDISC-native reader and writer for clinical-trial datasets. It moves data between **SAS XPORT (XPT)**, **CDISC Dataset-JSON v1.1**, **Apache Parquet**, and **RDS** through one canonical metadata model, so converting between any two formats is lossless *by construction* — not by best effort.

It is **pure R and lightweight**: no external SAS or Java runtime, and no heavy I/O dependency. One metadata model carries labels, CDISC data types, lengths, SAS display formats, controlled-terminology references, and sort keys identically across every format.

## Installation

``` r
# install.packages("pak")
pak::pak("vthanik/vport")
```

## Quick start

Build a spec, conform a raw frame into a submission-ready dataset, then write it to the format the FDA expects:

``` r
library(vport)

# A CDISC-shaped spec from the bundled pilot metadata
spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)

# Scaffold, coerce, order, sort, and stamp metadata in one call
adsl <- apply_spec(cdisc_adsl, spec, "ADSL")

# Write SAS XPORT v5
path <- tempfile(fileext = ".xpt")
write_xpt(adsl, path)

# Read it back -- labels, formats, types, and record count intact
get_meta(read_xpt(path))@dataset$records
#> [1] 60
```

## Any-to-any, lossless

One conformed dataset becomes a file in any supported format, and any file becomes any other, with the metadata carried straight through:

``` r
json <- tempfile(fileext = ".json")
write_json(adsl, json)

# Dataset-JSON on disk -> a submission XPT, no spec re-application
out <- tempfile(fileext = ".xpt")
write_xpt(read_json(json), out)
```

## Supported formats

    #>    format read write  extensions
    #> 1    json TRUE  TRUE        json
    #> 2 parquet TRUE  TRUE parquet, pq
    #> 3     rds TRUE  TRUE         rds
    #> 4     xpt TRUE  TRUE  xpt, xport

| Format | Reader | Writer | Use |
|----|----|----|----|
| SAS XPORT (XPT) | `read_xpt()` | `write_xpt()` | FDA / PMDA submission |
| CDISC Dataset-JSON | `read_json()` | `write_json()` | Modern CDISC interchange |
| Apache Parquet | `read_parquet()` | `write_parquet()` | Analytics, columnar store |
| RDS | `read_rds()` | `write_rds()` | Fast R-native storage |

The generic `read_dataset()` / `write_dataset()` dispatch on the file extension; every reader supports partial reads via `col_select` and `n_max`.

## Learn more

- `vignette("from-spec-to-submission")` — the spec → apply → check → write workflow.
- `vignette("one-dataset-every-format")` — lossless any-to-any conversion.

## License

MIT © Vignesh Thanikachalam
