# io.R -- the format-agnostic read/write dispatchers.
#
# write_dataset()/read_dataset() select a codec by explicit `format=` or file
# extension, then delegate to its encode/decode. write_dataset() pulls the
# artoo_meta off the frame once (get_meta) and hands it to the codec;
# read_dataset() re-attaches whatever meta the codec recovers. Codecs never
# touch raw attributes -- the meta spine is the only metadata path.

# The artoo_meta to write with: the frame's own metadata_json when present,
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
# unresolvable path is a artoo_error_input (the user can pass `format`).
#' @noRd
.resolve_format <- function(path, format, call = rlang::caller_env()) {
  if (!is.null(format)) {
    .resolve_codec(format, call)
    return(format)
  }
  known <- .registered_formats()
  # A .gz suffix is transparent compression, not a format: peel it and
  # resolve the inner extension (dm.json.gz -> json). Only the text-streaming
  # codecs gzip; a binary container behind .gz is refused loudly.
  ext <- tools::file_ext(path)
  gz <- identical(tolower(ext), "gz")
  if (gz) {
    ext <- tools::file_ext(sub("\\.gz$", "", path, ignore.case = TRUE))
  }
  codec <- tryCatch(
    .codec_for_ext(ext, call),
    artoo_error_codec = function(e) {
      .artoo_abort(
        c(
          "Cannot determine the dataset format from {.path {path}}.",
          "i" = "Pass {.arg format} explicitly, one of {.val {known}}."
        ),
        kind = "input",
        call = call
      )
    }
  )
  if (gz && !codec$format %in% c("json", "ndjson")) {
    .artoo_abort(
      c(
        "gz compression is not supported for the {.val {codec$format}} format.",
        "i" = "Only {.val json} and {.val ndjson} stream through gzip."
      ),
      kind = "input",
      call = call
    )
  }
  codec$format
}

