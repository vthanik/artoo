# codec_ndjson.R — the CDISC Dataset-JSON v1.1 codec, NDJSON variant.
#
# NDJSON (newline-delimited JSON) is the streaming exchange form Dataset-JSON
# v1.1 defines for large datasets: line 1 holds everything a `.json` file
# carries except `rows` (the same metadata payload, built by the ONE
# serializer .meta_payload()); every subsequent line is one row array.
# Memory stays bounded in BOTH directions — the writer streams slabs of
# per-column literals (json_common.R) and the reader parses slab-sized line
# batches — which the array-form `.json` reader cannot do (it materializes
# the whole `rows` array). Use ndjson for multi-million-row datasets.

# encode contract: (x, meta, path, <codec args>, call) -> invisible(path).
#' @noRd
.encode_ndjson <- function(
  x,
  meta,
  path,
  on_invalid = "error",
  created = NULL,
  strict = FALSE,
  call = rlang::caller_env()
) {
  if (!is_artoo_meta(meta)) {
    .artoo_abort(
      c(
        "Cannot write Dataset-JSON NDJSON without metadata.",
        "x" = "The frame carries no columns to describe."
      ),
      kind = "codec",
      call = call
    )
  }
  created <- created %||% Sys.time()
  # Same contract as the .json codec: the metadata line must describe
  # exactly the rows that follow it.
  meta <- .meta_reconcile(meta, x)
  special <- .json_prepare_special(x, meta, strict, path, call)

  # Gate UTF-8 validity, then canonicalise to NFC (same contract as the
  # .json codec).
  for (nm in names(x)) {
    if (is.character(x[[nm]])) {
      x[[nm]] <- .nfc(.to_target(x[[nm]], "UTF-8", on_invalid, call))
    }
  }

  head_obj <- c(
    list(
      datasetJSONCreationDateTime = format(
        created,
        "%Y-%m-%dT%H:%M:%S",
        tz = "UTC"
      )
    ),
    .meta_payload(meta, extensions = !isTRUE(strict), special = special)
  )

  .with_atomic_write(
    path,
    ".ndjson.tmp",
    function(tmp) {
      con <- .json_out_con(tmp, path)
      on.exit(try(close(con), silent = TRUE))
      writeBin(c(.json_head_raw(head_obj), charToRaw("\n")), con)
      .json_stream_rows(x, meta, con, call, sep = "\n", progress = TRUE)
      if (nrow(x) > 0L) {
        writeBin(charToRaw("\n"), con)
      }
    },
    call
  )
}

