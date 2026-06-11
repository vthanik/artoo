# codec_rds.R — the rds codec.
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
.encode_rds <- function(
  x,
  meta,
  path,
  encoding = NULL,
  call = rlang::caller_env()
) {
  if (is_artoo_meta(meta)) {
    # rds is R-native and faithful: strings are saved as-is (Encoding marks
    # survive saveRDS), never transcoded. An explicit `encoding` only records
    # the source charset so a later write_xpt() can reproduce the bytes.
    if (!is.null(encoding)) {
      .resolve_charset(encoding, call)
      meta <- .meta_set_encoding(meta, encoding)
    }
    x <- set_meta(x, meta)
  }
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".rds.tmp")
  saveRDS(x, tmp)
  .move_into_place(tmp, path, call)
  invisible(path)
}

# decode contract: (path, <codec args>, call) -> list(data, meta).
#' @noRd
.decode_rds <- function(path, encoding = NULL, call = rlang::caller_env()) {
  obj <- readRDS(path)
  # Faithful by default (a plain readRDS round-trip). Transcode character
  # columns only when the caller asserts a foreign source charset.
  if (!is.null(encoding) && is.data.frame(obj)) {
    for (nm in names(obj)) {
      obj[[nm]] <- .recode_col(obj[[nm]], encoding)
    }
  }
  meta <- if (is.character(attr(obj, "metadata_json", exact = TRUE))) {
    get_meta(obj)
  } else {
    NULL
  }
  list(data = obj, meta = meta)
}

#' Write a dataset to rds
#'
#' Write a data frame to an R `.rds` file, preserving its `artoo_meta`. A thin
#' wrapper over [write_dataset()] with `format = "rds"`; the rds carries the
#' metadata both as live R attributes and as the language-agnostic
#' `metadata_json` string, so [read_rds()] restores it exactly.
#'
#' @param x *The dataset to write.* `<data.frame>: required`.
#' @param path *Destination `.rds` path.* `<character(1)>: required`.
#' @param encoding *Source charset to record.* `<character(1)> | NULL`. rds is
#'   R-native and faithful: strings are saved as-is, never transcoded.
#'   `encoding` only records the data's original charset in the `artoo_meta`,
#'   so a later [write_xpt()] can reproduce the source bytes. `NULL` (default)
#'   leaves the recorded encoding untouched.
#'
#'
#'   **Tip:** any SAS or IANA spelling listed by [artoo_encodings()] is
#'   accepted.
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'
#' @examples
#' spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: write a conformed dataset to rds ----
#' #
#' # apply_spec() attaches the metadata; write_rds() carries it into the file.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".rds")
#' write_rds(adsl, path)
#'
#' # ---- Example 2: round-trip and confirm the metadata survived ----
#' #
#' # Reading it back yields an identical artoo_meta.
#' back <- read_rds(path)
#' identical(get_meta(back)@columns, get_meta(adsl)@columns)
#'
#' @seealso [read_rds()] for the inverse; [write_dataset()] for the generic
#'   dispatcher.
#' @export
write_rds <- function(x, path, encoding = NULL) {
  write_dataset(x, path, format = "rds", encoding = encoding)
}

#' Read a dataset from rds
#'
#' Read an R `.rds` file written by [write_rds()] (or any rds carrying a
#' `metadata_json` attribute) back to a data frame with its `artoo_meta`
#' restored. A thin wrapper over [read_dataset()] with `format = "rds"`.
#'
#' @param path *Source `.rds` path.* `<character(1)>: required`.
#' @param encoding *Source charset of the string columns.* `<character(1)> |
#'   NULL`. `NULL` (default) returns the strings exactly as saved (faithful R
#'   round-trip). Pass a charset name only to transcode a foreign rds whose
#'   string columns hold that charset's bytes.
#'
#'   **Tip:** any SAS or IANA spelling listed by [artoo_encodings()] is
#'   accepted.
#' @inheritParams read_dataset
#'
#' @return *A `<data.frame>`* carrying `artoo_meta` when the file recorded
#'   it. An rds holding anything other than a data frame is a
#'   `artoo_error_codec`; use `readRDS()` for arbitrary objects.
#'
#' @examples
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists
#' )
#'
#' # ---- Example 1: read a dataset written by write_rds() ----
#' #
#' # The restored frame carries the same metadata it was written with.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".rds")
#' write_rds(adsl, path)
#' back <- read_rds(path)
#' get_meta(back)@dataset$records
#'
#' # ---- Example 2: a plain rds still reads as a data frame ----
#' #
#' # An rds without artoo metadata reads back as an ordinary frame.
#' bare <- tempfile(fileext = ".rds")
#' saveRDS(cdisc_dm, bare)
#' nrow(read_rds(bare))
#'
#' @seealso [write_rds()] for the inverse; [read_dataset()] for the generic
#'   dispatcher.
#' @export
read_rds <- function(path, col_select = NULL, n_max = Inf, encoding = NULL) {
  read_dataset(
    path,
    format = "rds",
    col_select = col_select,
    n_max = n_max,
    encoding = encoding
  )
}

.register_codec(
  "rds",
  encode = ".encode_rds",
  decode = ".decode_rds",
  extensions = "rds",
  mode = "rw"
)
