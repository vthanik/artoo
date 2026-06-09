# data-raw/bundle-demo.R
# Build vport's CDISC demo data reproducibly from the PUBLIC PHUSE Test
# Data Factory (phuse-org/phuse-scripts) -- the canonical open CDISC pilot
# datasets. The .xpt sources are read at BUILD TIME with haven (a dev-only
# tool; haven is NOT a package dependency). The shipped .rda files are
# self-contained base-R data frames.
#
# NOTE (dogfooding TODO): once vport's own read_xpt() lands (Phase 3),
# switch the reader below from haven::read_xpt() to vport::read_xpt().
#
# Run from the package root:  Rscript data-raw/bundle-demo.R
#
# Produces (data/): cdisc_adsl, cdisc_dm, cdisc_datasets, cdisc_variables,
# cdisc_codelists.

devtools::load_all(quiet = TRUE)

phuse <- "https://raw.githubusercontent.com/phuse-org/phuse-scripts/master/data"
read_phuse_xpt <- function(rel) {
  tf <- tempfile(fileext = ".xpt")
  on.exit(unlink(tf), add = TRUE)
  utils::download.file(file.path(phuse, rel), tf, quiet = TRUE, mode = "wb")
  haven::read_xpt(tf)
}

# Strip haven classes to base R while preserving each column's variable
# label, so the bundled data carries no haven dependency.
unhaven <- function(df) {
  df <- haven::zap_formats(haven::zap_labels(df))
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
cdisc_dm <- trim_rows(unhaven(read_phuse_xpt("sdtm/TDF_SDTM_v1.0/dm.xpt")), 60L)

# ---- Derived spec tables -------------------------------------------------

cdisc_datasets <- data.frame(
  dataset = c("ADSL", "DM"),
  label = c("Subject-Level Analysis Dataset", "Demographics"),
  stringsAsFactors = FALSE
)

cdisc_variables <- rbind(
  derive_variables(cdisc_adsl, "ADSL"),
  derive_variables(cdisc_dm, "DM")
)

# Wire the SEX variables to the real NCI controlled-terminology codelist
# C66731 (reference terminology, not fabricated data).
cdisc_variables$codelist_id <- NA_character_
cdisc_variables$codelist_id[cdisc_variables$variable == "SEX"] <- "C66731"

cdisc_codelists <- data.frame(
  codelist_id = "C66731",
  term = c("F", "M", "U", "UNDIFFERENTIATED"),
  decode = c("Female", "Male", "Unknown", "Undifferentiated"),
  order = 1:4,
  stringsAsFactors = FALSE
)

stopifnot(is_vport_spec(
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
))

usethis::use_data(
  cdisc_adsl,
  cdisc_dm,
  cdisc_datasets,
  cdisc_variables,
  cdisc_codelists,
  overwrite = TRUE
)
