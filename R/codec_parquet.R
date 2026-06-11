# codec_parquet.R -- the Apache Parquet codec (nanoparquet engine + sidecar).
#
# Parquet stores the data natively via nanoparquet (a lightweight, zero-R-dep
# engine -- arrow is banned), and vport's full CDISC metadata rides alongside
# as the universal `metadata_json` sidecar (plan 4.0/4.1): the single
# Dataset-JSON-shaped string set_meta() stamps, embedded verbatim in the
# parquet file's key-value metadata under the key "metadata_json". This is
# exactly where vport beats plain nanoparquet/arrow, which drop
# labels/formats/codelists -- vport round-trips the complete vport_meta.
#
# Read precedence is META-FIRST (plan D1): types are reconstructed from the
# sidecar, with nanoparquet's native column types advisory. A parquet written
# by another tool (no sidecar) degrades gracefully to a bare frame, never an
# error (plan 9.B). nanoparquet round-trips a tens-of-KB metadata value
# verbatim, so the chunked-key fallback is unnecessary at clinical spec sizes.

.parquet_meta_key <- "metadata_json"

# Pull the metadata_json value out of a parquet file's key-value metadata, or
# NULL when the file carries none (a foreign / plain-nanoparquet file).
#' @noRd
.parquet_sidecar <- function(path) {
  md <- nanoparquet::read_parquet_metadata(path)
  kv <- md$file_meta_data$key_value_metadata
  tbl <- if (is.null(kv) || !length(kv)) NULL else kv[[1L]]
  if (is.null(tbl) || !(.parquet_meta_key %in% tbl$key)) {
    return(NULL)
  }
  # The key is present (checked above) and parquet KV values are always single
  # strings, so the first match is the sidecar.
  out <- tbl$value[tbl$key == .parquet_meta_key][[1L]]
  Encoding(out) <- "UTF-8"
  out
}

