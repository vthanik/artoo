# io.R -- the format-agnostic read/write dispatchers.
#
# write_dataset()/read_dataset() select a codec by explicit `format=` or file
# extension, then delegate to its encode/decode. write_dataset() pulls the
# vport_meta off the frame once (get_meta) and hands it to the codec;
# read_dataset() re-attaches whatever meta the codec recovers. Codecs never
# touch raw attributes -- the meta spine is the only metadata path.

# The vport_meta to write with: the frame's own metadata_json when present,
# else one derived from its column attributes + R classes (so a bare or
# haven-shaped frame still writes with labels/formats/types). NULL only for a
# 0-column frame.
#' @noRd
.maybe_meta <- function(x) {
  if (is.character(attr(x, "metadata_json", exact = TRUE))) {
    get_meta(x)
  } else {
    .meta_from_frame(x)
  }
}

# Resolve a path + optional format to a registered format name. Explicit
# `format` wins (validated); otherwise the file extension decides. An
# unresolvable path is a vport_error_input (the user can pass `format`).
#' @noRd
.resolve_format <- function(path, format, call = rlang::caller_env()) {
  if (!is.null(format)) {
    .resolve_codec(format, call)
    return(format)
  }
  known <- .registered_formats()
  codec <- tryCatch(
    .codec_for_ext(tools::file_ext(path), call),
    vport_error_codec = function(e) {
      cli::cli_abort(
        c(
          "Cannot determine the dataset format from {.path {path}}.",
          "i" = "Pass {.arg format} explicitly, one of {.val {known}}."
        ),
        class = "vport_error_input",
        call = call
      )
    }
  )
  codec$format
}

