# data-raw/bundle-spec.R
# Build artoo's bundled specification objects (adam_spec, sdtm_spec) and the
# shipped P21 workbooks (inst/extdata/adam-spec.xlsx, sdtm-spec.xlsx) from
# PUBLIC sources only: the official CDISC Define-XML 2.1 release examples
# (ADaM + SDTM), mirrored on GitHub and pinned by sha256. The bundled demo
# datasets (bundle-demo.R) come from the PHUSE Test Data Factory — the same
# CDISC pilot study these defines describe.
#
# Run from the package root AFTER bundle-demo.R:
#   Rscript data-raw/bundle-spec.R
#
# Produces: data/adam_spec.rda, data/sdtm_spec.rda,
#           inst/extdata/adam-spec.xlsx, inst/extdata/sdtm-spec.xlsx.
#
# Decisions (ADRs, one line each — see data-raw/README.md):
# - SUPPVS is in the SDTM example define but phuse-scripts ships no
#   suppvs.xpt; the bundled sdtm_spec is scoped to datasets with data.
# - CL.ARM / CL.ARMCD / CL.BMICAT / CL.VSTESTCD / CL.VSTEST / CL.VSRESU are
#   marked extended = TRUE: arms and BMI groupings are sponsor-defined, and
#   the official NCI VS codelists are extensible (the example define's
#   subsets simply omit terms like TEMP that the pilot data carries).
# - VISITNUM is retyped float: the pilot data has fractional visit numbers
#   (1.3, ...); the example define's integer typing would truncate them,
#   which artoo refuses to do.
# - VS gains the SDTMIG timepoint variables VSTPT / VSTPTNUM (the example
#   define omits them) and VSTPTNUM joins the VS key: the pilot data records
#   repeated measurements per position that only the timepoint
#   disambiguates — without it the VS key is not unique.

devtools::load_all(quiet = TRUE)

mirror <- paste0(
  "https://raw.githubusercontent.com/rubentalstra/Trial-Submission-Studio/",
  "master/resources/Define-XML_2.1/examples/"
)
sources <- list(
  adam = list(
    url = paste0(mirror, "Define-XML-2-1-ADaM/adam/defineV21-ADaM.xml"),
    sha256 = "115a55575bc6709562290415a22bfb6a3333c38b67bf702561e1adbc30bd157d",
    datasets = c("ADSL", "ADAE")
  ),
  sdtm = list(
    url = paste0(mirror, "DefineXML-2-1-SDTM/defineV21-SDTM.xml"),
    sha256 = "24c97a570d1f905435e815ff7e3199b2e17a5e5d6c58b4fabdf1439bf10d5d21",
    datasets = c("TS", "DM", "VS", "SUPPDM")
  )
)

fetch_define <- function(src) {
  tf <- tempfile(fileext = ".xml")
  utils::download.file(src$url, tf, quiet = TRUE, mode = "wb")
  got <- digest::digest(file = tf, algo = "sha256")
  if (!identical(got, src$sha256)) {
    stop("define checksum mismatch for ", src$url, ": ", got)
  }
  read_spec(tf, datasets = src$datasets)
}

# Rebuild a spec with demo-data adaptations: extensible codelists and
# float retyping (each justified in the header ADRs). Construction re-runs
# the full validation, so the result is still a checked artoo_spec.
adapt <- function(spec, extend = character(0), float_vars = character(0)) {
  v <- spec@variables
  cl <- spec@codelists
  v$data_type[v$variable %in% float_vars] <- "float"
  cl$extended[cl$codelist_id %in% extend] <- TRUE
  artoo_spec(
    spec@datasets,
    v,
    codelists = cl,
    study = spec@study,
    values = spec@values,
    methods = spec@methods,
    comments = spec@comments,
    documents = spec@documents,
    standard = spec@standard
  )
}

