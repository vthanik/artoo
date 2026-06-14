# json_common.R — the columnar JSON literal engine, shared by the
# Dataset-JSON file codec (codec_json.R) and the NDJSON codec
# (codec_ndjson.R).
#
# The engine turns one column into a character vector of ready JSON tokens
# ("null" at missing positions), so a rows section is assembled by vectorized
# paste, never by an O(rows x cols) nested list of cells. jsonlite still owns
# every byte of tokenizing/escaping/number formatting: each column's non-NA
# values are serialized ONCE as a JSON array, the outer brackets are
# stripped, and the elements are recovered by splitting on the separator.
# The split is structural, not a hand-rolled parser:
# - string arrays split on the exact 3-byte sequence `","` — inside JSON
#   string content a quote is always escaped to \", so quote-comma-quote can
#   only be a separator (the values are serialized NA-free, so no bare null
#   ever interrupts the pattern);
# - numeric/boolean arrays split on `,` (no commas inside those tokens).
# strsplit drops TRAILING empty strings (a trailing "" value), so the parts
# are right-padded back to the expected count.

# Serialize a vector (no NAs) to per-element JSON literals. jsonlite owns
# every token: its formatter and parser are self-consistent, so a value it
# writes at digits = 17 it also reads back to the identical double (an
# important property for extreme magnitudes a hand-rolled sprintf cannot
# guarantee). digits = I(17) is the round-trip precision for IEEE doubles
# (digits = NA delegates to R's 15-digit default, which loses the last ulp:
# 0.1 + 0.2 came back 0.3). The exact 16th/17th digit of an extreme value
# can differ across platforms, so the byte-golden tests pin only clean
# clinical data; the edge values are checked by round-trip equality instead.
#' @noRd
.json_array_literals <- function(v, quoted) {
  n <- length(v)
  if (!n) {
    return(character(0))
  }
  s <- as.character(jsonlite::toJSON(
    v,
    auto_unbox = FALSE,
    na = "null",
    digits = I(17)
  ))
  if (quoted) {
    inner <- substr(s, 3L, nchar(s) - 2L) # strip [" and "]
    parts <- strsplit(inner, "\",\"", fixed = TRUE)[[1L]]
    if (length(parts) < n) {
      parts <- c(parts, rep("", n - length(parts)))
    }
    paste0("\"", parts, "\"")
  } else {
    inner <- substr(s, 2L, nchar(s) - 1L) # strip [ and ]
    parts <- strsplit(inner, ",", fixed = TRUE)[[1L]]
    if (length(parts) < n) {
      parts <- c(parts, rep("", n - length(parts)))
    }
    parts
  }
}

# One column to a character(n) of JSON tokens, dispatched off the META
# dataType (not the R class, plan C1): a conformed `decimal` is character but
# emits as a JSON string, a `boolean` is logical and emits true/false.
# NaN/Inf are not valid CDISC numerics and abort loudly (plan C2).
#' @noRd
.json_col_literals <- function(col, cm, nm, call) {
  dt <- if (!is.null(cm)) cm$dataType else .infer_frame_type(col)$data_type
  tgt <- if (!is.null(cm)) cm$targetDataType else NULL
  disp <- if (!is.null(cm)) cm$displayFormat else NULL
  out <- rep("null", length(col))

  fill <- function(v, quoted, na_extra = NULL) {
    keep <- !is.na(v)
    if (!is.null(na_extra)) {
      keep <- keep & !na_extra
    }
    if (any(keep)) {
      out[keep] <- .json_array_literals(v[keep], quoted)
    }
    out
  }

  # Whole-number JSON literals for an integer dataType. Values inside R's
  # 32-bit range emit byte-identically to the former as.integer() path; a
  # larger integer (Dataset-JSON permits arbitrary precision) is written via
  # %.0f instead of being silently NA'd by as.integer() overflow.
  fill_int <- function(num) {
    res <- rep("null", length(num))
    keep <- !is.na(num)
    if (any(keep)) {
      v <- num[keep]
      small <- abs(v) <= .Machine$integer.max
      tok <- character(length(v))
      tok[small] <- as.character(as.integer(v[small]))
      tok[!small] <- sprintf("%.0f", v[!small])
      res[keep] <- tok
    }
    res
  }

  if (dt %in% c("date", "datetime", "time")) {
    if (identical(tgt, "integer")) {
      num <- .deflate_temporal(col, dt, var = nm, call = call)
      return(fill(num, quoted = FALSE))
    }
    return(fill(.temporal_to_iso(col, dt, disp), quoted = TRUE))
  }

  switch(
    dt,
    string = ,
    URI = fill(as.character(col), quoted = TRUE, na_extra = is.na(col)),
    decimal = {
      # Exchanged as a JSON string to preserve exact precision. When the
      # column is still numeric (an unconformed frame), format at round-trip
      # precision; as.character() would drop the last ulp.
      if (is.numeric(col)) {
        .reject_nonfinite_json(col, nm, call)
      }
      fill(.double_to_string(col), quoted = TRUE, na_extra = is.na(col))
    },
    integer = {
      num <- as.numeric(col)
      .reject_nonfinite_json(num, nm, call)
      fill_int(num)
    },
    boolean = fill(as.logical(col), quoted = FALSE, na_extra = is.na(col)),
    float = ,
    double = {
      num <- as.numeric(col)
      .reject_nonfinite_json(num, nm, call)
      fill(num, quoted = FALSE)
    },
    fill(as.character(col), quoted = TRUE, na_extra = is.na(col))
  )
}

