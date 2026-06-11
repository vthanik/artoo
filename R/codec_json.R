# codec_json.R -- the CDISC Dataset-JSON v1.1 codec.
#
# Dataset-JSON is the native home of vport's metadata shape: the file IS the
# serialized vport_meta plus a flat `rows` array (array-of-arrays, row-major).
# The metadata block is built by the SINGLE serializer .meta_payload() that
# every container's sidecar also uses (plan F4/4.0), so the columns/dataset
# attributes a .json file carries are byte-identical to what a parquet/rds
# sidecar would embed; the file codec only appends `datasetJSONCreationDateTime`
# and `rows`. jsonlite owns tokenizing/escaping/unicode; vport owns the v1.1
# structure, the CDISC type mapping, and the schema. The file is always UTF-8
# (RFC 8259 / CDISC v1.1).
#
# Type fidelity is META-DRIVEN, never inferred from JSON tokens (plan C1): the
# writer emits each value per its vport_meta dataType/targetDataType, and the
# reader reconstructs each column from the same meta, so a whole-number double
# does not drift to integer on the round-trip. date/datetime/time are exchanged
# as ISO 8601 strings, OR as SAS-epoch numbers when targetDataType = "integer"
# (the ADaM numeric-date convention, plan 9.A.5); `decimal` rides as a string
# end to end so exact precision survives (plan 9.A.9).

# Largest whole number an IEEE double represents exactly. CDISC `integer` maps
# to a 32-bit R integer (always well within this), so a JSON number always
# round-trips an integer exactly; the constant guards the float/double paths.
.json_exact_int_max <- 2^53

# ---- encode helpers ---------------------------------------------------------

# ISO 8601 text for a temporal column (the no-targetDataType exchange form).
# A character column already IS the ISO text (partials included) and passes
# through byte-faithfully; realizing first means a numeric/never-realized
# column still serializes correctly.
#' @noRd
.temporal_to_iso <- function(col, data_type, display_format) {
  if (is.character(col)) {
    return(col)
  }
  realized <- .realize_temporal(col, data_type, display_format)
  if (data_type == "date") {
    if (inherits(realized, "Date")) {
      format(realized, "%Y-%m-%d")
    } else {
      as.character(realized)
    }
  } else if (data_type == "datetime") {
    if (inherits(realized, "POSIXct")) {
      format(realized, "%Y-%m-%dT%H:%M:%S", tz = "UTC")
    } else {
      as.character(realized)
    }
  } else {
    if (is_vport_time(realized)) {
      format(realized)
    } else {
      as.character(realized)
    }
  }
}

# encode contract: (x, meta, path, <codec args>, call) -> invisible(path).
#' @noRd
.encode_json <- function(
  x,
  meta,
  path,
  created = NULL,
  strict = FALSE,
  call = rlang::caller_env()
) {
  if (!is_vport_meta(meta)) {
    cli::cli_abort(
      c(
        "Cannot write Dataset-JSON without metadata.",
        "x" = "The frame carries no columns to describe."
      ),
      class = "vport_error_codec",
      call = call
    )
  }
  created <- created %||% Sys.time()

  # The namespaced `_vport` block carries what strict CDISC cannot: special
  # missing tags, the recorded source encoding, informats. It appears only
  # when there is content; `strict = TRUE` suppresses it with a loss warning.
  special <- .json_prepare_special(x, meta, strict, path, call)

  # Canonicalise character columns to NFC so the UTF-8 output is canonical. A
  # no-op on ASCII / single-byte data, so demo goldens are byte-stable.
  for (nm in names(x)) {
    if (is.character(x[[nm]])) {
      x[[nm]] <- .nfc(x[[nm]])
    }
  }

  # Streaming write: the metadata head is serialized once (digits = I(17),
  # the guaranteed IEEE-754 round-trip precision -- digits = NA delegated to
  # R's 15-digit default, which silently lost the last ulp), then the rows
  # are streamed in slabs of per-column JSON literals (.json_stream_rows), so
  # a multi-million-row frame never materializes an O(rows x cols) cell list.
  # Byte-identical to the previous whole-object serialization (the goldens
  # under fixtures/json-golden pin this). Atomic: temp file, then rename.
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
  head_raw <- .json_head_raw(head_obj)

  tmp <- tempfile(tmpdir = dirname(path), fileext = ".json.tmp")
  con <- .json_out_con(tmp, path)
  ok <- FALSE
  tryCatch(
    {
      writeBin(head_raw[-length(head_raw)], con) # head minus its closing }
      writeBin(charToRaw(",\"rows\":["), con)
      .json_stream_rows(x, meta, con, call, sep = ",", progress = TRUE)
      writeBin(charToRaw("]}"), con)
      close(con)
      ok <- TRUE
    },
    finally = if (!ok) {
      try(close(con), silent = TRUE)
      if (file.exists(tmp)) {
        unlink(tmp)
      }
    }
  )
  .move_into_place(tmp, path)
  invisible(path)
}