# encode contract: (x, meta, path, <codec args>, call) -> invisible(path).
#' @noRd
.encode_parquet <- function(
  x,
  meta,
  path,
  encoding = NULL,
  compression = "snappy",
  call = rlang::caller_env()
) {
  rlang::check_installed("nanoparquet", reason = "to write Parquet files.")

  valid_comp <- c("snappy", "gzip", "zstd", "uncompressed")
  if (
    !is.character(compression) ||
      length(compression) != 1L ||
      !compression %in% valid_comp
  ) {
    cli::cli_abort(
      c(
        "{.arg compression} must be one of {.val {valid_comp}}.",
        "x" = "You supplied {.val {compression}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }

  # Parquet bytes stay UTF-8 (the format's STRING type is UTF-8 by spec); an
  # explicit `encoding` is recorded as the source-charset metadata so a later
  # write_xpt() can reproduce the original bytes. Validate the name loudly.
  if (!is.null(encoding) && is_vport_meta(meta)) {
    .resolve_charset(encoding, call)
    meta <- .meta_set_encoding(meta, encoding)
  }

  # vport_time is a classed double with no native parquet type; store the bare
  # seconds (the read path realizes it back from the sidecar dataType). Date
  # and POSIXct have native parquet types, so they pass through untouched.
  # Character columns are NFC-canonicalised (a no-op on ASCII / single-byte).
  for (nm in names(x)) {
    if (is_vport_time(x[[nm]])) {
      x[[nm]] <- unclass(x[[nm]])
    } else if (is.character(x[[nm]])) {
      x[[nm]] <- .nfc(x[[nm]])
    }
  }
  # The frame-level metadata_json attribute (if any) is not a column; drop it
  # so it never leaks into the parquet schema. The sidecar below is the home.
  attr(x, "metadata_json") <- NULL

  kv <- if (is_vport_meta(meta)) {
    stats::setNames(
      .meta_to_datasetjson(
        meta,
        extensions = TRUE,
        special = .collect_special_missings(x)
      ),
      .parquet_meta_key
    )
  } else {
    NULL
  }

  # Atomic write: build in a temp file, then rename over the target.
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".parquet.tmp")
  ok <- FALSE
  tryCatch(
    {
      if (is.null(kv)) {
        nanoparquet::write_parquet(x, tmp, compression = compression)
      } else {
        nanoparquet::write_parquet(
          x,
          tmp,
          compression = compression,
          metadata = kv
        )
      }
      ok <- TRUE
    },
    finally = if (!ok && file.exists(tmp)) {
      unlink(tmp)
    }
  )
  .move_into_place(tmp, path)
  invisible(path)
}

# Read the parquet frame, using nanoparquet's native column projection when it
# is available and col_select is given (a real columnar IO win). nanoparquet
# returns columns in the requested order, so the kept names are fed in FILE
# order (from the schema) to keep behavior identical to a full read. Any
# failure (old nanoparquet, odd schema) falls back to a full read; the generic
# filter in read_dataset() is the single source of selection correctness.
#' @noRd
.parquet_read_frame <- function(path, col_select) {
  full <- function() as.data.frame(nanoparquet::read_parquet(path))
  if (
    is.null(col_select) ||
      !"col_select" %in% names(formals(nanoparquet::read_parquet))
  ) {
    return(full())
  }
  tryCatch(
    {
      file_cols <- nanoparquet::read_parquet_schema(path)$name[-1L]
      keep <- file_cols[file_cols %in% col_select]
      if (!length(keep)) {
        return(full()) # all-unknown: let the generic filter raise the error
      }
      as.data.frame(nanoparquet::read_parquet(path, col_select = keep))
    },
    error = function(e) full()
  )
}

# decode contract: (path, <codec args>, call) -> list(data, meta).
#' @noRd
.decode_parquet <- function(
  path,
  col_select = NULL,
  encoding = NULL,
  call = rlang::caller_env()
) {
  rlang::check_installed("nanoparquet", reason = "to read Parquet files.")

  df <- .parquet_read_frame(path, col_select)
  # Parquet STRING bytes are UTF-8; canonicalise to internal UTF-8 (NFC). An
  # explicit `encoding` instead reads a foreign file whose bytes are that
  # charset. Non-character columns pass through untouched.
  source_enc <- encoding %||% "UTF-8"
  for (nm in names(df)) {
    df[[nm]] <- .recode_col(df[[nm]], source_enc)
  }
  json <- .parquet_sidecar(path)
  # Parse the sidecar ONCE: the same parsed object feeds the meta rebuild and
  # the special-missing tag reattachment below. A foreign / plain-nanoparquet
  # file (no sidecar) gets metadata synthesized from the column types and
  # attributes -- the same path a bare frame takes on write -- so the result
  # still feeds get_meta() and write_xpt()/write_json(), never an abort
  # (plan 9.B).
  p <- if (is.null(json)) {
    NULL
  } else {
    jsonlite::fromJSON(json, simplifyVector = FALSE)
  }
  meta <- if (is.null(p)) .meta_from_frame(df) else .meta_from_parsed(p)
  if (is.null(meta)) {
    return(list(data = df, meta = NULL)) # 0-column foreign file
  }
  # Realize temporal columns from the meta dataType (plan D1: meta-first).
  # Date/POSIXct survive nanoparquet natively and realize idempotently (the
  # integer-backed DATE arrival is canonicalized to double); a time column
  # comes back a bare double and becomes vport_time here. A character ISO
  # 8601 column (the no-targetDataType --DTC form) stays text -- realize is
  # for numeric storage, and text is already readable.
  for (nm in names(meta@columns)) {
    cm <- meta@columns[[nm]]
    dt <- cm$dataType %||% ""
    if (
      dt %in%
        c("date", "datetime", "time") &&
        nm %in% names(df) &&
        !is.character(df[[nm]])
    ) {
      df[[nm]] <- .realize_temporal(df[[nm]], dt, cm$displayFormat %||% NA)
    }
  }
  # Reattach special-missing tags AFTER realization (it rebuilds vectors).
  sm <- if (is.null(p)) NULL else .special_from_parsed(p)
  if (!is.null(sm)) {
    df <- .apply_special_missings(df, sm)
  }
  list(data = df, meta = meta)
}

# ---- exported wrappers ------------------------------------------------------

#' Write a dataset to Apache Parquet
#'
#' Serialize a data frame to an Apache Parquet (`.parquet`) file, storing the
#' data natively while preserving the full `vport_meta` as a CDISC-shaped
#' sidecar in the file's key-value metadata. The emit end of the vport
#' workflow (spec -> apply_spec -> write_parquet); a thin wrapper over
#' [write_dataset()] with `format = "parquet"`. Requires the lightweight
#' `nanoparquet` package.
#'
#' @details
#' **Metadata where plain Parquet has none.** A bare nanoparquet/arrow file
#' drops labels, formats, and codelists; `write_parquet()` embeds the complete
#' `vport_meta` as a single Dataset-JSON-shaped string under the
#' `metadata_json` key, so [read_parquet()] restores every CDISC attribute.
#' The same string is what a `.json` file or an rds carries, so conversion
#' between any two formats stays lossless. A reader without vport still opens
#' the data and can see the `metadata_json` block.
#'
#' @param x *The dataset to write.* `<data.frame>: required`. Typically the
#'   output of [apply_spec()], carrying `vport_meta`.
#' @param path *Destination `.parquet` path.* `<character(1)>: required`.
#' @param encoding *Source charset to record.* `<character(1)> | NULL`. The
#'   parquet bytes are always written as UTF-8 (the format's STRING type is
#'   UTF-8 by spec); `encoding` only records the data's original charset in the
#'   `vport_meta`, so a later [write_xpt()] can reproduce the source bytes.
#'   `NULL` (default) leaves the recorded encoding untouched.
#' @param compression *Column compression codec.* `<character(1)>: default
#'   "snappy"`. One of:
#'
#'   - `"snappy"` (default) -- fast, the parquet ecosystem default.
#'   - `"gzip"` -- smaller files, slower.
#'   - `"zstd"` -- the best size/speed trade-off where supported.
#'   - `"uncompressed"` -- raw pages.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: write a conformed dataset to Parquet ----
#' #
#' # apply_spec() attaches the metadata; write_parquet() stores the data
#' # natively and the metadata as a CDISC-shaped sidecar.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".parquet")
#' write_parquet(adsl, path)
#'
#' # ---- Example 2: round-trip and confirm the metadata survived ----
#' #
#' # Reading it back yields an identical vport_meta.
#' back <- read_parquet(path)
#' identical(get_meta(back)@columns, get_meta(adsl)@columns)
#'
#' @seealso [read_parquet()] for the inverse; [write_dataset()] for the
#'   generic dispatcher.
#' @export
write_parquet <- function(x, path, encoding = NULL, compression = "snappy") {
  write_dataset(
    x,
    path,
    format = "parquet",
    encoding = encoding,
    compression = compression
  )
}

#' Read a dataset from Apache Parquet
#'
#' Read an Apache Parquet (`.parquet`) file back to a data frame, restoring the
#' `vport_meta` from its `metadata_json` sidecar and realizing SAS
#' date/datetime/time variables to R `Date` / `POSIXct` / `vport_time`. A
#' parquet written by another tool (with no vport sidecar) reads back as a
#' bare frame. A thin wrapper over [read_dataset()] with `format = "parquet"`.
#' Requires the lightweight `nanoparquet` package.
#'
#' @param path *Source `.parquet` path.* `<character(1)>: required`.
#' @param encoding *Source charset of the string columns.* `<character(1)> |
#'   NULL`. `NULL` (default) reads the UTF-8 bytes parquet stores. Pass a
#'   charset name only to read a foreign file whose string columns hold that
#'   charset's bytes; they are transcoded to UTF-8 on read.
#' @inheritParams read_dataset
#'
#' @return *A `<data.frame>`* carrying `vport_meta` when the file recorded it
#'   (read it with [get_meta()]); otherwise a plain data frame.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: round-trip a conformed dataset through Parquet ----
#' #
#' # The variable labels, types, and keys survive the round-trip.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".parquet")
#' write_parquet(adsl, path)
#' back <- read_parquet(path)
#' get_meta(back)@columns$STUDYID$label
#'
#' # ---- Example 2: the metadata names the dataset and row count ----
#' #
#' # The restored vport_meta exposes the dataset-level attributes.
#' get_meta(back)@dataset$records
#'
#' @seealso [write_parquet()] for the inverse; [read_dataset()] for the
#'   generic dispatcher.
#' @export
read_parquet <- function(
  path,
  col_select = NULL,
  n_max = Inf,
  encoding = NULL
) {
  read_dataset(
    path,
    format = "parquet",
    col_select = col_select,
    n_max = n_max,
    encoding = encoding
  )
}

.register_codec(
  "parquet",
  encode = ".encode_parquet",
  decode = ".decode_parquet",
  extensions = c("parquet", "pq"),
  mode = "rw",
  engine = "nanoparquet"
)