# NaN and infinite values are not valid CDISC Dataset-JSON numerics; reject
# them loudly (shared by the integer/decimal/float/double branches) so they
# never reach the file as a `null` or an invalid bare "Inf" token.
#' @noRd
.reject_nonfinite_json <- function(num, nm, call) {
  bad <- is.nan(num) | is.infinite(num)
  if (any(bad)) {
    offenders <- utils::head(unique(as.character(num[bad])), 3L)
    .artoo_abort(
      c(
        "Column {.var {nm}} contains {.val {offenders}}.",
        "x" = "NaN and infinite values are not valid in CDISC Dataset-JSON.",
        "i" = "Recode them to NA, or use a string dataType."
      ),
      kind = "type",
      call = call
    )
  }
  invisible(num)
}

# The shared strict-mode gate of the json/ndjson writers: collect the
# special-missing tags, and under `strict = TRUE` suppress every `_artoo`
# extension with one loss warning naming exactly what is dropped. Returns the
# `special` list to pass to .meta_payload() (NULL under strict).
#' @noRd
.json_prepare_special <- function(x, meta, strict, path, call) {
  special <- .collect_special_missings(x)
  if (!isTRUE(strict)) {
    return(special)
  }
  dropped <- character(0)
  if (length(special)) {
    dropped <- c(dropped, "special missing tags (.A-.Z)")
  }
  if (!is.null(meta@dataset$encoding)) {
    dropped <- c(dropped, "the recorded source encoding")
  }
  if (any(vapply(meta@columns, function(c) !is.null(c$informat), logical(1)))) {
    dropped <- c(dropped, "informats")
  }
  if (length(dropped)) {
    .artoo_warn(
      c(
        "strict = TRUE drops artoo extensions from {.path {path}}.",
        "x" = "Not carried: {dropped}.",
        "i" = "Write with strict = FALSE to keep them in the _artoo block."
      ),
      kind = "codec",
      call = call
    )
  }
  NULL
}

# Rows-per-slab for the streaming writers. An option so tests can force the
# multi-slab path on small frames; 100k rows keeps a wide ADaM slab in the
# tens of MB.
#' @noRd
.json_slab_rows <- function() {
  max(1L, as.integer(getOption("artoo.json_slab_rows", 100000L)))
}

# Stream the `rows` of `x` to an open connection, one slab at a time:
# `prefix` before the first row of each emitted chunk handles the
# between-slab comma; `wrap` lets the file codec emit `[r1],[r2]` joined by
# commas while NDJSON emits one row per line. Returns invisibly.
#' @noRd
.json_stream_rows <- function(x, meta, con, call, sep = ",", progress = FALSE) {
  nr <- nrow(x)
  if (nr == 0L) {
    return(invisible(NULL))
  }
  nms <- names(x)
  has_meta <- is_artoo_meta(meta)
  slab <- .json_slab_rows()
  starts <- seq.int(1L, nr, by = slab)
  pb <- NULL
  if (progress && length(starts) > 1L) {
    pb <- cli::cli_progress_bar(
      "Writing rows",
      total = length(starts),
      .envir = environment()
    )
  }
  first <- TRUE
  for (s in starts) {
    idx <- s:min(s + slab - 1L, nr)
    lits <- lapply(nms, function(nm) {
      cm <- if (has_meta) meta@columns[[nm]] else NULL
      .json_col_literals(x[[nm]][idx], cm, nm, call)
    })
    rows_txt <- paste0("[", do.call(paste, c(lits, sep = ",")), "]")
    chunk <- paste0(rows_txt, collapse = sep)
    if (!first) {
      writeBin(charToRaw(sep), con)
    }
    writeBin(charToRaw(enc2utf8(chunk)), con)
    first <- FALSE
    if (!is.null(pb)) {
      cli::cli_progress_update(id = pb, .envir = environment())
    }
  }
  if (!is.null(pb)) {
    cli::cli_progress_done(id = pb, .envir = environment())
  }
  invisible(NULL)
}

# The metadata head as raw UTF-8 bytes (one toJSON of the payload object).
#' @noRd
.json_head_raw <- function(obj) {
  charToRaw(enc2utf8(as.character(jsonlite::toJSON(
    obj,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = I(17)
  ))))
}

# Open the (atomic-write) output connection: gzip when the final target path
# ends in .gz, plain binary otherwise.
#' @noRd
.json_out_con <- function(tmp, path) {
  if (grepl("\\.gz$", path, ignore.case = TRUE)) {
    gzfile(tmp, "wb")
  } else {
    file(tmp, "wb")
  }
}

# Read a whole file as raw bytes, transparently inflating gzip (magic
# 0x1F 0x8B) so `.json.gz` / `.ndjson.gz` read through the same text path.
#' @noRd
.read_maybe_gz <- function(path) {
  head2 <- readBin(path, what = "raw", n = 2L)
  if (
    length(head2) == 2L &&
      head2[1L] == as.raw(0x1F) &&
      head2[2L] == as.raw(0x8B)
  ) {
    con <- gzfile(path, "rb")
    on.exit(close(con), add = TRUE)
    chunks <- list()
    repeat {
      b <- readBin(con, what = "raw", n = 1048576L)
      if (!length(b)) {
        break
      }
      chunks[[length(chunks) + 1L]] <- b
    }
    return(do.call(c, chunks))
  }
  readBin(path, what = "raw", n = file.info(path)$size)
}