# decode contract: (path, <codec args>, call) -> list(data, meta). n_max is
# consumed natively: the line loop stops as soon as enough rows are read, so
# a partial read of a huge file never parses the tail.
#' @noRd
.decode_ndjson <- function(
  path,
  n_max = Inf,
  encoding = NULL,
  call = rlang::caller_env()
) {
  # Stream through the connection at the source charset (resolved to an iconv
  # spelling file()/gzfile() accept), so readLines re-encodes each line to
  # UTF-8 on the fly. This keeps the n_max slab streaming that reading the
  # whole file through .to_internal (the read_json path) would defeat.
  enc <- .resolve_charset(encoding %||% "UTF-8")
  head2 <- readBin(path, what = "raw", n = 2L)
  con <- if (
    length(head2) == 2L &&
      head2[1L] == as.raw(0x1F) &&
      head2[2L] == as.raw(0x8B)
  ) {
    gzfile(path, "rt", encoding = enc)
  } else {
    file(path, "rt", encoding = enc)
  }
  on.exit(close(con), add = TRUE)

  first <- readLines(con, n = 1L, warn = FALSE)
  bad_file <- function(why) {
    .artoo_abort(
      c(
        "{.path {path}} is not a Dataset-JSON NDJSON file.",
        "x" = why
      ),
      kind = "codec",
      call = call
    )
  }
  if (!length(first) || !nzchar(first)) {
    bad_file("The file has no metadata line.")
  }
  first <- sub("^\ufeff", "", first) # strip a UTF-8 BOM
  p <- tryCatch(
    jsonlite::fromJSON(first, simplifyVector = FALSE),
    error = function(e) bad_file("Line 1 is not valid JSON.")
  )
  if (
    !is.list(p) ||
      is.null(p[["datasetJSONVersion"]]) ||
      is.null(p[["columns"]])
  ) {
    bad_file(
      "Line 1 lacks the {.field datasetJSONVersion} and {.field columns} keys."
    )
  }

  meta <- .meta_from_parsed(p)
  col_names <- names(meta@columns)
  nc <- length(col_names)
  slab <- .json_slab_rows()
  acc <- rep(list(list()), nc)
  total <- 0L

  while (total < n_max) {
    lines <- readLines(con, n = slab, warn = FALSE)
    if (!length(lines)) {
      break
    }
    lines <- lines[nzchar(lines)] # tolerate a trailing blank line
    if (!length(lines)) {
      next
    }
    if (is.finite(n_max) && total + length(lines) > n_max) {
      lines <- lines[seq_len(as.integer(n_max) - total)]
    }
    rows <- tryCatch(
      jsonlite::fromJSON(
        paste0("[", paste(lines, collapse = ","), "]"),
        simplifyVector = FALSE
      ),
      error = function(e) {
        .artoo_abort(
          c(
            "{.path {path}} has a malformed row line.",
            "x" = "Rows {total + 1} to {total + length(lines)} did not parse as JSON."
          ),
          kind = "codec",
          call = call
        )
      }
    )
    lens <- lengths(rows)
    bad <- which(lens != nc)
    if (length(bad)) {
      .artoo_abort(
        c(
          "{.path {path}} has a malformed row.",
          "x" = "Row {total + bad[1]} has {lens[bad[1]]} value{?s}, expected {nc}."
        ),
        kind = "codec",
        call = call
      )
    }
    for (k in seq_len(nc)) {
      acc[[k]][[length(acc[[k]]) + 1L]] <- lapply(rows, .subset2, k)
    }
    total <- total + length(rows)
  }

  cols <- vector("list", nc)
  for (k in seq_len(nc)) {
    cells <- if (length(acc[[k]])) do.call(c, acc[[k]]) else list()
    col <- .json_decode_column(cells, meta@columns[[k]])
    # NFC-normalize character columns for parity with read_json (which routes
    # through .to_internal). A no-op on ASCII / single-byte content, so the
    # byte-golden round-trips stay stable.
    if (is.character(col)) {
      col <- .nfc(col)
    }
    cols[[k]] <- col
  }
  names(cols) <- col_names
  df <- structure(
    cols,
    names = col_names,
    row.names = .set_row_names(total),
    class = "data.frame"
  )
  sm <- .special_from_parsed(p)
  if (!is.null(sm)) {
    df <- .apply_special_missings(df, sm)
  }
  # records reflects the rows actually read (the xpt n_max contract).
  meta <- .meta_set_records(meta, total)
  list(data = df, meta = meta)
}

# ---- exported wrappers ------------------------------------------------------

