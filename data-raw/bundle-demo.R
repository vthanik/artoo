# data-raw/bundle-demo.R
# Build artoo's CDISC demo data reproducibly from the PUBLIC PHUSE Test
# Data Factory (phuse-org/phuse-scripts) -- the canonical open CDISC pilot
# datasets. The .xpt sources are read at BUILD TIME with haven (a dev-only
# tool; haven is NOT a package dependency). The shipped .rda files are
# self-contained base-R data frames.
#
# Dogfood: the .xpt sources are read with artoo's own read_xpt() -- artoo eats
# its own cooking, so the demo data exercises the reader it ships.
#
# Run from the package root:  Rscript data-raw/bundle-demo.R
#
# Produces (data/): cdisc_adsl, cdisc_adae, cdisc_dm, cdisc_vs, cdisc_ts,
# cdisc_suppdm, cdisc_adam_datasets, cdisc_adam_variables,
# cdisc_sdtm_datasets, cdisc_sdtm_variables, cdisc_codelists. Each raw
# dataset is trimmed to its first 60 rows (deterministic). Companion script
# bundle-spec.R builds the matching adam_spec / sdtm_spec objects and gates
# every pairing with apply_spec(conformance = "abort").

devtools::load_all(quiet = TRUE)

phuse <- "https://raw.githubusercontent.com/phuse-org/phuse-scripts/master/data"
read_phuse_xpt <- function(rel) {
  tf <- tempfile(fileext = ".xpt")
  on.exit(unlink(tf), add = TRUE)
  utils::download.file(file.path(phuse, rel), tf, quiet = TRUE, mode = "wb")
  read_xpt(tf)
}

# Reduce a artoo-read frame to plain base R for shipping: drop the metadata_json
# frame sidecar and the projected SAS format attr, keep each column's variable
# label. artoo already returns a base data.frame with native temporal classes,
# so there is no haven dependency to strip.
unhaven <- function(df) {
  attr(df, "metadata_json") <- NULL
  for (nm in names(df)) {
    attr(df[[nm]], "format.sas") <- NULL
  }
  as.data.frame(df, stringsAsFactors = FALSE)
}

# Keep the first `n` rows WITHOUT losing per-column `label` attributes
# (base `[` / head() drop them, so re-attach explicitly).
trim_rows <- function(df, n) {
  labs <- lapply(df, function(x) attr(x, "label", exact = TRUE))
  out <- df[seq_len(min(n, nrow(df))), , drop = FALSE]
  for (nm in names(out)) {
    attr(out[[nm]], "label") <- labs[[nm]]
  }
  rownames(out) <- NULL
  out
}

# A column's CDISC dataType, inferred from its R class.
infer_data_type <- function(x) {
  if (inherits(x, "Date")) {
    "date"
  } else if (inherits(x, "POSIXct")) {
    "datetime"
  } else if (is.factor(x) || is.character(x)) {
    "string"
  } else if (is.logical(x)) {
    "boolean"
  } else if (is.integer(x)) {
    "integer"
  } else if (is.numeric(x)) {
    "float"
  } else {
    "string"
  }
}

infer_length <- function(x) {
  if (is.character(x) || is.factor(x)) {
    n <- suppressWarnings(max(nchar(as.character(x)), na.rm = TRUE))
    if (!is.finite(n) || n < 1L) 1L else as.integer(n)
  } else {
    8L
  }
}

derive_variables <- function(df, dataset) {
  data.frame(
    dataset = dataset,
    variable = names(df),
    label = vapply(
      df,
      function(x) attr(x, "label", exact = TRUE) %||% "",
      character(1)
    ),
    data_type = vapply(df, infer_data_type, character(1)),
    length = vapply(df, infer_length, integer(1)),
    order = seq_along(df),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

# ---- Raw datasets (first 60 subjects, deterministic) ---------------------

cdisc_adsl <- trim_rows(unhaven(read_phuse_xpt("adam/cdisc/adsl.xpt")), 60L)
cdisc_adae <- trim_rows(unhaven(read_phuse_xpt("adam/cdisc/adae.xpt")), 60L)
cdisc_dm <- trim_rows(unhaven(read_phuse_xpt("sdtm/TDF_SDTM_v1.0/dm.xpt")), 60L)
cdisc_vs <- trim_rows(unhaven(read_phuse_xpt("sdtm/cdiscpilot01/vs.xpt")), 60L)
cdisc_ts <- trim_rows(unhaven(read_phuse_xpt("sdtm/cdiscpilot01/ts.xpt")), 60L)
cdisc_suppdm <- trim_rows(
  unhaven(read_phuse_xpt("sdtm/cdiscpilot01/suppdm.xpt")),
  60L
)

# ---- Derived spec tables (ONE standard per pair -- never mixed) -----------
# A artoo_spec carries exactly one CDISC standard, so the demo constructor
# tables are split by standard: the ADaM pair (ADSL) and the SDTM pair
# (DM). The shared NCI codelist table is controlled terminology, which is
# standard-agnostic.

cdisc_adam_datasets <- data.frame(
  dataset = "ADSL",
  label = "Subject-Level Analysis Dataset",
  standard = "ADaMIG 1.1",
  stringsAsFactors = FALSE
)

cdisc_adam_variables <- derive_variables(cdisc_adsl, "ADSL")
cdisc_adam_variables$codelist_id <- NA_character_
cdisc_adam_variables$codelist_id[cdisc_adam_variables$variable == "SEX"] <-
  "C66731"

cdisc_sdtm_datasets <- data.frame(
  dataset = "DM",
  label = "Demographics",
  standard = "SDTMIG 3.1.2",
  stringsAsFactors = FALSE
)

cdisc_sdtm_variables <- derive_variables(cdisc_dm, "DM")
cdisc_sdtm_variables$codelist_id <- NA_character_
cdisc_sdtm_variables$codelist_id[cdisc_sdtm_variables$variable == "SEX"] <-
  "C66731"

# The real NCI controlled-terminology codelist C66731 (reference
# terminology, not fabricated data), shared by both standards' SEX.
cdisc_codelists <- data.frame(
  codelist_id = "C66731",
  term = c("F", "M", "U", "UNDIFFERENTIATED"),
  decode = c("Female", "Male", "Unknown", "Undifferentiated"),
  order = 1:4,
  stringsAsFactors = FALSE
)

# BUILD GATES: each pair builds a validated single-standard spec, and
# mixing the two standards' tables ABORTS (the invariant the split
# exists to teach).
adam_demo <- artoo_spec(
  cdisc_adam_datasets,
  cdisc_adam_variables,
  codelists = cdisc_codelists
)
sdtm_demo <- artoo_spec(
  cdisc_sdtm_datasets,
  cdisc_sdtm_variables,
  codelists = cdisc_codelists
)
stopifnot(
  identical(spec_standard(adam_demo), "ADaMIG 1.1"),
  identical(spec_standard(sdtm_demo), "SDTMIG 3.1.2"),
  inherits(
    tryCatch(
      artoo_spec(
        rbind(cdisc_adam_datasets, cdisc_sdtm_datasets),
        rbind(cdisc_adam_variables, cdisc_sdtm_variables),
        codelists = cdisc_codelists
      ),
      error = function(e) e
    ),
    "artoo_error_spec"
  )
)

usethis::use_data(
  cdisc_adsl,
  cdisc_adae,
  cdisc_dm,
  cdisc_vs,
  cdisc_ts,
  cdisc_suppdm,
  cdisc_adam_datasets,
  cdisc_adam_variables,
  cdisc_sdtm_datasets,
  cdisc_sdtm_variables,
  cdisc_codelists,
  overwrite = TRUE
)