#' Write a dataset to any supported format
#'
#' Serialize a data frame to a clinical file format, preserving its
#' `artoo_meta` losslessly. The codec is chosen from the file extension (or an
#' explicit `format`), so one call covers xpt, Dataset-JSON, Parquet, and rds.
#' This is the emit end of the artoo workflow; the per-format wrappers like
#' [write_rds()] are thin sugar over it.
#'
#' @param x *The dataset to write.* `<data.frame>: required`. Typically the
#'   output of [apply_spec()], carrying `artoo_meta`.
#' @param path *Destination file path.* `<character(1)>: required`. Its
#'   extension selects the codec unless `format` is given.
#' @param format *Force a codec instead of inferring from the extension.*
#'   `<character(1)> | NULL`. One of the registered formats (see
#'   [artoo_formats()]).
#' @param ... *Codec-specific arguments* passed through to the encoder (see
#'   the per-format wrappers, e.g. [write_xpt()], for what each codec
#'   accepts). An argument the codec does not know is an error, never
#'   silently ignored.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'   Called for the side effect of writing `path`.
#'
#' @examples
#' spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: write a conformed dataset, inferring rds from the path ----
#' #
#' # apply_spec() attaches the metadata; write_dataset() carries it into the
#' # file so a later read is lossless.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
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
#'   per-format wrapper; [artoo_formats()] for what is available.
#' @export
write_dataset <- function(x, path, format = NULL, ...) {
  call <- rlang::caller_env()
  if (!is.data.frame(x)) {
    .artoo_abort(
      c(
        "{.arg x} must be a data frame.",
        "x" = "You supplied {.obj_type_friendly {x}}."
      ),
      kind = "input",
      call = call
    )
  }
  .check_path(path, call)
  fmt <- .resolve_format(path, format, call)
  codec <- .resolve_codec(fmt, call)
  if (codec$mode == "r") {
    .artoo_abort(
      c(
        "Format {.val {fmt}} is read-only.",
        "i" = "It cannot be written."
      ),
      kind = "codec",
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
#' Read a clinical file back to a data frame, restoring its `artoo_meta`. The
#' codec is chosen from the file extension (or an explicit `format`), and the
#' metadata the file carries is re-attached, so a value written by
#' [write_dataset()] round-trips losslessly. This is the ingest end of the
#' I/O layer; the per-format wrappers like [read_rds()] call it.
#'
#' @param path *Source file path.* `<character(1)>: required`. Its extension
#'   selects the codec unless `format` is given.
#' @param format *Force a codec instead of inferring from the extension.*
#'   `<character(1)> | NULL`. One of the registered formats (see
#'   [artoo_formats()]).
#' @param col_select *Variables to read.* `<character> | NULL`. `NULL`
#'   (default) reads every column; otherwise a vector of variable names.
#'   Columns return in file order (not the requested order) and the
#'   `artoo_meta` is filtered to match. Works on every format: parquet narrows
#'   columns natively, the rest filter after decode.
#'
#'   **Note:** an unknown name is a `artoo_error_input`, never a silent drop.
#' @param n_max *Maximum records to read.* `<numeric(1)>: default Inf`. Caps
#'   the row count; the returned `artoo_meta` reports the rows actually read.
#'   xpt v8 bounds the disk read; the other formats cap after decode.
#' @param ... *Codec-specific arguments* passed through to the decoder (see
#'   the per-format wrappers, e.g. [read_xpt()]). An argument the codec does
#'   not know is an error, never silently ignored.
#'
#' @return *A `<data.frame>`* carrying `artoo_meta` when the file recorded it
#'   (read it with [get_meta()]). A file whose payload is not a data frame is
#'   a `artoo_error_codec`.
#'
#' @examples
#' spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: round-trip a dataset through rds ----
#' #
#' # Write a conformed dataset, then read it back; the metadata survives.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".rds")
#' write_dataset(adsl, path)
#' back <- read_dataset(path)
#' identical(get_meta(back)@columns, get_meta(adsl)@columns)
#'
#' # ---- Example 2: the metadata names the dataset and row count ----
#' #
#' # The restored artoo_meta exposes the dataset-level attributes.
#' get_meta(back)@dataset$records
#'
#' @seealso [write_dataset()] for the inverse; [read_rds()] for the
#'   per-format wrapper.
#' @export
read_dataset <- function(
  path,
  format = NULL,
  col_select = NULL,
  n_max = Inf,
  ...
) {
  call <- rlang::caller_env()
  .check_path(path, call)
  if (!file.exists(path)) {
    .artoo_abort(
      c(
        "{.arg path} does not exist.",
        "x" = "No file at {.path {path}}."
      ),
      kind = "input",
      call = call
    )
  }
  # Type-validate before decode: a codec that consumes these natively (xpt)
  # must not see an invalid value, so the gate runs ahead of dispatch.
  .validate_partial_args(col_select, n_max, call)

  fmt <- .resolve_format(path, format, call)
  codec <- .resolve_codec(fmt, call)
  decode <- .codec_fn(codec$decode)
  # Forward the partial-read args only to a decoder that declares them; the
  # rest are narrowed by the generic filter below. Every codec stays correct
  # even if it does no native push-down.
  fwd <- intersect(c("col_select", "n_max"), names(formals(decode)))
  dargs <- list(path)
  if ("col_select" %in% fwd) {
    dargs$col_select <- col_select
  }
  if ("n_max" %in% fwd) {
    dargs$n_max <- n_max
  }
  # The decode boundary takes untrusted file bytes. A codec aborts with a
  # artoo_error_* on malformed input, but an external engine (the parquet C++
  # reader, readRDS, jsonlite's UTF-8 validator) can raise a raw R error on a
  # truncated or bit-flipped file. The whole read path -- decode AND the
  # narrowing / meta-reattachment tail -- is translated, because a corrupt
  # container can also yield a payload that only fails later (an rds whose
  # bit-flipped bytes decompress to a RAGGED data frame breaks the column
  # re-projection; an invalid-UTF-8 label breaks the meta serializer). The
  # contract holds for every codec: return a data frame or abort with a
  # artoo condition, never leak a foreign error.
  tryCatch(
    {
      res <- do.call(decode, c(dargs, list(...), list(call = call)))
      # Self-describing containers (rds) can hold anything; the read_*
      # contract promises a data frame, so refuse other payloads loudly.
      if (!is.data.frame(res$data)) {
        msg <- c(
          "{.path {path}} does not contain a dataset.",
          "x" = "The {.val {fmt}} payload is {.obj_type_friendly {res$data}}, not a data frame."
        )
        if (identical(fmt, "rds")) {
          msg <- c(msg, "i" = "Use {.fn readRDS} for arbitrary R objects.")
        }
        .artoo_abort(msg, kind = "codec", call = call)
      }
      # The single source of partial-read correctness (which columns, what
      # order, which error). Idempotent on a frame a codec already narrowed.
      # Runs BEFORE set_meta so the re-projected label/format.sas attrs land
      # on the kept cols.
      red <- .apply_partial_read(res$data, res$meta, col_select, n_max, call)
      if (is_artoo_meta(red$meta)) {
        set_meta(red$data, red$meta)
      } else {
        red$data
      }
    },
    error = function(e) {
      # artoo's own conditions (the malformed-input message a codec crafted,
      # an unknown col_select name) pass through unchanged; only a foreign
      # error from an external engine is re-wrapped.
      if (any(grepl("^artoo_error_", class(e)))) {
        stop(e)
      }
      msg <- .safe_msg(e)
      .artoo_abort(
        c(
          "Could not read {.path {path}} as {.val {fmt}}.",
          "x" = "{msg}"
        ),
        kind = "codec",
        call = call
      )
    }
  )
}

# Type-check the partial-read arguments before any decode runs. col_select is
# NULL or a non-NA character vector; n_max is a single non-NA numeric, Inf or
# >= 0. Name validation (unknown column) happens later against the frame.
#' @noRd
.validate_partial_args <- function(col_select, n_max, call) {
  if (!is.null(col_select)) {
    if (!is.character(col_select) || anyNA(col_select)) {
      .artoo_abort(
        c(
          "{.arg col_select} must be a character vector of column names.",
          "x" = "You supplied {.obj_type_friendly {col_select}}."
        ),
        kind = "input",
        call = call
      )
    }
  }
  if (
    !is.numeric(n_max) ||
      length(n_max) != 1L ||
      is.na(n_max) ||
      n_max < 0
  ) {
    .artoo_abort(
      c(
        "{.arg n_max} must be a single non-negative number or {.code Inf}.",
        "x" = "You supplied {.obj_type_friendly {n_max}}."
      ),
      kind = "input",
      call = call
    )
  }
  invisible(NULL)
}

# The single authority for partial-read correctness: narrow the decoded frame
# (and its meta) to col_select (file order, unknown -> error) and n_max (row
# cap, records synced). Idempotent: re-narrowing an already-narrowed frame is a
# no-op, so a codec's native push-down stays observationally invisible.
#' @noRd
.apply_partial_read <- function(data, meta, col_select, n_max, call) {
  if (!is.null(col_select)) {
    missing_cols <- setdiff(as.character(col_select), names(data))
    if (length(missing_cols)) {
      .artoo_abort(
        c(
          "Unknown column{?s} in {.arg col_select}: {.val {missing_cols}}.",
          "i" = "The dataset has {.val {names(data)}}."
        ),
        kind = "input",
        call = call
      )
    }
    keep <- names(data)[names(data) %in% col_select] # file order, not requested
    data <- data[keep]
    if (is_artoo_meta(meta)) {
      meta <- .meta_select_columns(meta, keep)
    }
  }
  if (is.finite(n_max) && nrow(data) > n_max) {
    idx <- seq_len(n_max)
    # Row-subsetting a data frame drops column attributes; carry the
    # special-missing tags across, aligned to the kept rows. (xpt consumes
    # n_max natively, so this matters for the post-decode formats.)
    sm <- lapply(data, function(col) attr(col, "sas_missing", exact = TRUE))
    data <- data[idx, , drop = FALSE]
    for (nm in names(data)) {
      tags <- .subset_special_missings(sm[[nm]], idx)
      if (!is.null(tags) && any(!is.na(tags))) {
        attr(data[[nm]], "sas_missing") <- tags
      }
    }
    if (is_artoo_meta(meta)) {
      meta <- .meta_set_records(meta, nrow(data))
    }
  }
  list(data = data, meta = meta)
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
#' artoo_formats()
#'
#' @seealso [read_dataset()] and [write_dataset()] which use the registry.
#' @export
artoo_formats <- function() {
  fmts <- .registered_formats()
  data.frame(
    format = fmts,
    read = vapply(
      fmts,
      function(f) {
        codec <- .artoo_codecs[[f]]
        codec$mode %in% c("rw", "r") && .codec_available(codec)
      },
      logical(1)
    ),
    write = vapply(
      fmts,
      function(f) {
        codec <- .artoo_codecs[[f]]
        codec$mode == "rw" && .codec_available(codec)
      },
      logical(1)
    ),
    extensions = vapply(
      fmts,
      function(f) paste(.artoo_codecs[[f]]$extensions, collapse = ", "),
      character(1)
    ),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