#' Write a dataset to CDISC Dataset-JSON NDJSON
#'
#' Serialize a data frame to the newline-delimited variant of CDISC
#' Dataset-JSON v1.1 (`.ndjson`): line 1 carries the complete metadata block,
#' every following line one row array. The streaming end of the artoo
#' workflow (spec -> apply_spec -> write_ndjson) for datasets too large for
#' the array-form `.json` file; a thin wrapper over [write_dataset()] with
#' `format = "ndjson"`.
#'
#' @details
#' **Bounded memory, both directions.** The writer streams slabs of
#' per-column JSON literals and [read_ndjson()] parses slab-sized line
#' batches, so a multi-million-row dataset never materializes a whole `rows`
#' array the way the `.json` codec must. A `.ndjson.gz` path gzips the stream
#' transparently.
#'
#' @param x *The dataset to write.* `<data.frame>: required`. Typically the
#'   output of [apply_spec()], carrying `artoo_meta`.
#' @param path *Destination `.ndjson` path.* `<character(1)>: required`. A
#'   `.ndjson.gz` path writes gzip-compressed bytes.
#' @param on_invalid *Policy for values that are not valid UTF-8.*
#'   `<character(1)>: default "error"`. One of `"error"` (abort with
#'   `artoo_error_codec`), `"replace"` (substitute `?` and warn with
#'   `artoo_warning_encoding`), `"ignore"` (drop the invalid bytes), or
#'   `"translit"` (accepted for pipeline symmetry; behaves as `"error"`
#'   here, since a byte-level invalidity has no punctuation fold).
#'   See [write_json()] for when this fires.
#' @param created *Creation timestamp.* `<POSIXct(1)> | NULL`. `NULL`
#'   (default) stamps the current time into `datasetJSONCreationDateTime`;
#'   freeze it for byte-stable output.
#' @param strict *Suppress the `_artoo` extension block.* `<logical(1)>:
#'   default FALSE`. See [write_json()]: the same extension semantics apply
#'   to the metadata line.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'
#' @examples
#' spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: write a conformed dataset as NDJSON ----
#' #
#' # apply_spec() attaches the metadata; write_ndjson() streams the metadata
#' # line and one row per line.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".ndjson")
#' write_ndjson(adsl, path)
#' readLines(path, n = 2)[2]
#'
#' # ---- Example 2: gzip the stream via the file extension ----
#' #
#' # A .ndjson.gz path compresses transparently; read_ndjson() inflates it.
#' gz <- tempfile(fileext = ".ndjson.gz")
#' write_ndjson(adsl, gz)
#' nrow(read_ndjson(gz))
#'
#' @seealso [read_ndjson()] for the inverse; [write_json()] for the
#'   array-form file; [write_dataset()] for the generic dispatcher.
#' @export
write_ndjson <- function(
  x,
  path,
  on_invalid = c("error", "replace", "ignore", "translit"),
  created = NULL,
  strict = FALSE
) {
  on_invalid <- match.arg(on_invalid)
  write_dataset(
    x,
    path,
    format = "ndjson",
    on_invalid = on_invalid,
    created = created,
    strict = strict
  )
}

#' Read a dataset from CDISC Dataset-JSON NDJSON
#'
#' Read a newline-delimited CDISC Dataset-JSON v1.1 (`.ndjson`) file back to
#' a data frame, restoring the full `artoo_meta` from its metadata line and
#' realizing SAS date/datetime/time variables to R `Date` / `POSIXct` /
#' `hms::hms`. Rows are parsed in bounded slabs, and `n_max` stops the
#' line loop early, so a partial read of a huge file never parses the tail.
#' A thin wrapper over [read_dataset()] with `format = "ndjson"`.
#'
#' @param path *Source `.ndjson` path.* `<character(1)>: required`. A gzip
#'   stream (`.ndjson.gz`) is inflated transparently. A file whose first line
#'   is not the Dataset-JSON metadata object aborts with `artoo_error_codec`.
#' @inheritParams read_dataset
#' @param encoding *Source charset of the file bytes.* `<character(1)> |
#'   NULL`. `NULL` (default) reads UTF-8, as Dataset-JSON requires. Pass an
#'   IANA or SAS charset name (e.g. `"windows-1252"`) only to read a
#'   non-conformant file a producer wrote in that charset; each line is
#'   transcoded to UTF-8 on read, preserving the bounded `n_max` streaming.
#'
#' @return *A `<data.frame>`* carrying `artoo_meta` (read it with
#'   [get_meta()]).
#'
#' @examples
#' spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: round-trip a conformed dataset through NDJSON ----
#' #
#' # The variable labels, types, and keys survive the round-trip.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".ndjson")
#' write_ndjson(adsl, path)
#' back <- read_ndjson(path)
#' identical(get_meta(back)@columns, get_meta(adsl)@columns)
#'
#' # ---- Example 2: a bounded partial read of the first rows ----
#' #
#' # n_max stops the line loop as soon as enough rows are in.
#' head_rows <- read_ndjson(path, n_max = 5)
#' get_meta(head_rows)@dataset$records
#'
#' @seealso [write_ndjson()] for the inverse; [read_json()] for the
#'   array-form file; [read_dataset()] for the generic dispatcher.
#' @export
read_ndjson <- function(path, col_select = NULL, n_max = Inf, encoding = NULL) {
  read_dataset(
    path,
    format = "ndjson",
    col_select = col_select,
    n_max = n_max,
    encoding = encoding
  )
}

.register_codec(
  "ndjson",
  encode = ".encode_ndjson",
  decode = ".decode_ndjson",
  extensions = c("ndjson", "jsonl"),
  mode = "rw"
)
