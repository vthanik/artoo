# data.R -- documentation for the bundled CDISC-pilot demo data.
# Regenerate the .rda files with data-raw/bundle-demo.R.

#' CDISC demo specification tables (one standard per pair)
#'
#' The constructor-shaped metadata tables for the bundled demo data, split
#' by CDISC standard because a `artoo_spec` carries exactly one:
#' `cdisc_adam_datasets` + `cdisc_adam_variables` describe ADSL
#' (ADaMIG 1.1), and `cdisc_sdtm_datasets` + `cdisc_sdtm_variables`
#' describe DM (SDTMIG 3.1.2). Each variables table is *derived from the
#' data* (names, labels, inferred CDISC types, byte lengths) by
#' `data-raw/`. Pass one standard's pair to [artoo_spec()]; passing both
#' pairs together aborts with `artoo_error_spec` -- mixing standards in
#' one spec is the mistake the split exists to prevent.
#'
#' @format
#' Each `*_datasets` table is a data frame with one row per dataset:
#' \describe{
#'   \item{dataset}{Dataset name (`"ADSL"` or `"DM"`).}
#'   \item{label}{Dataset label.}
#'   \item{standard}{The CDISC standard, consumed into the spec's
#'     [spec_standard()].}
#' }
#' Each `*_variables` table is a data frame with one row per variable:
#' \describe{
#'   \item{dataset}{Owning dataset name.}
#'   \item{variable}{Variable name.}
#'   \item{label}{Variable label (from the data's `label` attribute).}
#'   \item{data_type}{CDISC `dataType` inferred from the column's class.}
#'   \item{length}{Storage length (max byte width for character, 8 for
#'     numeric).}
#'   \item{order}{Variable order within the dataset.}
#'   \item{codelist_id}{NCI codelist reference (`"C66731"` on `SEX`).}
#' }
#' @source Derived from the CDISC pilot `.xpt` files in the public PHUSE
#'   Test Data Factory (`phuse-org/phuse-scripts`) by
#'   `data-raw/bundle-demo.R`.
#' @keywords datasets
#' @name cdisc_spec
"cdisc_adam_datasets"

#' @rdname cdisc_spec
#' @format NULL
"cdisc_adam_variables"

#' @rdname cdisc_spec
#' @format NULL
"cdisc_sdtm_datasets"

#' @rdname cdisc_spec
#' @format NULL
"cdisc_sdtm_variables"

#' @rdname cdisc_spec
#' @format
#' `cdisc_codelists` is a data frame of controlled-terminology terms (the
#' real NCI codelist C66731 for `SEX`):
#' \describe{
#'   \item{codelist_id}{Codelist identifier (`"C66731"`).}
#'   \item{term}{Submission value (`"M"`, `"F"`, ...).}
#'   \item{decode}{Decoded value (`"Male"`, `"Female"`, ...).}
#'   \item{order}{Term order.}
#' }
"cdisc_codelists"

#' Demo subject-level analysis dataset (ADaM ADSL)
#'
#' A 60-subject sample of the CDISC pilot ADaM subject-level analysis dataset
#' (ADSL): one row per subject, with treatment, demographic, baseline, and
#' disposition variables (labels preserved as column attributes).
#'
#' @format A data frame with 60 rows and 48 variables (`STUDYID`, `USUBJID`,
#'   `TRT01P`, `AGE`, `SEX`, `RACE`, `SAFFL`, `TRTSDT`, ...).
#' @source First 60 subjects of the CDISC pilot `adam/cdisc/adsl.xpt` from
#'   the PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
#' @keywords datasets
"cdisc_adsl"

#' Demo demographics dataset (SDTM DM)
#'
#' A 60-subject sample of the CDISC pilot SDTM demographics domain (DM): one
#' row per subject, with the standard DM variables (labels preserved as
#' attributes).
#'
#' @format A data frame with 60 rows and 25 variables (`STUDYID`, `DOMAIN`,
#'   `USUBJID`, `AGE`, `SEX`, `RACE`, `ARM`, `COUNTRY`, ...).
#' @source First 60 subjects of the CDISC pilot `sdtm/TDF_SDTM_v1.0/dm.xpt`
#'   from the PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
#' @keywords datasets
"cdisc_dm"