# ---- decode helpers ---------------------------------------------------------

# Pull one typed extractor over a list of parsed JSON cells (NULL -> typed NA).
# A single vapply per column (plan 9.A.6) -- never the per-cell-per-column loop
# the archived reader used.
#' @noRd
.json_extract_num <- function(vals) {
  vapply(
    vals,
    function(v) if (is.null(v)) NA_real_ else as.numeric(v),
    numeric(1)
  )
}
#' @noRd
.json_extract_chr <- function(vals) {
  vapply(
    vals,
    function(v) if (is.null(v)) NA_character_ else as.character(v),
    character(1)
  )
}
#' @noRd
.json_extract_lgl <- function(vals) {
  vapply(vals, function(v) if (is.null(v)) NA else as.logical(v), logical(1))
}

# Reconstruct one column from its parsed cells, dispatched off the META
# dataType (plan C1). Temporal columns realize from a number (targetDataType =
# integer) or an ISO string; the choice follows targetDataType, falling back to
# the first non-null cell's JSON type for a foreign file.
#' @noRd
.json_decode_column <- function(vals, cm) {
  dt <- cm$dataType %||% "string"
  tgt <- cm$targetDataType
  disp <- cm$displayFormat

  if (dt %in% c("date", "datetime", "time")) {
    use_num <- identical(tgt, "integer")
    if (is.null(tgt) && length(vals)) {
      nn <- which(!vapply(vals, is.null, logical(1)))
      if (length(nn)) {
        use_num <- is.numeric(vals[[nn[1L]]])
      }
    }
    # Numbers are SAS-epoch values and realize to the R class; ISO text
    # stays text -- with no numeric targetDataType, text IS the recorded
    # storage form (--DTC), and partials make a silent promotion to Date
    # impossible anyway.
    if (!use_num) {
      return(.json_extract_chr(vals))
    }
    return(.realize_temporal(.json_extract_num(vals), dt, disp %||% NA))
  }

  switch(
    dt,
    string = ,
    URI = .json_extract_chr(vals),
    decimal = .json_extract_chr(vals),
    integer = as.integer(.json_extract_num(vals)),
    float = ,
    double = .json_extract_num(vals),
    boolean = .json_extract_lgl(vals),
    .json_extract_chr(vals)
  )
}

# Read the file, stripping a leading BOM and refusing an embedded NUL (plan
# B5), then transcode the byte stream from `encoding` to internal UTF-8 (NFC).
# Dataset-JSON is UTF-8 by spec, so `encoding` defaults to UTF-8; a non-UTF-8
# value reads a foreign (non-conformant) file a producer wrote in that charset.
#' @noRd
.json_read_text <- function(path, encoding = NULL, call) {
  bytes <- .read_maybe_gz(path)
  if (
    length(bytes) >= 3L &&
      bytes[1L] == as.raw(0xEF) &&
      bytes[2L] == as.raw(0xBB) &&
      bytes[3L] == as.raw(0xBF)
  ) {
    bytes <- bytes[-(1:3)]
  }
  if (any(bytes == as.raw(0x00))) {
    cli::cli_abort(
      c(
        "{.path {path}} is not a valid Dataset-JSON file.",
        "x" = "It contains an embedded NUL byte."
      ),
      class = "vport_error_codec",
      call = call
    )
  }
  .to_internal(rawToChar(bytes), encoding %||% "UTF-8")
}

