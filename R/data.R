# data.R -- documentation for the bundled CDISC-pilot demo data.
# Regenerate the .rda files with data-raw/bundle-demo.R.

#' CDISC demo specification tables
#'
#' The dataset-level (`cdisc_datasets`) and variable-level (`cdisc_variables`)
#' metadata for the bundled `cdisc_adsl` and `cdisc_dm` datasets, in the shape
#' [vport_spec()] expects. The variable table is *derived from the data*
#' (names, labels, inferred CDISC types, byte lengths) by `data-raw/`. Pass
#' both to [vport_spec()] to build a specification for examples and tests.
#'
#' @format
#' `cdisc_datasets` is a data frame with one row per dataset:
#' \describe{
#'   \item{dataset}{Dataset name (`"ADSL"`, `"DM"`).}
#'   \item{label}{Dataset label.}
#' }
#' `cdisc_variables` is a data frame with one row per variable:
#' \describe{
#'   \item{dataset}{Owning dataset name.}
#'   \item{variable}{Variable name.}
#'   \item{label}{Variable label (from the data's `label` attribute).}
#'   \item{data_type}{CDISC `dataType` inferred from the column's class.}
#'   \item{length}{Storage length (max byte width for character, 8 for
#'     numeric).}
#'   \item{order}{Variable order within the dataset.}
#' }
#' @source Derived from the CDISC pilot `.xpt` files in the public PHUSE
#'   Test Data Factory (`phuse-org/phuse-scripts`) by
#'   `data-raw/bundle-demo.R`.
#' @keywords datasets
#' @name cdisc_spec
"cdisc_datasets"

#' @rdname cdisc_spec
#' @format NULL
"cdisc_variables"

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