#' Demo adverse events analysis dataset (ADaM ADAE)
#'
#' A 60-row sample of the CDISC pilot ADaM adverse events analysis dataset
#' (ADAE): one row per reported event, with treatment-emergent flags,
#' severity, and coding variables (labels preserved as attributes).
#'
#' @format A data frame with 60 rows (`STUDYID`, `USUBJID`, `AETERM`,
#'   `AESEV`, `TRTEMFL`, `ASTDT`, ...).
#' @source First 60 rows of the CDISC pilot `adam/cdisc/adae.xpt` from the
#'   PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
#' @keywords datasets
"cdisc_adae"

#' Demo vital signs dataset (SDTM VS)
#'
#' A 60-row sample of the CDISC pilot SDTM vital signs domain (VS): repeated
#' measurements per subject across visits, positions, and planned
#' timepoints.
#'
#' @format A data frame with 60 rows (`STUDYID`, `USUBJID`, `VSTESTCD`,
#'   `VSORRES`, `VISITNUM`, `VSPOS`, `VSTPTNUM`, ...).
#' @source First 60 rows of the CDISC pilot `sdtm/cdiscpilot01/vs.xpt` from
#'   the PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
#' @keywords datasets
"cdisc_vs"

#' Demo trial summary dataset (SDTM TS)
#'
#' The CDISC pilot SDTM trial summary domain (TS): one row per trial
#' characteristic (33 rows in the pilot), the study-design parameters a
#' submission carries.
#'
#' @format A data frame with 33 rows (`STUDYID`, `TSPARMCD`, `TSPARM`,
#'   `TSVAL`, ...).
#' @source The CDISC pilot `sdtm/cdiscpilot01/ts.xpt` from the PHUSE Test
#'   Data Factory (`phuse-org/phuse-scripts`).
#' @keywords datasets
"cdisc_ts"

#' Demo supplemental qualifiers dataset (SDTM SUPPDM)
#'
#' A 60-row sample of the CDISC pilot SDTM supplemental qualifiers for DM
#' (SUPPDM): the non-standard qualifier values that ride alongside the DM
#' domain.
#'
#' @format A data frame with 60 rows (`STUDYID`, `RDOMAIN`, `USUBJID`,
#'   `QNAM`, `QVAL`, ...).
#' @source First 60 rows of the CDISC pilot `sdtm/cdiscpilot01/suppdm.xpt`
#'   from the PHUSE Test Data Factory (`phuse-org/phuse-scripts`).
#' @keywords datasets
"cdisc_suppdm"

#' Bundled CDISC specifications (ADaM and SDTM)
#'
#' Ready-made `artoo_spec` objects built from the official CDISC Define-XML
#' 2.1 release examples: `adam_spec` (ADaMIG 1.1; datasets ADSL, ADAE) and
#' `sdtm_spec` (SDTMIG 3.1.2; datasets TS, DM, VS, SUPPDM). Every bundled
#' demo dataset conforms to its spec under
#' `apply_spec(conformance = "abort")` -- the pairing is gated at build
#' time. The same specs ship as P21 workbooks in
#' `system.file("extdata", "adam-spec.xlsx", package = "artoo")` and
#' `"sdtm-spec.xlsx"`, written by [write_spec()].
#'
#' @details
#' **Demo adaptations** (each an ADR in `data-raw/bundle-spec.R`): the
#' sponsor-defined codelists (`CL.ARM`, `CL.ARMCD`, `CL.BMICAT`, and the
#' extensible NCI VS codelists) are marked `extended`; `VISITNUM` is typed
#' `float` (the pilot data has fractional visit numbers); VS declares the
#' SDTMIG timepoint variables `VSTPT`/`VSTPTNUM`, with `VSTPTNUM` in the VS
#' key.
#'
#' @format A validated [artoo_spec()] object; inspect it with
#'   [spec_datasets()], [spec_variables()], and [spec_standard()].
#' @source The CDISC Define-XML 2.1 release example defines (ADaM + SDTM),
#'   pinned by sha256 in `data-raw/bundle-spec.R`; data from the PHUSE Test
#'   Data Factory.
#' @keywords datasets
#' @name cdisc_specs
"adam_spec"

#' @rdname cdisc_specs
#' @format NULL
"sdtm_spec"