# decode contract: (path, <codec args>, call) -> list(data, meta).
#' @noRd
.decode_json <- function(path, encoding = NULL, call = rlang::caller_env()) {
  txt <- .json_read_text(path, encoding, call)
  p <- tryCatch(
    jsonlite::fromJSON(txt, simplifyVector = FALSE),
    error = function(e) {
      # The parser message can contain braces; pass it as a value so cli does
      # not treat it as glue markup.
      msg <- conditionMessage(e)
      cli::cli_abort(
        c(
          "{.path {path}} is not valid JSON.",
          "x" = "{msg}"
        ),
        class = "vport_error_codec",
        call = call
      )
    }
  )
  # Probe the top-level shape before trusting it (plan E2): a JSON file that is
  # not Dataset-JSON v1.1 fails here with a clear message, not deep in decode.
  if (
    !is.list(p) ||
      is.null(p[["datasetJSONVersion"]]) ||
      is.null(p[["columns"]])
  ) {
    cli::cli_abort(
      c(
        "{.path {path}} is not a Dataset-JSON v1.1 file.",
        "x" = "It lacks the {.field datasetJSONVersion} and {.field columns} keys."
      ),
      class = "vport_error_codec",
      call = call
    )
  }

  meta <- .meta_from_parsed(p)
  col_names <- names(meta@columns)
  nc <- length(col_names)
  rows <- p[["rows"]] %||% list()

  # Every row must hold one cell per column; a ragged row would silently shift
  # every later column (plan C5). Abort at the first offender.
  if (length(rows)) {
    lens <- lengths(rows)
    bad <- which(lens != nc)
    if (length(bad)) {
      cli::cli_abort(
        c(
          "{.path {path}} has a malformed row.",
          "x" = "Row {bad[1]} has {lens[bad[1]]} value{?s}, expected {nc}."
        ),
        class = "vport_error_codec",
        call = call
      )
    }
  }

  cols <- vector("list", nc)
  for (k in seq_len(nc)) {
    cells <- lapply(rows, .subset2, k)
    cols[[k]] <- .json_decode_column(cells, meta@columns[[k]])
  }
  names(cols) <- col_names

  df <- structure(
    cols,
    names = col_names,
    row.names = .set_row_names(length(rows)),
    class = "data.frame"
  )
  # Reattach special-missing tags AFTER the columns are fully realized
  # (temporal realization rebuilds vectors and would drop the attribute).
  sm <- .special_from_parsed(p)
  if (!is.null(sm)) {
    df <- .apply_special_missings(df, sm)
  }
  list(data = df, meta = meta)
}

# ---- exported wrappers ------------------------------------------------------