# Declare the SDTMIG VS timepoint variables and add VSTPTNUM to the VS key
# (see the header ADR). Both the keys string and the per-variable
# key_sequence are extended coherently, so validate_spec()'s
# key-consistency rules stay green.
add_vs_timepoints <- function(spec) {
  v <- spec@variables
  ds <- spec@datasets
  vs <- !is.na(v$dataset) & v$dataset == "VS"
  next_ord <- max(v$order[vs], na.rm = TRUE) + 1:2
  next_key <- max(v$key_sequence[vs], na.rm = TRUE) + 1L
  extra <- v[0, , drop = FALSE][1:2, ]
  extra$dataset <- "VS"
  extra$variable <- c("VSTPT", "VSTPTNUM")
  extra$label <- c("Planned Time Point Name", "Planned Time Point Number")
  extra$data_type <- c("string", "float")
  extra$order <- next_ord
  extra$key_sequence <- c(NA_integer_, next_key)
  v <- rbind(v, extra)
  ds$keys[ds$dataset == "VS"] <- paste(
    ds$keys[ds$dataset == "VS"],
    "VSTPTNUM"
  )
  artoo_spec(
    ds,
    v,
    codelists = spec@codelists,
    study = spec@study,
    values = spec@values,
    methods = spec@methods,
    comments = spec@comments,
    documents = spec@documents,
    standard = spec@standard
  )
}

adam_spec <- adapt(fetch_define(sources$adam), extend = "CL.BMICAT")
sdtm_spec <- add_vs_timepoints(adapt(
  fetch_define(sources$sdtm),
  extend = c(
    "CL.ARM",
    "CL.ARMCD",
    "CL.VSTESTCD",
    "CL.VSTEST",
    "CL.VSRESU"
  ),
  float_vars = "VISITNUM"
))

stopifnot(
  identical(spec_standard(adam_spec), "ADaMIG 1.1"),
  identical(spec_standard(sdtm_spec), "SDTMIG 3.1.2")
)

# ---- shipped P21 workbooks (the Define-XML -> P21 bridge, exercised) ------

dir.create("inst/extdata", recursive = TRUE, showWarnings = FALSE)
write_spec(adam_spec, "inst/extdata/adam-spec.xlsx")
write_spec(sdtm_spec, "inst/extdata/sdtm-spec.xlsx")

# ---- BUILD GATE 1: the workbook round-trips its representable surface ----

for (nm in c("adam", "sdtm")) {
  spec <- get(paste0(nm, "_spec"))
  back <- read_spec(sprintf("inst/extdata/%s-spec.xlsx", nm))
  stopifnot(
    identical(spec_standard(back), spec_standard(spec)),
    setequal(spec_datasets(back), spec_datasets(spec)),
    identical(back@variables$variable, spec@variables$variable),
    identical(back@variables$data_type, spec@variables$data_type)
  )
}

# ---- BUILD GATE 2: every bundled dataset conforms in abort mode ----------
# (Requires the demo .rda files from bundle-demo.R in data/.)

pairs <- list(
  list(data = "cdisc_adsl", spec = adam_spec, ds = "ADSL"),
  list(data = "cdisc_adae", spec = adam_spec, ds = "ADAE"),
  list(data = "cdisc_dm", spec = sdtm_spec, ds = "DM"),
  list(data = "cdisc_vs", spec = sdtm_spec, ds = "VS"),
  list(data = "cdisc_ts", spec = sdtm_spec, ds = "TS"),
  list(data = "cdisc_suppdm", spec = sdtm_spec, ds = "SUPPDM")
)
for (p in pairs) {
  e <- new.env()
  load(file.path("data", paste0(p$data, ".rda")), envir = e)
  out <- suppressMessages(suppressWarnings(
    apply_spec(get(p$data, envir = e), p$spec, p$ds, conformance = "abort")
  ))
  message(sprintf("gate OK: %-14s -> %s (%d rows)", p$data, p$ds, nrow(out)))
}

usethis::use_data(adam_spec, sdtm_spec, overwrite = TRUE)
