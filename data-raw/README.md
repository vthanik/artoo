# data-raw — build scripts and decision records

All bundled data and specs rebuild from **public sources only**:

- `bundle-demo.R` — demo datasets (`cdisc_adsl`, `cdisc_adae`, `cdisc_dm`,
  `cdisc_vs`, `cdisc_ts`, `cdisc_suppdm`, 60-row trims) plus the derived
  `cdisc_datasets` / `cdisc_variables` / `cdisc_codelists` tables, from the
  PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
- `bundle-spec.R` — `adam_spec` / `sdtm_spec` plus the shipped P21 workbooks
  (`inst/extdata/*.xlsx`), from the official CDISC Define-XML 2.1 release
  examples (mirrored on GitHub, sha256-pinned). Run AFTER `bundle-demo.R`;
  both build gates (xlsx round-trip; abort-mode conformance of every
  bundled dataset) must pass.
- `download-fixtures.R` — test fixtures (sha256-pinned).
- `make-p21-fixture.R` — the hand-authored P21 test workbook.
- `build-spec-rules.R` — the bundled `inst/spec_rules.json` catalog.

## ADRs (one line each)

- 2026-06-11 The PHUSE cdiscpilot01 `define.xml` files are Define-XML v1.0,
  which artoo refuses by design; the bundled specs come from the official
  CDISC Define-XML **2.1** release examples instead (same pilot study).
- 2026-06-11 SUPPVS is in the SDTM example define but phuse-scripts ships
  no `suppvs.xpt`; `sdtm_spec` is scoped to datasets with data.
- 2026-06-11 `CL.ARM`/`CL.ARMCD`/`CL.BMICAT`/`CL.VSTESTCD`/`CL.VSTEST`/
  `CL.VSRESU` are marked `extended = TRUE` (sponsor-defined arms/groupings;
  the NCI VS codelists are officially extensible).
- 2026-06-11 `VISITNUM` is retyped `float`: the pilot data carries
  fractional visit numbers the example define's `integer` would truncate.
- 2026-06-11 VS declares SDTMIG `VSTPT`/`VSTPTNUM` (omitted by the example
  define) and `VSTPTNUM` joins the VS key — without it the pilot VS key is
  not unique.
