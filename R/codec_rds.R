# codec_rds.R -- the rds codec.
#
# saveRDS/readRDS already round-trip live R attributes, so the metadata_json
# string set_meta() stamps survives natively. The codec still goes through the
# meta spine (encode stamps from the passed meta, decode recovers it) so an
# rds is self-describing in the same language-agnostic vocabulary as every
# other container. Writes are atomic (temp file + rename) so a crash mid-write
# never leaves a truncated dataset.

# encode contract: (x, meta, path, <codec args>, call) -> invisible(path).
# No `...`: an unknown argument forwarded by write_dataset() is a loud
# "unused argument" error, never silently swallowed.
#' @noRd
.encode_rds <- function(x, meta, path, call = rlang::caller_env()) {
  if (is_vport_meta(meta)) {
    x <- set_meta(x, meta)
  }
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".rds.tmp")
  saveRDS(x, tmp)
  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
  }
  invisible(path)
}

# decode contract: (path, <codec args>, call) -> list(data, meta).
#' @noRd
.decode_rds <- function(path, call = rlang::caller_env()) {
  obj <- readRDS(path)
  meta <- if (is.character(attr(obj, "metadata_json", exact = TRUE))) {
    get_meta(obj)
  } else {
    NULL
  }
  list(data = obj, meta = meta)
}

#' Write a dataset to rds
#'
#' Write a data frame to an R `.rds` file, preserving its `vport_meta`. A thin
#' wrapper over [write_dataset()] with `format = "rds"`; the rds carries the
#' metadata both as live R attributes and as the language-agnostic
#' `metadata_json` string, so [read_rds()] restores it exactly.
#'
#' @param x *The dataset to write.* `<data.frame>: required`.
#' @param path *Destination `.rds` path.* `<character(1)>: required`.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: write a conformed dataset to rds ----
#' #
#' # apply_spec() attaches the metadata; write_rds() carries it into the file.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
#' path <- tempfile(fileext = ".rds")
#' write_rds(adsl, path)
#'
#' # ---- Example 2: round-trip and confirm the metadata survived ----
#' #
#' # Reading it back yields an identical vport_meta.
#' back <- read_rds(path)
#' identical(get_meta(back)@columns, get_meta(adsl)@columns)
#'
#' @seealso [read_rds()] for the inverse; [write_dataset()] for the generic
#'   dispatcher.
#' @export
write_rds <- function(x, path) {
  write_dataset(x, path, format = "rds")
}

#' Read a dataset from rds
#'
#' Read an R `.rds` file written by [write_rds()] (or any rds carrying a
#' `metadata_json` attribute) back to a data frame with its `vport_meta`
#' restored. A thin wrapper over [read_dataset()] with `format = "rds"`.
#'
#' @param path *Source `.rds` path.* `<character(1)>: required`.
#'
#' @return *A `<data.frame>`* carrying `vport_meta` when the file recorded
#'   it. An rds holding anything other than a data frame is a
#'   `vport_error_codec`; use `readRDS()` for arbitrary objects.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: read a dataset written by write_rds() ----
#' #
#' # The restored frame carries the same metadata it was written with.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
#' path <- tempfile(fileext = ".rds")
#' write_rds(adsl, path)
#' back <- read_rds(path)
#' get_meta(back)@dataset$records
#'
#' # ---- Example 2: a plain rds still reads as a data frame ----
#' #
#' # An rds without vport metadata reads back as an ordinary frame.
#' bare <- tempfile(fileext = ".rds")
#' saveRDS(cdisc_dm, bare)
#' nrow(read_rds(bare))
#'
#' @seealso [write_rds()] for the inverse; [read_dataset()] for the generic
#'   dispatcher.
#' @export
read_rds <- function(path) {
  read_dataset(path, format = "rds")
}

.register_codec(
  "rds",
  encode = ".encode_rds",
  decode = ".decode_rds",
  extensions = "rds",
  mode = "rw"
)
