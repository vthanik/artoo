# codec_json.R — the CDISC Dataset-JSON v1.1 codec.
#
# Dataset-JSON is the native home of artoo's metadata shape: the file IS the
# serialized artoo_meta plus a flat `rows` array (array-of-arrays, row-major).
# The metadata block is built by the SINGLE serializer .meta_payload() that
# every container's sidecar also uses (plan F4/4.0), so the columns/dataset
# attributes a .json file carries are byte-identical to what a parquet/rds
# sidecar would embed; the file codec only appends `datasetJSONCreationDateTime`
# and `rows`. jsonlite owns tokenizing/escaping/unicode; artoo owns the v1.1
# structure, the CDISC type mapping, and the schema. The file is always UTF-8
# (RFC 8259 / CDISC v1.1).
#
# Type fidelity is META-DRIVEN, never inferred from JSON tokens (plan C1): the
# writer emits each value per its artoo_meta dataType/targetDataType, and the
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
    if (inherits(realized, "difftime")) {
      .time_iso_text(as.numeric(realized, units = "secs"))
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
  on_invalid = "error",
  created = NULL,
  strict = FALSE,
  call = rlang::caller_env()
) {
  if (!is_artoo_meta(meta)) {
    .artoo_abort(
      c(
        "Cannot write Dataset-JSON without metadata.",
        "x" = "The frame carries no columns to describe."
      ),
      kind = "codec",
      call = call
    )
  }
  created <- created %||% Sys.time()
  # The columns declaration derives from the meta while the rows stream from
  # the frame; reconcile so the two can never disagree (a frame mutated
  # after apply_spec() would otherwise write a corrupt or, worse, silently
  # misaligned file). A congruent meta reconciles to itself.
  meta <- .meta_reconcile(meta, x)

  # The namespaced `_artoo` block carries what strict CDISC cannot: special
  # missing tags, the recorded source encoding, informats. It appears only
  # when there is content; `strict = TRUE` suppresses it with a loss warning.
  special <- .json_prepare_special(x, meta, strict, path, call)

  # Gate character columns through the UTF-8 validity policy, then
  # canonicalise to NFC so the output is canonical UTF-8 (RFC 8259). The
  # gate runs first: normalization needs valid UTF-8. Both are no-ops on
  # ASCII / single-byte data, so demo goldens are byte-stable.
  for (nm in names(x)) {
    if (is.character(x[[nm]])) {
      x[[nm]] <- .nfc(.to_target(x[[nm]], "UTF-8", on_invalid, call))
    }
  }

  # Streaming write: the metadata head is serialized once (digits = I(17),
  # the guaranteed IEEE-754 round-trip precision — digits = NA delegated to
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

  .with_atomic_write(
    path,
    ".json.tmp",
    function(tmp) {
      con <- .json_out_con(tmp, path)
      on.exit(try(close(con), silent = TRUE))
      writeBin(head_raw[-length(head_raw)], con) # head minus its closing }
      writeBin(charToRaw(",\"rows\":["), con)
      .json_stream_rows(x, meta, con, call, sep = ",", progress = TRUE)
      writeBin(charToRaw("]}"), con)
    },
    call
  )
}

# ---- decode helpers ---------------------------------------------------------

# Pull one typed extractor over a list of parsed JSON cells (NULL -> typed NA).
# A single vapply per column (plan 9.A.6) — never the per-cell-per-column loop
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
    # stays text — with no numeric targetDataType, text IS the recorded
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
    integer = .json_int_or_dbl(.json_extract_num(vals)),
    float = ,
    double = .json_extract_num(vals),
    boolean = .json_extract_lgl(vals),
    .json_extract_chr(vals)
  )
}