#' Write a dataset to any supported format
#'
#' Serialize a data frame to a clinical file format, preserving its
#' `vport_meta` losslessly. The codec is chosen from the file extension (or an
#' explicit `format`), so one call covers xpt, Dataset-JSON, Parquet, and rds.
#' This is the emit end of the vport workflow; the per-format wrappers like
#' [write_rds()] are thin sugar over it.
#'
#' @param x *The dataset to write.* `<data.frame>: required`. Typically the
#'   output of [apply_spec()], carrying `vport_meta`.
#' @param path *Destination file path.* `<character(1)>: required`. Its
#'   extension selects the codec unless `format` is given.
#' @param format *Force a codec instead of inferring from the extension.*
#'   `<character(1)> | NULL`. One of the registered formats (see
#'   [check_formats()]).
#' @param ... *Codec-specific arguments* passed through to the encoder (see
#'   the per-format wrappers, e.g. [write_xpt()], for what each codec
#'   accepts). An argument the codec does not know is an error, never
#'   silently ignored.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'   Called for the side effect of writing `path`.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: write a conformed dataset, inferring rds from the path ----
#' #
#' # apply_spec() attaches the metadata; write_dataset() carries it into the
#' # file so a later read is lossless.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", check = "off")
#' path <- tempfile(fileext = ".rds")
#' write_dataset(adsl, path)
#'
#' # ---- Example 2: force the format for an unconventional extension ----
#' #
#' # When the extension does not name the format, pass it explicitly.
#' alt <- tempfile(fileext = ".data")
#' write_dataset(adsl, alt, format = "rds")
#'
#' @seealso [read_dataset()] for the inverse; [write_rds()] for the
#'   per-format wrapper; [check_formats()] for what is available.
#' @export
write_dataset <- function(x, path, format = NULL, ...) {
  call <- rlang::caller_env()
  if (!is.data.frame(x)) {
    cli::cli_abort(
      c(
        "{.arg x} must be a data frame.",
        "x" = "You supplied {.obj_type_friendly {x}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  .check_path(path, call)
  fmt <- .resolve_format(path, format, call)
  codec <- .resolve_codec(fmt, call)
  if (codec$mode == "r") {
    cli::cli_abort(
      c(
        "Format {.val {fmt}} is read-only.",
        "i" = "It cannot be written."
      ),
      class = "vport_error_codec",
      call = call
    )
  }
  encode <- .codec_fn(codec$encode)
  # `call` is passed explicitly so codec errors attribute to the function the
  # user actually called (write_xpt, not write_dataset), and so a user-
  # supplied `call =` in `...` is a loud duplicate-argument error.
  encode(x, .maybe_meta(x), path, ..., call = call)
  invisible(x)
}

#' Read a dataset from any supported format
#'
#' Read a clinical file back to a data frame, restoring its `vport_meta`. The
#' codec is chosen from the file extension (or an explicit `format`), and the
#' metadata the file carries is re-attached, so a value written by
#' [write_dataset()] round-trips losslessly. This is the ingest end of the
#' I/O layer; the per-format wrappers like [read_rds()] call it.
#'
#' @param path *Source file path.* `<character(1)>: required`. Its extension
#'   selects the codec unless `format` is given.
#' @param format *Force a codec instead of inferring from the extension.*
#'   `<character(1)> | NULL`. One of the registered formats (see
#'   [check_formats()]).
#' @param ... *Codec-specific arguments* passed through to the decoder (see
#'   the per-format wrappers, e.g. [read_xpt()]). An argument the codec does
#'   not know is an error, never silently ignored.
#'
#' @return *A `<data.frame>`* carrying `vport_meta` when the file recorded it
#'   (read it with [get_meta()]). A file whose payload is not a data frame is
#'   a `vport_error_codec`.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: round-trip a dataset through rds ----
#' #
#' # Write a conformed dataset, then read it back; the metadata survives.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", check = "off")
#' path <- tempfile(fileext = ".rds")
#' write_dataset(adsl, path)
#' back <- read_dataset(path)
#' identical(get_meta(back)@columns, get_meta(adsl)@columns)
#'
#' # ---- Example 2: the metadata names the dataset and row count ----
#' #
#' # The restored vport_meta exposes the dataset-level attributes.
#' get_meta(back)@dataset$records
#'
#' @seealso [write_dataset()] for the inverse; [read_rds()] for the
#'   per-format wrapper.
#' @export
read_dataset <- function(path, format = NULL, ...) {
  call <- rlang::caller_env()
  .check_path(path, call)
  if (!file.exists(path)) {
    cli::cli_abort(
      c(
        "{.arg path} does not exist.",
        "x" = "No file at {.path {path}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  fmt <- .resolve_format(path, format, call)
  codec <- .resolve_codec(fmt, call)
  decode <- .codec_fn(codec$decode)
  res <- decode(path, ..., call = call)
  # Self-describing containers (rds) can hold anything; the read_* contract
  # promises a data frame, so refuse other payloads loudly.
  if (!is.data.frame(res$data)) {
    msg <- c(
      "{.path {path}} does not contain a dataset.",
      "x" = "The {.val {fmt}} payload is {.obj_type_friendly {res$data}}, not a data frame."
    )
    if (identical(fmt, "rds")) {
      msg <- c(msg, "i" = "Use {.fn readRDS} for arbitrary R objects.")
    }
    cli::cli_abort(msg, class = "vport_error_codec", call = call)
  }
  if (is_vport_meta(res$meta)) {
    set_meta(res$data, res$meta)
  } else {
    res$data
  }
}

#' Report which formats are available
#'
#' List every registered codec and whether it can read and write in this
#' session. The pure-R formats (xpt, json, rds) are always available;
#' optional-engine formats (parquet) report `FALSE` until their package is
#' installed. Purely informational, modelled on the diagnostic helpers in the
#' wider ecosystem; it never aborts.
#'
#' @return *A `<data.frame>`* with one row per format and columns `format`,
#'   `read`, `write` (logical), and `extensions`.
#'
#' @examples
#' # ---- Example 1: see what this session can read and write ----
#' #
#' # rds is always available; the table shows the extensions each codec claims.
#' check_formats()
#'
#' @seealso [read_dataset()] and [write_dataset()] which use the registry.
#' @export
check_formats <- function() {
  fmts <- .registered_formats()
  data.frame(
    format = fmts,
    read = vapply(
      fmts,
      function(f) .vport_codecs[[f]]$mode %in% c("rw", "r"),
      logical(1)
    ),
    write = vapply(
      fmts,
      function(f) .vport_codecs[[f]]$mode == "rw",
      logical(1)
    ),
    extensions = vapply(
      fmts,
      function(f) paste(.vport_codecs[[f]]$extensions, collapse = ", "),
      character(1)
    ),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
