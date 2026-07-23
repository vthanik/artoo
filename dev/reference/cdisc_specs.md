# Bundled CDISC specifications (ADaM and SDTM)

Ready-made `artoo_spec` objects built from the official CDISC Define-XML
2.1 release examples: `adam_spec` (ADaMIG 1.1; datasets ADSL, ADAE) and
`sdtm_spec` (SDTMIG 3.1.2; datasets TS, DM, VS, SUPPDM). Every bundled
demo dataset conforms to its spec under
`apply_spec(conformance = "abort")` — the pairing is gated at build
time. The same specs ship as P21 workbooks in
`system.file("extdata", "adam-spec.xlsx", package = "artoo")` and
`"sdtm-spec.xlsx"`, written by
[`write_spec()`](https://vthanik.github.io/artoo/dev/reference/write_spec.md).

## Usage

``` r
adam_spec

sdtm_spec
```

## Format

A validated
[`artoo_spec()`](https://vthanik.github.io/artoo/dev/reference/artoo_spec.md)
object; inspect it with
[`spec_datasets()`](https://vthanik.github.io/artoo/dev/reference/spec_datasets.md),
[`spec_variables()`](https://vthanik.github.io/artoo/dev/reference/spec_variables.md),
and
[`spec_standard()`](https://vthanik.github.io/artoo/dev/reference/spec_standard.md).

## Source

The CDISC Define-XML 2.1 release example defines (ADaM + SDTM), pinned
by sha256 in `data-raw/bundle-spec.R`; data from the PHUSE Test Data
Factory.

## Details

**Demo adaptations** (each an ADR in `data-raw/bundle-spec.R`): the
sponsor-defined codelists (`CL.ARM`, `CL.ARMCD`, `CL.BMICAT`, and the
extensible NCI VS codelists) are marked `extended`; `VISITNUM` is typed
`float` (the pilot data has fractional visit numbers); VS declares the
SDTMIG timepoint variables `VSTPT`/`VSTPTNUM`, with `VSTPTNUM` in the VS
key.