# Realize an integer dataType column. Dataset-JSON integers are arbitrary
# precision, so a value beyond R's 32-bit range stays a double (lossless)
# instead of being silently coerced to NA by as.integer(); a column that fits
# returns an integer vector, unchanged from before.
#' @noRd
.json_int_or_dbl <- function(num) {
  if (all(is.na(num) | abs(num) <= .Machine$integer.max)) {
    return(as.integer(num))
  }
  num
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
    .artoo_abort(
      c(
        "{.path {path}} is not a valid Dataset-JSON file.",
        "x" = "It contains an embedded NUL byte.",
        "i" = "The file is corrupt or binary; re-export it from the source system."
      ),
      kind = "codec",
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
      msg <- .safe_msg(e)
      .artoo_abort(
        c(
          "{.path {path}} is not valid JSON.",
          "x" = "{msg}",
          "i" = "The file may be truncated or not Dataset-JSON; re-export it."
        ),
        kind = "codec",
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
    .artoo_abort(
      c(
        "{.path {path}} is not a Dataset-JSON v1.1 file.",
        "x" = "It lacks the {.field datasetJSONVersion} and {.field columns} keys.",
        "i" = "artoo reads CDISC Dataset-JSON v1.1; check the producing tool and version."
      ),
      kind = "codec",
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
      .artoo_abort(
        c(
          "{.path {path}} has a malformed row.",
          "x" = "Row {bad[1]} has {lens[bad[1]]} value{?s}, expected {nc}.",
          "i" = "Every row must match the {.field columns} declaration; the file is corrupt or hand-edited."
        ),
        kind = "codec",
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
#' Dataset-JSON being the native home of the `artoo_meta` shape: the file is
#' the metadata block plus a flat `rows` array. The emit end of the artoo
#' workflow (spec -> apply_spec -> write_json); a thin wrapper over
#' [write_dataset()] with `format = "json"`.
#'
#' @details
#' **Full metadata, no loss.** Unlike `.xpt`, a `.json` file records the
#' complete `artoo_meta`: keySequence, codelist, origin, targetDataType, and
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
#'   output of [apply_spec()], carrying `artoo_meta`.
#' @param path *Destination `.json` path.* `<character(1)>: required`.
#' @param on_invalid *Policy for values that are not valid UTF-8.*
#'   `<character(1)>: default "error"`. One of `"error"` (abort with
#'   `artoo_error_codec`, naming the offenders with their invalid bytes
#'   hex-escaped), `"replace"` (substitute `?` and warn with
#'   `artoo_warning_encoding`), `"ignore"` (drop the invalid bytes), or
#'   `"translit"` (like `"error"`; a byte-level invalidity has no
#'   punctuation fold, the option exists so one policy value can thread a
#'   whole multi-format pipeline).
#'   The same policy vocabulary as [write_xpt()]; text correctly read
#'   through artoo is always valid UTF-8, so this only fires on bytes
#'   that entered the frame through a mis-declared source encoding.
#' @param created *Creation timestamp.* `<POSIXct(1)> | NULL`. `NULL`
#'   (default) stamps the current time into `datasetJSONCreationDateTime`;
#'   freeze it for byte-stable output.
#' @param strict *Suppress the `_artoo` extension block.* `<logical(1)>:
#'   default FALSE`. By default the file carries a single namespaced `_artoo`
#'   object when (and only when) there is content strict CDISC cannot
#'   express: SAS special-missing tags (`.A`-`.Z`, `._`), the recorded source
#'   encoding, and informats. Data values stay plain `null`s either way, so a
#'   foreign reader degrades gracefully.
#'
#'   **Note:** `strict = TRUE` writes a pure closed-vocabulary file and warns
#'   (`artoo_warning_codec`) naming exactly what was dropped; those
#'   attributes will not survive a read-back.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'
#' @examples
#' # ---- Example 1: write a conformed dataset as Dataset-JSON ----
#' #
#' # apply_spec() attaches the metadata; write_json() serializes the full
#' # itemGroup plus the data rows.
#' adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".json")
#' write_json(adsl, path)
#'
#' # ---- Example 2: a frozen timestamp for reproducible bytes ----
#' #
#' # Fixing `created` makes two writes byte-identical; the columns() pane on
#' # the written file shows the full metadata the file carries (DM is SDTM,
#' # so it conforms against the bundled sdtm_spec).
#' dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#' path2 <- tempfile(fileext = ".json")
#' write_json(dm, path2, created = as.POSIXct("2020-01-01", tz = "UTC"))
#' columns(path2)
#'
#' @seealso [read_json()] for the inverse; [write_dataset()] for the generic
#'   dispatcher.
#' @export
write_json <- function(
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
    format = "json",
    on_invalid = on_invalid,
    created = created,
    strict = strict
  )
}

#' Read a dataset from CDISC Dataset-JSON
#'
#' Read a CDISC Dataset-JSON v1.1 (`.json`) file back to a data frame,
#' restoring the full `artoo_meta` it carries and realizing SAS
#' date/datetime/time variables to R `Date` / `POSIXct` / `hms::hms`. Column
#' types are reconstructed from the recorded metadata, not guessed from the
#' JSON tokens, so the round-trip is lossless. The ingest end of the I/O layer;
#' a thin wrapper over [read_dataset()] with `format = "json"`.
#'
#' @param path *Source `.json` path.* `<character(1)>: required`. A JSON file
#'   that is not Dataset-JSON v1.1 aborts with `artoo_error_codec`.
#' @param encoding *Source charset of the file bytes.* `<character(1)> |
#'   NULL`. `NULL` (default) reads UTF-8, as Dataset-JSON requires. Pass an
#'   IANA or SAS charset name (e.g. `"windows-1252"`) only to read a
#'   non-conformant file a producer wrote in that charset; the bytes are
#'   transcoded to UTF-8 on read.
#'
#'   **Tip:** any SAS or IANA spelling listed by [artoo_encodings()] is
#'   accepted.
#' @inheritParams read_dataset
#'
#' @return *A `<data.frame>`* carrying `artoo_meta` (read it with
#'   [get_meta()]).
#'
#' @examples
#' spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)
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
#' # The restored artoo_meta exposes the dataset-level attributes.
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