#' Write a dataset to CDISC Dataset-JSON
#'
#' Serialize a data frame to a CDISC Dataset-JSON v1.1 (`.json`) file,
#' Dataset-JSON being the native home of the `vport_meta` shape: the file is
#' the metadata block plus a flat `rows` array. The emit end of the vport
#' workflow (spec -> apply_spec -> write_json); a thin wrapper over
#' [write_dataset()] with `format = "json"`.
#'
#' @details
#' **Full metadata, no loss.** Unlike `.xpt`, a `.json` file records the
#' complete `vport_meta`: keySequence, codelist, origin, targetDataType, and
#' significantDigits all survive. Dates, datetimes, and times are exchanged as
#' ISO 8601 strings, or as SAS-epoch numbers when their `targetDataType` is
#' `"integer"` (the ADaM numeric-date convention); `decimal` rides as a string
#' so exact precision is preserved. The file is always UTF-8 (RFC 8259 / CDISC
#' v1.1). `NaN` and infinite values are not valid CDISC numerics and abort the
#' write.
#'
#' **Streaming write, whole-file read.** The writer streams the `rows` array
#' in bounded slabs (a `.json.gz` path gzips the stream transparently), but
#' [read_json()] must parse the whole array at once. For multi-million-row
#' datasets prefer the NDJSON variant ([write_ndjson()] / [read_ndjson()]),
#' which bounds memory in both directions.
#'
#' @param x *The dataset to write.* `<data.frame>: required`. Typically the
#'   output of [apply_spec()], carrying `vport_meta`.
#' @param path *Destination `.json` path.* `<character(1)>: required`.
#' @param created *Creation timestamp.* `<POSIXct(1)> | NULL`. `NULL`
#'   (default) stamps the current time into `datasetJSONCreationDateTime`;
#'   freeze it for byte-stable output.
#' @param strict *Suppress the `_vport` extension block.* `<logical(1)>:
#'   default FALSE`. By default the file carries a single namespaced `_vport`
#'   object when (and only when) there is content strict CDISC cannot
#'   express: SAS special-missing tags (`.A`-`.Z`, `._`), the recorded source
#'   encoding, and informats. Data values stay plain `null`s either way, so a
#'   foreign reader degrades gracefully.
#'
#'   **Note:** `strict = TRUE` writes a pure closed-vocabulary file and warns
#'   (`vport_warning_codec`) naming exactly what was dropped; those
#'   attributes will not survive a read-back.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: write a conformed dataset as Dataset-JSON ----
#' #
#' # apply_spec() attaches the metadata; write_json() serializes the full
#' # itemGroup plus the data rows.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".json")
#' write_json(adsl, path)
#'
#' # ---- Example 2: a frozen timestamp for reproducible bytes ----
#' #
#' # Fixing `created` makes two writes byte-identical.
#' dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
#' path2 <- tempfile(fileext = ".json")
#' write_json(dm, path2, created = as.POSIXct("2020-01-01", tz = "UTC"))
#'
#' @seealso [read_json()] for the inverse; [write_dataset()] for the generic
#'   dispatcher.
#' @export
write_json <- function(x, path, created = NULL, strict = FALSE) {
  write_dataset(x, path, format = "json", created = created, strict = strict)
}

#' Read a dataset from CDISC Dataset-JSON
#'
#' Read a CDISC Dataset-JSON v1.1 (`.json`) file back to a data frame,
#' restoring the full `vport_meta` it carries and realizing SAS
#' date/datetime/time variables to R `Date` / `POSIXct` / `vport_time`. Column
#' types are reconstructed from the recorded metadata, not guessed from the
#' JSON tokens, so the round-trip is lossless. The ingest end of the I/O layer;
#' a thin wrapper over [read_dataset()] with `format = "json"`.
#'
#' @param path *Source `.json` path.* `<character(1)>: required`. A JSON file
#'   that is not Dataset-JSON v1.1 aborts with `vport_error_codec`.
#' @param encoding *Source charset of the file bytes.* `<character(1)> |
#'   NULL`. `NULL` (default) reads UTF-8, as Dataset-JSON requires. Pass an
#'   IANA or SAS charset name (e.g. `"windows-1252"`) only to read a
#'   non-conformant file a producer wrote in that charset; the bytes are
#'   transcoded to UTF-8 on read.
#' @inheritParams read_dataset
#'
#' @return *A `<data.frame>`* carrying `vport_meta` (read it with
#'   [get_meta()]).
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: round-trip a conformed dataset through Dataset-JSON ----
#' #
#' # The variable labels, types, and keys survive the round-trip.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".json")
#' write_json(adsl, path)
#' back <- read_json(path)
#' identical(get_meta(back)@columns, get_meta(adsl)@columns)
#'
#' # ---- Example 2: the metadata names the dataset and row count ----
#' #
#' # The restored vport_meta exposes the dataset-level attributes.
#' get_meta(back)@dataset$records
#'
#' @seealso [write_json()] for the inverse; [read_dataset()] for the generic
#'   dispatcher.
#' @export
read_json <- function(path, col_select = NULL, n_max = Inf, encoding = NULL) {
  read_dataset(
    path,
    format = "json",
    col_select = col_select,
    n_max = n_max,
    encoding = encoding
  )
}

.register_codec(
  "json",
  encode = ".encode_json",
  decode = ".decode_json",
  extensions = "json",
  mode = "rw"
)
