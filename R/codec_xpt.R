# codec_xpt.R -- the SAS XPORT (xpt) codec, v5 (FDA submission default) and
# v8 (extended names/labels). Writes are single-member (one dataset = one
# file, the FDA convention); reads handle multi-member libraries via
# xpt_members() + read_xpt(member =).
#
# The XPORT framing (LIBRARY/MEMBER/NAMESTR/OBS headers, the 140-byte namestr,
# and the v8 LABELV8 long-name/long-label extension) is built from the SAS
# XPORT v5/v8 transport spec. All metadata flows through the artoo_meta spine
# -- the codec never reads or writes raw column attributes -- and all
# transcoding goes through encoding.R. The byte/float/temporal mechanics reuse
# the existing building blocks (xpt_ieee.R, xpt_util.R, artoo_temporal.R).
#
# Honesty contracts (see write_xpt/read_xpt @details):
#  - C3: an .xpt file's NAMESTR holds only name/label/length/format. CDISC
#    metadata beyond that (keySequence, codelist, origin, targetDataType, ...)
#    and the source encoding are NOT representable in the .xpt bytes; they ride
#    the live in-session artoo_meta (and the sidecar in other containers).
#  - C4: "" and NA_character_ are physically identical in XPORT (both blanks);
#    a genuine empty string reads back as NA. Trailing spaces are likewise not
#    recoverable.
#  - C5: SAS per-variable transcode=NO has no NAMESTR field, so artoo cannot
#    detect it; every character column is transcoded uniformly.

# A stable token in place of the host OS name, so byte output is reproducible
# across machines (SAS readers treat this field as informational).
.xpt_os_token <- "R"

# IBM-370 double magnitude ceiling (16^63); a finite value at or above this
# overflows the format. The codec aborts loudly rather than relying on
# .ieee_to_ibm()'s silent overflow-to-missing mapping.
.xpt_ibm_max <- 16^63

# CDISC dataType -> SAS variable type: 1 numeric, 2 character. Dispatched off
# the META dataType, never is.character(col): a conformed `decimal` is an R
# character vector and a `boolean` is logical, yet both store as SAS numerics.
#' @noRd
.xpt_vartype <- function(data_type) {
  if (data_type %in% c("string", "URI")) 2L else 1L
}

# Reconstruct a SAS format string from a namestr's name/length/decimals.
#' @noRd
.xpt_format_string <- function(name, len, dec) {
  if (!nzchar(name) && len == 0L && dec == 0L) {
    return("")
  }
  out <- name
  if (len > 0L) {
    out <- paste0(out, len)
  }
  out <- paste0(out, ".")
  if (dec > 0L) {
    out <- paste0(out, dec)
  }
  out
}

# ---- header builders --------------------------------------------------------

#' @noRd
.xpt_library_header <- function(version, created) {
  rec1 <- if (version == 5L) {
    .str_to_raw(
      "HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!000000000000000000000000000000",
      80L
    )
  } else {
    .str_to_raw(
      "HEADER RECORD*******LIBV8   HEADER RECORD!!!!!!!000000000000000000000000000000",
      80L
    )
  }
  os_id <- .pad_to(.xpt_os_token, 8L)
  dt <- .sas_datetime_str(created)
  rec2 <- .str_to_raw(
    paste0("SAS     SAS     SASLIB  9.4     ", os_id, strrep(" ", 24L), dt),
    80L
  )
  rec3 <- .str_to_raw(dt, 80L)
  c(rec1, rec2, rec3)
}

#' @noRd
.xpt_member_header <- function(name, label, nvars, version, created) {
  os_id <- .pad_to(.xpt_os_token, 8L)
  dt <- .sas_datetime_str(created)
  if (version == 5L) {
    rec1 <- .str_to_raw(
      "HEADER RECORD*******MEMBER  HEADER RECORD!!!!!!!000000000000000001600000000140",
      80L
    )
    rec2 <- .str_to_raw(
      "HEADER RECORD*******DSCRPTR HEADER RECORD!!!!!!!000000000000000000000000000000",
      80L
    )
    ds_name <- .pad_to(toupper(substr(name, 1L, 8L)), 8L)
    rec3 <- .str_to_raw(
      paste0(
        "SAS     ",
        ds_name,
        "SASDATA 9.4     ",
        os_id,
        strrep(" ", 24L),
        dt
      ),
      80L
    )
    nvars_str <- formatC(nvars, width = 4L, format = "d", flag = "0")
    rec5 <- .str_to_raw(
      paste0(
        "HEADER RECORD*******NAMESTR HEADER RECORD!!!!!!!000000",
        nvars_str,
        "0000000000000000000000"
      ),
      80L
    )
  } else {
    rec1 <- .str_to_raw(
      "HEADER RECORD*******MEMBV8  HEADER RECORD!!!!!!!000000000000000001600000000140",
      80L
    )
    rec2 <- .str_to_raw(
      "HEADER RECORD*******DSCPTV8 HEADER RECORD!!!!!!!000000000000000000000000000000",
      80L
    )
    ds_name <- .pad_to(substr(name, 1L, 32L), 32L)
    rec3 <- .str_to_raw(
      paste0("SAS     ", ds_name, "SASDATA 9.4     ", os_id, dt),
      80L
    )
    nvars_str <- formatC(nvars, width = 6L, format = "d", flag = "0")
    rec5 <- .str_to_raw(
      paste0(
        "HEADER RECORD*******NAMSTV8 HEADER RECORD!!!!!!!0000",
        nvars_str,
        "0000000000000000000000"
      ),
      80L
    )
  }
  # rec4 is assembled byte-wise: `label` arrives transcoded (target bytes) and
  # boundary-truncated to <= 40 bytes, so character-counted padding would
  # misalign every record after it for a multibyte label.
  rec4 <- c(
    charToRaw(paste0(dt, strrep(" ", 16L))),
    .str_to_raw_bytes(label, 40L),
    .str_to_raw("DATA", 8L)
  )
  c(rec1, rec2, rec3, rec4, rec5)
}

# One 140-byte NAMESTR record. The 40-byte label is byte-packed (it may carry
# transcoded text); name/format fields are ASCII.
#' @noRd
.xpt_namestr <- function(r, varnum, npos, version) {
  just <- if (r$vartype == 1L) 1L else 0L
  buf <- c(
    .int_to_pib2(r$vartype),
    as.raw(c(0x00, 0x00)),
    .int_to_pib2(r$length),
    .int_to_pib2(varnum),
    .str_to_raw(r$name, 8L),
    .str_to_raw_bytes(r$label_ns %||% r$label, 40L),
    .str_to_raw(r$format_name, 8L),
    .int_to_pib2(r$formatl),
    .int_to_pib2(r$formatd),
    .int_to_pib2(just),
    as.raw(c(0x00, 0x00)),
    # niform / nifl / nifd: the SAS informat (how to read the field back in),
    # bytes 73-84. Carried so a real SAS file round-trips its input spec.
    .str_to_raw(r$informat_name %||% "", 8L),
    .int_to_pib2(r$informatl %||% 0L),
    .int_to_pib2(r$informatd %||% 0L),
    .int_to_pib4(npos)
  )
  if (version == 5L) {
    c(buf, raw(52L))
  } else {
    c(
      buf,
      .str_to_raw(r$name, 32L),
      .int_to_pib2(length(charToRaw(r$label))),
      .int_to_pib2(nchar(r$format_name)),
      .int_to_pib2(nchar(r$informat_name %||% "")),
      raw(14L)
    )
  }
}

#' @noRd
.xpt_namestr_block <- function(recs, version) {
  npos <- 0L
  parts <- vector("list", length(recs))
  for (i in seq_along(recs)) {
    parts[[i]] <- .xpt_namestr(recs[[i]], i, npos, version)
    npos <- npos + recs[[i]]$length
  }
  .pad_record(if (length(parts)) unlist(parts) else raw(0), 80L)
}

# v8 LABELV8 records carry full names (> 8) / labels (> 40); v5 returns nothing.
#' @noRd
.xpt_label_extension <- function(recs, version) {
  if (version == 5L) {
    return(raw(0))
  }
  needs <- vapply(
    recs,
    function(r) nchar(r$name) > 8L || length(charToRaw(r$label)) > 40L,
    logical(1)
  )
  n_ext <- sum(needs)
  if (n_ext == 0L) {
    return(raw(0))
  }
  header <- .str_to_raw(
    paste0(
      "HEADER RECORD*******",
      .pad_to("LABELV8", 7L),
      " HEADER RECORD!!!!!!!",
      formatC(n_ext, width = 30L, format = "d", flag = " ")
    ),
    80L
  )
  chunks <- list()
  for (i in seq_along(recs)) {
    if (!needs[i]) {
      next
    }
    name_raw <- charToRaw(recs[[i]]$name)
    label_raw <- charToRaw(recs[[i]]$label)
    chunks[[length(chunks) + 1L]] <- c(
      .int_to_pib2(i),
      .int_to_pib2(length(name_raw)),
      .int_to_pib2(length(label_raw)),
      name_raw,
      label_raw
    )
  }
  c(header, .pad_record(unlist(chunks), 80L))
}

#' @noRd
.xpt_obs_header <- function(nobs, version) {
  if (version == 5L) {
    .str_to_raw(
      paste0(
        "HEADER RECORD*******OBS     HEADER RECORD!!!!!!!",
        strrep("0", 32L)
      ),
      80L
    )
  } else {
    nobs_str <- formatC(nobs, width = 15L, format = "d", flag = " ")
    .str_to_raw(
      paste0(
        "HEADER RECORD*******OBSV8   HEADER RECORD!!!!!!!",
        nobs_str,
        strrep(" ", 17L)
      ),
      80L
    )
  }
}

# Strided assembly of the fixed-width OBS section, padded to 80 bytes. Each
# column's bytes are placed at its offset within every record.
#' @noRd
.xpt_obs_buffer <- function(recs, nobs, obs_length) {
  buf <- raw(obs_length * nobs)
  col_offset <- 0L
  for (r in recs) {
    len <- r$length
    row_starts <- seq(col_offset + 1L, by = obs_length, length.out = nobs)
    dest <- rep(row_starts, each = len) + rep.int(0L:(len - 1L), nobs)
    buf[dest] <- r$bytes
    col_offset <- col_offset + len
  }
  .pad_record(buf, 80L)
}

# ---- encode -----------------------------------------------------------------

# Build one per-column record (namestr fields + packed bytes) from the column
# and its meta. dataType drives vartype; numerics write nlng = 8 (F2);
# characters are transcoded then byte-packed to max(declared, max byte length)
# so data is never silently truncated (F1).
#' @noRd
.xpt_encode_columns <- function(
  x,
  meta,
  target_enc,
  on_invalid,
  version,
  call
) {
  nms <- names(x)
  nobs <- nrow(x)
  has_meta <- is_artoo_meta(meta)
  label_trunc <- character(0)
  # FDA TCG bytes 160-191 are only meaningful on a single-byte stream; on
  # UTF-8 those values are multibyte continuation bytes and would false-fire.
  target_cs <- .resolve_charset(target_enc, call)
  fda_check <- !identical(toupper(target_cs), "UTF-8")
  fda_cols <- character(0)
  recs <- vector("list", length(nms))
  for (i in seq_along(nms)) {
    nm <- nms[i]
    col <- x[[nm]]
    cm <- if (has_meta) meta@columns[[nm]] else NULL

    if (is.factor(col)) {
      .artoo_abort(
        c(
          "Column {.var {nm}} is a factor.",
          "i" = "Convert it with {.fn as.character} before writing."
        ),
        kind = "type",
        call = call
      )
    }
    if (is.list(col)) {
      .artoo_abort(
        c(
          "Column {.var {nm}} is a list column.",
          "i" = "xpt cannot store list columns."
        ),
        kind = "type",
        call = call
      )
    }

    dt <- if (!is.null(cm)) cm$dataType else .infer_frame_type(col)$data_type
    raw_label <- if (!is.null(cm)) {
      cm$label %||% ""
    } else {
      la <- attr(col, "label", exact = TRUE)
      if (is.null(la)) "" else as.character(la)
    }
    # A character date/datetime/time column with no numeric targetDataType
    # is ISO 8601 text -- the CDISC --DTC convention (partial dates like
    # "1951" and "1951-12" included). It stores as a character variable;
    # the SAS-numeric path below is reserved for columns whose metadata
    # (targetDataType) or R class (Date/POSIXct/hms/numeric) is
    # numeric-backed.
    tdt <- if (!is.null(cm)) cm$targetDataType else NULL
    iso_text <- dt %in%
      c("date", "datetime", "time") &&
      is.character(col) &&
      is.null(tdt)
    display <- if (!is.null(cm)) cm$displayFormat else NULL
    display <- if (iso_text) {
      # A SAS temporal format (DATE9.) on a character variable would be
      # wrong; keep only an explicit character format ($...), else none.
      if (!is.null(display) && grepl("^\\$", display)) display else NA
    } else {
      .resolve_display_format(dt, if (is.null(display)) NA else display)
    }
    vtype <- if (iso_text) 2L else .xpt_vartype(dt)
    # Labels are metadata; transcode with "replace" so a stray glyph never
    # aborts a write. The namestr field holds at most 40 bytes; truncate on a
    # character boundary so a multibyte character is never split (the full
    # label still rides the v8 LABELV8 extension).
    label_t <- .to_target(raw_label, target_enc, "replace", call)
    label_ns <- .trunc_bytes_boundary(label_t, target_enc, 40L)

    if (vtype == 1L) {
      tag <- attr(col, "sas_missing", exact = TRUE)
      # The coercion-loss guard below reports failures with a precise message,
      # so suppress base R's generic "NAs introduced by coercion" warning.
      num <- suppressWarnings(.deflate_temporal(col, dt, var = nm, call = call))
      # A blank/whitespace-only string in a character-backed numeric (decimal)
      # is an intended missing, not a coercion failure -> write SAS missing.
      blank <- is.character(col) & !is.na(col) & !nzchar(trimws(col))
      lost <- is.na(num) & !is.na(col) & !blank
      if (any(lost)) {
        bad <- utils::head(unique(as.character(col[lost])), 3L)
        .artoo_abort(
          c(
            "Cannot coerce column {.var {nm}} to numeric for xpt.",
            "x" = "Offending value{?s}: {.val {bad}}.",
            "i" = "The meta types this column numeric; fix the values or the spec dataType."
          ),
          kind = "codec",
          call = call
        )
      }
      # xpt cannot represent infinity; fail loud rather than silently writing a
      # SAS missing (consistent with the finite-overflow guard below).
      if (any(is.infinite(num))) {
        .artoo_abort(
          c(
            "Column {.var {nm}} contains infinite values.",
            "i" = "xpt cannot represent infinity; remove or recode them first."
          ),
          kind = "codec",
          call = call
        )
      }
      fin <- is.finite(num)
      if (any(abs(num[fin]) >= .xpt_ibm_max)) {
        .artoo_abort(
          c(
            "Column {.var {nm}} exceeds the IBM-370 magnitude limit.",
            "i" = "xpt numerics cap near 7.2e75."
          ),
          kind = "codec",
          call = call
        )
      }
      bytes <- .ieee_to_ibm(num, missing = tag)
      nlng <- 8L
    } else {
      chr <- .to_target(as.character(col), target_enc, on_invalid, call)
      # FDA TCG bans bytes 160-191 in submission xpt. Check the post-transcode
      # single-byte stream (skipped for UTF-8, where those are continuation
      # bytes). Data columns only; one warning after the loop names them all.
      if (fda_check && length(chr)) {
        joined <- paste0(chr[!is.na(chr)], collapse = "")
        if (nzchar(joined) && length(.fda_forbidden_bytes(charToRaw(joined)))) {
          fda_cols <- c(fda_cols, nm)
        }
      }
      bw <- nchar(chr, type = "bytes")
      bw[is.na(chr)] <- 0L
      declared <- if (!is.null(cm) && !is.null(cm$length)) {
        as.integer(cm$length)
      } else {
        0L
      }
      nlng <- max(declared, max(bw, 1L))
      if (version == 5L && nlng > 200L) {
        .artoo_abort(
          c(
            "Column {.var {nm}} needs {nlng} bytes, over the v5 limit of 200.",
            "i" = "Use {.code version = 8} or shorten the data."
          ),
          kind = "codec",
          call = call
        )
      }
      bytes <- .strvec_to_fixed_raw(chr, nlng)
    }

    out_name <- nm
    if (version == 5L) {
      up <- toupper(nm)
      if (!grepl("^[A-Z_][A-Z0-9_]{0,7}$", up)) {
        .artoo_abort(
          c(
            "Variable name {.var {nm}} is not valid for xpt v5.",
            "i" = "v5 names are 1-8 chars of letters, digits, or underscore, not starting with a digit."
          ),
          kind = "codec",
          call = call
        )
      }
      out_name <- up
    }
    if (version == 5L && length(charToRaw(label_t)) > 40L) {
      label_trunc <- c(label_trunc, nm)
    }

    fmt <- .parse_format_str(if (is.na(display)) "" else display)
    inf <- .parse_format_str(
      if (!is.null(cm) && !is.null(cm$informat)) cm$informat else ""
    )
    recs[[i]] <- list(
      name = out_name,
      label = label_t,
      label_ns = label_ns,
      vartype = vtype,
      length = nlng,
      format_name = fmt$name,
      formatl = fmt$length,
      formatd = fmt$decimals,
      informat_name = inf$name,
      informatl = inf$length,
      informatd = inf$decimals,
      bytes = bytes
    )
  }
  if (length(label_trunc)) {
    .artoo_warn(
      c(
        "Truncated {length(label_trunc)} label{?s} to 40 bytes for xpt v5: {.var {label_trunc}}.",
        "i" = "Use {.code version = 8} to keep long labels."
      ),
      kind = "encoding",
      call = call
    )
  }
  if (length(fda_cols)) {
    .artoo_warn(
      c(
        "Wrote bytes 160-191 in {length(fda_cols)} column{?s}: {.var {fda_cols}}.",
        "i" = "The FDA Study Data TCG prohibits these bytes in submission xpt; write with {.code encoding = \"US-ASCII\"} for a submission.",
        "i" = "See https://www.fda.gov/media/153632/download."
      ),
      kind = "encoding",
      call = call
    )
  }
  recs
}

# encode contract: (x, meta, path, <codec args>, call) -> invisible(path).
# No `...`: an unknown argument forwarded by write_dataset() is a loud
# "unused argument" error, never silently swallowed.
#' @noRd
.encode_xpt <- function(
  x,
  meta,
  path,
  version = 5L,
  encoding = NULL,
  on_invalid = "error",
  created = NULL,
  call = rlang::caller_env()
) {
  created <- created %||% Sys.time()
  version <- as.integer(version)
  if (!version %in% c(5L, 8L)) {
    .artoo_abort(
      c(
        "{.arg version} must be 5 or 8.",
        "x" = "You supplied {.val {version}}."
      ),
      kind = "input",
      call = call
    )
  }
  # v5 uppercases every variable name, so two names colliding only in case
  # (age + AGE) would silently overwrite a column. Abort before writing.
  if (version == 5L) {
    dup <- unique(names(x)[duplicated(toupper(names(x)))])
    if (length(dup)) {
      collided <- names(x)[toupper(names(x)) %in% toupper(dup)]
      .artoo_abort(
        c(
          "Variable names collide when uppercased for xpt v5: {.var {collided}}.",
          "i" = "v5 names are case-insensitive; rename or use {.code version = 8}."
        ),
        kind = "codec",
        call = call
      )
    }
  }

  if (is_artoo_meta(meta)) {
    ds_name <- meta@dataset$name %||% "DATA"
    ds_label <- meta@dataset$label %||% ""
    src_enc <- meta@dataset$encoding
  } else {
    ds_name <- "DATA"
    ds_label <- ""
    src_enc <- NULL
  }
  target_enc <- encoding %||% src_enc %||% "UTF-8"
  ds_name <- if (version == 5L) {
    toupper(substr(ds_name, 1L, 8L))
  } else {
    substr(ds_name, 1L, 32L)
  }
  # SAS member names are ASCII letters/digits/underscore; anything else would
  # be packed by character count and corrupt the 80-byte header framing.
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", ds_name)) {
    .artoo_abort(
      c(
        "Dataset name {.val {ds_name}} is not valid for xpt.",
        "i" = "Member names are ASCII letters, digits, or underscore, not starting with a digit."
      ),
      kind = "codec",
      call = call
    )
  }
  # The dataset label is metadata: transcode with "replace" (a stray glyph
  # never aborts a write), then truncate to the 40-byte field on a character
  # boundary. Unlike variable labels, v8 has no long-label extension for it.
  ds_label <- .to_target(ds_label, target_enc, "replace", call)
  ds_label40 <- .trunc_bytes_boundary(ds_label, target_enc, 40L)
  if (!identical(ds_label40, ds_label)) {
    .artoo_warn(
      c(
        "Truncated the dataset label to 40 bytes for xpt.",
        "i" = "XPORT stores at most 40 bytes of dataset label."
      ),
      kind = "encoding",
      call = call
    )
  }
  ds_label <- ds_label40

  recs <- .xpt_encode_columns(x, meta, target_enc, on_invalid, version, call)
  nvars <- length(recs)
  nobs <- nrow(x)
  obs_length <- if (nvars) {
    sum(vapply(recs, function(r) r$length, integer(1)))
  } else {
    0L
  }

  # v5 records no row count: the reader recovers it by trimming trailing
  # all-blank records (padding). In an all-character frame a genuine trailing
  # all-blank row is indistinguishable from that padding, so it cannot be read
  # back. v8 stores the count and is exempt. Warn at write time (see C4).
  if (
    version == 5L &&
      nvars > 0L &&
      nobs > 0L &&
      all(vapply(recs, function(r) r$vartype == 2L, logical(1)))
  ) {
    last_blank <- all(vapply(
      seq_len(nvars),
      function(j) {
        v <- x[[j]][[nobs]]
        is.na(v) || !nzchar(trimws(as.character(v)))
      },
      logical(1)
    ))
    if (last_blank) {
      .artoo_warn(
        c(
          "The final row of this all-character v5 frame is entirely blank.",
          "x" = "v5 cannot distinguish a trailing blank row from padding; it will not read back.",
          "i" = "Use {.code version = 8}, which records the row count."
        ),
        kind = "encoding",
        call = call
      )
    }
  }

  # Atomic write: build in a temp file, then rename over the target so a crash
  # mid-write never corrupts a prior good file. Cleanup runs only on error.
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".xpt.tmp")
  con <- file(tmp, "wb")
  ok <- FALSE
  tryCatch(
    {
      writeBin(.xpt_library_header(version, created), con)
      writeBin(
        .xpt_member_header(ds_name, ds_label, nvars, version, created),
        con
      )
      writeBin(.xpt_namestr_block(recs, version), con)
      ext <- .xpt_label_extension(recs, version)
      if (length(ext)) {
        writeBin(ext, con)
      }
      writeBin(.xpt_obs_header(nobs, version), con)
      if (nobs > 0L && obs_length > 0L) {
        writeBin(.xpt_obs_buffer(recs, nobs, obs_length), con)
      }
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

  .move_into_place(tmp, path, call)
  invisible(path)
}

# ---- parsers ----------------------------------------------------------------

#' @noRd
.xpt_record_str <- function(con, call = rlang::caller_env()) {
  rawToChar(.read_bytes(con, 80L, call))
}

#' @noRd
.xpt_parse_library <- function(con, call = rlang::caller_env()) {
  s <- rawToChar(.read_bytes(con, 80L, call))
  version <- if (grepl("LIBRARY HEADER", s, fixed = TRUE)) {
    5L
  } else if (grepl("LIBV8", s, fixed = TRUE)) {
    8L
  } else {
    .artoo_abort(
      c(
        "Not a valid XPORT transport file.",
        "x" = "Unrecognised library header.",
        "i" = "The file is not SAS XPORT (v5/v8), or was corrupted in transfer; check the source and transfer mode (binary, not text)."
      ),
      kind = "codec",
      call = call
    )
  }
  .read_bytes(con, 80L, call)
  .read_bytes(con, 80L, call)
  list(version = version)
}

#' @noRd
.xpt_parse_member <- function(con, version, call = rlang::caller_env()) {
  s <- rawToChar(.read_bytes(con, 80L, call))
  if (!grepl("MEMBER", s, fixed = TRUE) && !grepl("MEMBV8", s, fixed = TRUE)) {
    .artoo_abort(
      c("Not a valid XPORT member.", "x" = "Missing MEMBER header."),
      kind = "codec",
      call = call
    )
  }
  # The member header records the NAMESTR record size at bytes 75-78 ("0140",
  # or "0136" for the VMS variant). Honor it for the block stride; default to
  # 140 when the field is absent or implausible.
  nstr_size <- suppressWarnings(as.integer(substr(s, 75L, 78L)))
  if (is.na(nstr_size) || nstr_size < 100L || nstr_size > 200L) {
    nstr_size <- 140L
  }
  .read_bytes(con, 80L, call)
  desc1 <- .read_bytes(con, 80L, call)
  desc2 <- .read_bytes(con, 80L, call)
  ds_name <- if (version == 5L) {
    .raw_to_str(desc1[9:16])
  } else {
    .raw_to_str(desc1[9:40])
  }
  ds_label <- .raw_to_str(desc2[33:72])
  namestr_rec <- .xpt_record_str(con, call)
  nvars <- as.integer(suppressWarnings(as.numeric(substr(
    namestr_rec,
    53L,
    58L
  ))))
  if (is.na(nvars) || nvars < 0L) {
    .artoo_abort(
      c(
        "Not a valid XPORT member.",
        "x" = "Could not read the variable count from the NAMESTR header."
      ),
      kind = "codec",
      call = call
    )
  }
  list(
    name = ds_name,
    label = ds_label,
    nvars = nvars,
    namestr_size = nstr_size
  )
}

# `namestr_size` (140, or 136 for VMS) sizes the record; the field offsets at
# 1:88 are identical across sizes. The v8 long-name slice at 89:120 only exists
# in a full 140-byte extended namestr.
#' @noRd
.xpt_parse_namestr <- function(raw140, version, namestr_size = 140L) {
  vartype <- .pib2_to_int(raw140[1:2])
  var_length <- .pib2_to_int(raw140[5:6])
  varnum <- .pib2_to_int(raw140[7:8])
  name <- .raw_to_str(raw140[9:16])
  label <- .raw_to_str(raw140[17:56])
  format_name <- .raw_to_str(raw140[57:64])
  formatl <- .pib2_to_int(raw140[65:66])
  formatd <- .pib2_to_int(raw140[67:68])
  informat_name <- .raw_to_str(raw140[73:80])
  informatl <- .pib2_to_int(raw140[81:82])
  informatd <- .pib2_to_int(raw140[83:84])
  npos <- .pib4_to_int(raw140[85:88])
  if (version == 8L && namestr_size >= 140L) {
    name <- .raw_to_str(raw140[89:120])
  }
  list(
    vartype = vartype,
    length = var_length,
    varnum = varnum,
    name = name,
    label = label,
    format_name = format_name,
    formatl = formatl,
    formatd = formatd,
    informat_name = informat_name,
    informatl = informatl,
    informatd = informatd,
    npos = npos
  )
}

#' @noRd
.xpt_parse_namestr_block <- function(
  con,
  nvars,
  version,
  namestr_size = 140L,
  call = rlang::caller_env()
) {
  total <- nvars * namestr_size
  block <- if (total > 0L) .read_bytes(con, total, call) else raw(0)
  namestrs <- lapply(seq_len(nvars), function(i) {
    off <- (i - 1L) * namestr_size
    .xpt_parse_namestr(
      block[(off + 1L):(off + namestr_size)],
      version,
      namestr_size
    )
  })
  rem <- total %% 80L
  if (rem > 0L) {
    .read_bytes(con, 80L - rem, call)
  }
  namestrs
}

#' @noRd
.xpt_parse_label_extension <- function(
  con,
  rec_str,
  namestrs,
  call = rlang::caller_env()
) {
  ext_type <- if (grepl("LABELV9", rec_str, fixed = TRUE)) {
    "LABELV9"
  } else if (grepl("LABELV8", rec_str, fixed = TRUE)) {
    "LABELV8"
  } else {
    return(namestrs)
  }
  n_ext <- as.integer(suppressWarnings(as.numeric(trimws(substr(
    rec_str,
    49L,
    80L
  )))))
  total <- 0L
  for (i in seq_len(n_ext)) {
    if (ext_type == "LABELV8") {
      hdr <- .read_bytes(con, 6L, call)
      total <- total + 6L
      varnum <- .pib2_to_int(hdr[1:2])
      name_len <- .pib2_to_int(hdr[3:4])
      label_len <- .pib2_to_int(hdr[5:6])
      data_raw <- .read_bytes(con, name_len + label_len, call)
      total <- total + name_len + label_len
      namestrs[[varnum]]$name <- .raw_to_str(data_raw[seq_len(name_len)])
      namestrs[[varnum]]$label <- .raw_to_str(
        data_raw[(name_len + 1L):(name_len + label_len)]
      )
    } else {
      hdr <- .read_bytes(con, 10L, call)
      total <- total + 10L
      varnum <- .pib2_to_int(hdr[1:2])
      name_len <- .pib2_to_int(hdr[3:4])
      label_len <- .pib2_to_int(hdr[5:6])
      fmt_len <- .pib2_to_int(hdr[7:8])
      infmt_len <- .pib2_to_int(hdr[9:10])
      dlen <- name_len + label_len + fmt_len + infmt_len
      data_raw <- .read_bytes(con, dlen, call)
      total <- total + dlen
      pos <- 1L
      namestrs[[varnum]]$name <- .raw_to_str(data_raw[
        pos:(pos + name_len - 1L)
      ])
      pos <- pos + name_len
      if (label_len > 0L) {
        namestrs[[varnum]]$label <- .raw_to_str(
          data_raw[pos:(pos + label_len - 1L)]
        )
        pos <- pos + label_len
      }
      # LABELV9 also carries the full format / informat strings (the NAMESTR
      # fields hold at most 8 name characters); parse and take them as the
      # authoritative values rather than discarding them.
      if (fmt_len > 0L) {
        pf <- .parse_format_str(.raw_to_str(
          data_raw[pos:(pos + fmt_len - 1L)]
        ))
        namestrs[[varnum]]$format_name <- pf$name
        namestrs[[varnum]]$formatl <- pf$length
        namestrs[[varnum]]$formatd <- pf$decimals
        pos <- pos + fmt_len
      }
      if (infmt_len > 0L) {
        pi <- .parse_format_str(.raw_to_str(
          data_raw[pos:(pos + infmt_len - 1L)]
        ))
        namestrs[[varnum]]$informat_name <- pi$name
        namestrs[[varnum]]$informatl <- pi$length
        namestrs[[varnum]]$informatd <- pi$decimals
      }
    }
  }
  rem <- total %% 80L
  if (rem > 0L) {
    .read_bytes(con, 80L - rem, call)
  }
  namestrs
}

#' @noRd
.xpt_parse_obs_header <- function(rec_str, version) {
  if (grepl("OBSV8", rec_str, fixed = TRUE)) {
    s <- trimws(substr(rec_str, 49L, 63L))
    if (nzchar(s)) as.integer(suppressWarnings(as.numeric(s))) else NA_integer_
  } else {
    NA_integer_
  }
}

# The shared multi-member abort: artoo reads one member per call, and a
# silently dropped second member would be silent truncation.
#' @noRd
.xpt_abort_multimember <- function(call) {
  .artoo_abort(
    c(
      "This XPORT file has more than one member.",
      "i" = "Run {.code xpt_members(path)} to list them, then pick one with {.code read_xpt(path, member = ...)}."
    ),
    kind = "codec",
    call = call
  )
}

# v5 stores no obs count: it is the data section after the OBS header, blank-
# padded to an 80-byte boundary. Step back from `end` (the next member's
# offset, or EOF -- the default) over trailing all-0x20 records (the padding)
# to find the row count -- one record read per trailing blank, never the
# whole section, so a partial read (n_max) and a >2GB file both stay bounded.
# The ambiguity is confined to all-character data (a numeric field is never
# all-blank), where a genuine trailing all-NA row is indistinguishable from
# padding -- an inherent v5 limitation (see C4).
#' @noRd
.xpt_compute_v5_nobs <- function(
  con,
  obs_length,
  path,
  end = NULL,
  call = rlang::caller_env()
) {
  start <- seek(con, where = NA)
  end <- end %||% file.info(path)$size
  remaining <- end - start
  if (remaining <= 0 || obs_length == 0L) {
    return(0L)
  }
  # Double arithmetic: remaining can exceed the 2^31 integer limit.
  r <- as.double(remaining) %/% obs_length
  blank <- as.raw(0x20)
  while (r > 0) {
    seek(con, where = start + (r - 1) * as.double(obs_length))
    rec <- readBin(con, what = "raw", n = obs_length)
    if (length(rec) == obs_length && all(rec == blank)) {
      r <- r - 1
    } else {
      break
    }
  }
  # The floor() above drops a tail shorter than one record -- and when
  # records are wide, an ENTIRE small second member can hide inside that
  # floored-off fragment (the in-obs signature scan never sees it, because
  # only r * obs_length bytes are read). Scan the fragment's 80-byte-aligned
  # file offsets for a HEADER signature and abort loud: a silently dropped
  # member is silent truncation.
  tail_start <- start + r * as.double(obs_length)
  if (end > tail_start) {
    sig <- charToRaw("HEADER RECORD*******")
    off <- ceiling(tail_start / 80) * 80
    while (off + length(sig) <= end) {
      seek(con, where = off)
      probe <- readBin(con, what = "raw", n = length(sig))
      if (length(probe) == length(sig) && all(probe == sig)) {
        .xpt_abort_multimember(call)
      }
      off <- off + 80
    }
  }
  seek(con, where = start)
  as.integer(r)
}

# artoo reads single-member transport files only. After the obs section (padded
# to an 80-byte boundary) anything more is a second member; abort -- but only
# when the bytes at that boundary carry a real "HEADER RECORD*******" signature,
# so extra blank padding never triggers a false abort. Leaves con at obs_start.
#' @noRd
.xpt_check_single_member <- function(
  con,
  path,
  obs_start,
  nobs,
  obs_length,
  call = rlang::caller_env()
) {
  if (nobs == 0L || obs_length == 0L) {
    return(invisible(NULL))
  }
  data_bytes <- as.double(nobs) * obs_length
  padded_end <- obs_start + ceiling(data_bytes / 80) * 80
  size <- file.info(path)$size
  if (size > padded_end) {
    seek(con, where = padded_end)
    sig <- readBin(con, what = "raw", n = 80L)
    seek(con, where = obs_start)
    expected <- charToRaw("HEADER RECORD*******")
    if (
      length(sig) >= length(expected) &&
        all(sig[seq_along(expected)] == expected)
    ) {
      .xpt_abort_multimember(call)
    }
  }
  invisible(NULL)
}

# Read the OBS section into a named list of columns. Field slicing is driven by
# the parsed npos/nlng. Numerics are right-zero-padded from nlng (2-8 bytes) to
# 8 before .ibm_to_ieee (real SAS stores high-order bytes only); they carry the
# sas_missing tag. Characters are byte-passthrough strings (converted later).
# Resolve col_select (NULL = all) to variable indices in file order. An
# unknown name is a loud artoo_error_input, never a silent drop.
#' @noRd
.xpt_resolve_col_select <- function(namestrs, col_select, call) {
  if (is.null(col_select)) {
    return(seq_along(namestrs))
  }
  all_names <- vapply(namestrs, function(ns) ns$name, character(1))
  want <- as.character(col_select)
  missing_cols <- setdiff(want, all_names)
  if (length(missing_cols)) {
    .artoo_abort(
      c(
        "Unknown column{?s} in {.arg col_select}: {.val {missing_cols}}.",
        "i" = "The file has {.val {all_names}}."
      ),
      kind = "input",
      call = call
    )
  }
  which(all_names %in% want)
}

# Scan the (over-)read v5 obs bytes for a second member: its HEADER record
# lands at an 80-byte boundary past member 1's padded obs. Pre-filtered on the
# leading 'H' so the boundary walk stays cheap. Skips boundary 1 (member 1's
# first data row).
#' @noRd
.xpt_assert_single_member_v5 <- function(all_data, call) {
  n <- length(all_data)
  sig <- charToRaw("HEADER RECORD*******")
  nb <- length(sig)
  # 80-byte-aligned starts (skipping byte 1, member 1's first row) where the
  # full signature still fits.
  max_start <- n - nb + 1L
  if (max_start < 81L) {
    return(invisible(NULL))
  }
  starts <- seq.int(81L, max_start, by = 80L)
  cand <- starts[all_data[starts] == sig[1L]]
  for (s in cand) {
    if (all(all_data[s:(s + nb - 1L)] == sig)) {
      .xpt_abort_multimember(call)
    }
  }
  invisible(NULL)
}

# `keep` selects which variables to materialize (col_select). Field offsets
# come from each namestr's absolute npos, so the obs bytes are read whole (the
# record interleaves all fields) but only the kept columns become R vectors.
#' @noRd
.xpt_read_obs <- function(
  con,
  namestrs,
  nobs,
  obs_length,
  keep = seq_along(namestrs),
  detect_multimember = FALSE,
  call = rlang::caller_env()
) {
  col_names <- vapply(namestrs, function(ns) ns$name, character(1))
  if (nobs == 0L || obs_length == 0L) {
    cols <- lapply(keep, function(j) {
      if (namestrs[[j]]$vartype == 1L) numeric(0) else character(0)
    })
    names(cols) <- col_names[keep]
    return(cols)
  }
  # Record count times record length can exceed the 2^31 integer limit on a
  # large file; size the read in double arithmetic.
  all_data <- .read_bytes(con, as.double(nobs) * obs_length, call)
  if (detect_multimember) {
    .xpt_assert_single_member_v5(all_data, call)
  }
  raw_mat <- matrix(all_data, nrow = obs_length, ncol = nobs)
  cols <- vector("list", length(keep))
  for (idx in seq_along(keep)) {
    ns <- namestrs[[keep[idx]]]
    rf <- ns$npos + 1L
    rt <- ns$npos + ns$length
    if (ns$vartype == 1L) {
      vr <- raw_mat[rf:rt, , drop = FALSE]
      if (ns$length < 8L) {
        vr <- rbind(vr, matrix(as.raw(0x00), 8L - ns$length, nobs))
      }
      cols[[idx]] <- .ibm_to_ieee(as.vector(vr))
    } else {
      cols[[idx]] <- .raw_mat_to_strvec(raw_mat[rf:rt, , drop = FALSE], NULL)
    }
  }
  names(cols) <- col_names[keep]
  cols
}

# CDISC dataType inferred from a parsed namestr (decode side).
#' @noRd
.xpt_decode_datatype <- function(ns) {
  if (ns$vartype == 2L) {
    return("string")
  }
  fn <- ns$format_name
  if (.is_sas_date_format(fn)) {
    "date"
  } else if (.is_sas_datetime_format(fn)) {
    "datetime"
  } else if (.is_sas_time_format(fn)) {
    "time"
  } else {
    "float"
  }
}

# One meta column entry from a parsed namestr (canonical, NULL-dropped order).
#' @noRd
.meta_col_from_namestr <- function(ns, dataset, dt) {
  disp <- .xpt_format_string(ns$format_name, ns$formatl, ns$formatd)
  infm <- .xpt_format_string(
    ns$informat_name %||% "",
    ns$informatl %||% 0L,
    ns$informatd %||% 0L
  )
  col <- list(
    itemOID = paste0("IT.", dataset, ".", ns$name),
    name = ns$name,
    label = if (nzchar(ns$label)) ns$label else NULL,
    dataType = dt,
    # A numeric SAS temporal IS dataType date/datetime/time with numeric
    # storage -- record targetDataType = "integer" so the next codec (json,
    # parquet) writes the same exchange form and realizes the same R class.
    targetDataType = if (
      ns$vartype == 1L && dt %in% c("date", "datetime", "time")
    ) {
      "integer"
    } else {
      NULL
    },
    length = if (ns$vartype == 2L && ns$length > 0L) {
      as.integer(ns$length)
    } else {
      NULL
    },
    displayFormat = if (nzchar(disp)) disp else NULL,
    informat = if (nzchar(infm)) infm else NULL
  )
  .drop_null(col)
}

# Walk every member of an open transport file (con positioned just after the
# 3-record library header): parse each member's headers, size its obs
# section, and seek past it. v8 records the row count, so the extent is
# arithmetic; v5 does not, so the next member's HEADER signature is found by
# a forward chunk scan and the count derived from the bounded span.
#' @noRd
.xpt_scan_members <- function(con, version, path, call = rlang::caller_env()) {
  size <- file.info(path)$size
  members <- list()
  repeat {
    offset <- seek(con, where = NA)
    if (offset >= size) {
      break
    }
    peek <- readBin(con, what = "raw", n = min(80, size - offset))
    if (length(peek) < 80L || all(peek == as.raw(0x20))) {
      break # trailing padding, not a member
    }
    seek(con, where = offset)
    mem <- .xpt_parse_member(con, version, call)
    namestrs <- .xpt_parse_namestr_block(
      con,
      mem$nvars,
      version,
      mem$namestr_size,
      call
    )
    nxt <- .xpt_record_str(con, call)
    if (
      grepl("LABELV8", nxt, fixed = TRUE) || grepl("LABELV9", nxt, fixed = TRUE)
    ) {
      namestrs <- .xpt_parse_label_extension(con, nxt, namestrs, call)
      nxt <- .xpt_record_str(con, call)
    }
    nobs <- .xpt_parse_obs_header(nxt, version)
    obs_start <- seek(con, where = NA)
    obs_length <- if (length(namestrs)) {
      sum(vapply(namestrs, function(ns) ns$length, integer(1)))
    } else {
      0L
    }
    if (version == 8L && !is.na(nobs)) {
      data_bytes <- as.double(nobs) * obs_length
      obs_end <- min(obs_start + ceiling(data_bytes / 80) * 80, size)
    } else {
      nxt_off <- .xpt_next_member_offset(con, path, obs_start)
      obs_end <- if (is.na(nxt_off)) size else nxt_off
      # The forward scan moved the connection; the nobs walk reads its start
      # position from the connection, so restore it first.
      seek(con, where = obs_start)
      nobs <- .xpt_compute_v5_nobs(con, obs_length, path, end = obs_end)
    }
    members[[length(members) + 1L]] <- list(
      member = length(members) + 1L,
      name = mem$name,
      label = mem$label,
      nvars = mem$nvars,
      nobs = as.integer(nobs),
      offset = offset,
      obs_end = obs_end
    )
    seek(con, where = obs_end)
  }
  if (!length(members)) {
    .artoo_abort(
      c(
        "Not a valid XPORT transport file.",
        "x" = "No member header follows the library header.",
        "i" = "The file is truncated or was corrupted in transfer; re-export or re-transfer it in binary mode."
      ),
      kind = "codec",
      call = call
    )
  }
  members
}

# First 80-aligned offset at/after `from` whose record opens with the HEADER
# signature (the next member), or NA when none. Chunked, so a multi-GB v5
# file is scanned without loading it.
#' @noRd
.xpt_next_member_offset <- function(con, path, from) {
  sig <- charToRaw("HEADER RECORD*******")
  size <- file.info(path)$size
  chunk <- 81920L # 1024 records per read
  pos <- from
  while (pos < size) {
    seek(con, where = pos)
    bytes <- readBin(con, what = "raw", n = min(chunk, size - pos))
    nrec <- length(bytes) %/% 80L
    if (nrec == 0L) {
      break
    }
    starts <- seq.int(1L, by = 80L, length.out = nrec)
    cand <- starts[bytes[starts] == sig[1L]]
    for (s in cand) {
      if (s + 19L <= length(bytes) && all(bytes[s:(s + 19L)] == sig)) {
        return(pos + s - 1)
      }
    }
    pos <- pos + nrec * 80L
  }
  NA_real_
}

# Resolve a `member` selector (1-based index, or case-insensitive name) to a
# member list index; unknown selectors error listing what the file has.
#' @noRd
.xpt_resolve_member <- function(members, member, call = rlang::caller_env()) {
  nms <- vapply(members, function(m) m$name, character(1))
  if (is.numeric(member) && length(member) == 1L && !is.na(member)) {
    i <- as.integer(member)
    if (i >= 1L && i <= length(members)) {
      return(i)
    }
    .artoo_abort(
      c(
        "{.arg member} index {.val {i}} is out of range.",
        "i" = "The file has {length(members)} member{?s}: {.val {nms}}."
      ),
      kind = "input",
      call = call
    )
  }
  if (is.character(member) && length(member) == 1L && !is.na(member)) {
    i <- match(toupper(member), toupper(nms))
    if (!is.na(i)) {
      return(i)
    }
    .artoo_abort(
      c(
        "Unknown member {.val {member}}.",
        "i" = "The file has: {.val {nms}}."
      ),
      kind = "input",
      call = call
    )
  }
  .artoo_abort(
    c(
      "{.arg member} must be a single member name or index.",
      "x" = "You supplied {.obj_type_friendly {member}}."
    ),
    kind = "input",
    call = call
  )
}

# decode contract: (path, <codec args>, call) -> list(data, meta). A NULL
# `member` is the single-member fast path (aborts on a multi-member file);
# otherwise the file is scanned and the chosen member decoded in place.
#' @noRd
.decode_xpt <- function(
  path,
  encoding = NULL,
  col_select = NULL,
  n_max = Inf,
  member = NULL,
  call = rlang::caller_env()
) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)

  lib <- .xpt_parse_library(con, call)
  version <- lib$version
  if (is.null(member)) {
    return(.xpt_decode_member(
      con,
      version,
      path,
      encoding,
      col_select,
      n_max,
      call = call
    ))
  }
  members <- .xpt_scan_members(con, version, path, call)
  m <- members[[.xpt_resolve_member(members, member, call)]]
  seek(con, where = m$offset)
  .xpt_decode_member(
    con,
    version,
    path,
    encoding,
    col_select,
    n_max,
    obs_end = m$obs_end,
    call = call
  )
}

# Decode ONE member from `con` (positioned at its MEMBER header). With
# `obs_end` NA (the single-member path) the obs extent is EOF-derived and the
# multi-member guards run; a known `obs_end` bounds every read to the member.
#' @noRd
.xpt_decode_member <- function(
  con,
  version,
  path,
  encoding = NULL,
  col_select = NULL,
  n_max = Inf,
  obs_end = NA_real_,
  call = rlang::caller_env()
) {
  mem <- .xpt_parse_member(con, version, call)
  namestrs <- .xpt_parse_namestr_block(
    con,
    mem$nvars,
    version,
    mem$namestr_size,
    call
  )

  nxt <- .xpt_record_str(con, call)
  if (
    grepl("LABELV8", nxt, fixed = TRUE) || grepl("LABELV9", nxt, fixed = TRUE)
  ) {
    namestrs <- .xpt_parse_label_extension(con, nxt, namestrs, call)
    nxt <- .xpt_record_str(con, call)
  }

  # Resolve col_select to variable indices, file order preserved.
  keep <- .xpt_resolve_col_select(namestrs, col_select, call)

  nobs <- .xpt_parse_obs_header(nxt, version)
  obs_length <- if (length(namestrs)) {
    sum(vapply(namestrs, function(ns) ns$length, integer(1)))
  } else {
    0L
  }
  if (is.na(nobs)) {
    nobs <- .xpt_compute_v5_nobs(
      con,
      obs_length,
      path,
      end = if (is.na(obs_end)) NULL else obs_end,
      call = call
    )
  }
  # Multi-member detection (single-member path only; a known obs_end means
  # the member was already scanned and bounded). v8 records the exact row
  # count, so a second member is the bytes beyond the padded obs section --
  # check that boundary. v5's count is EOF-derived, so a second member is
  # absorbed into the (inflated) count and the read bytes themselves carry
  # its HEADER signature at an 80-byte boundary -- scanned inside
  # .xpt_read_obs (no extra IO, n_max-bound).
  obs_start <- seek(con, where = NA)
  if (version == 8L && is.na(obs_end)) {
    .xpt_check_single_member(con, path, obs_start, nobs, obs_length, call)
  }
  if (is.finite(n_max)) {
    nobs <- min(nobs, max(as.integer(n_max), 0L))
  }
  cols <- .xpt_read_obs(
    con,
    namestrs,
    nobs,
    obs_length,
    keep,
    detect_multimember = version == 5L && is.na(obs_end),
    call = call
  )
  # Downstream loops (transcode, realize, meta) align 1:1 with the kept cols.
  namestrs <- namestrs[keep]

  char_idx <- which(vapply(namestrs, function(ns) ns$vartype == 2L, logical(1)))
  # Header text (dataset label, variable labels) is byte-passthrough until
  # here; it joins the detection scan -- labels can be the only non-ASCII
  # content in a file -- and is transcoded below like the data columns.
  hdr_text <- c(
    mem$label,
    vapply(namestrs, function(ns) ns$label, character(1))
  )
  resolved_enc <- if (!is.null(encoding)) {
    encoding
  } else {
    valid <- !any(!validUTF8(hdr_text))
    if (valid) {
      for (j in char_idx) {
        v <- cols[[j]]
        if (length(v) && any(!validUTF8(v))) {
          valid <- FALSE
          break
        }
      }
    }
    if (valid) "UTF-8" else "WINDOWS-1252"
  }
  for (j in char_idx) {
    v <- cols[[j]]
    blanks <- is.na(v) | !nzchar(v)
    v <- .to_internal(v, resolved_enc)
    v[blanks] <- NA_character_
    cols[[j]] <- v
  }
  mem$label <- .to_internal(mem$label, resolved_enc)
  for (j in seq_along(namestrs)) {
    namestrs[[j]]$label <- .to_internal(namestrs[[j]]$label, resolved_enc)
  }

  cols_meta <- vector("list", length(namestrs))
  for (j in seq_along(namestrs)) {
    ns <- namestrs[[j]]
    dt <- .xpt_decode_datatype(ns)
    if (ns$vartype == 1L && dt %in% c("date", "datetime", "time")) {
      disp <- .xpt_format_string(ns$format_name, ns$formatl, ns$formatd)
      # Realizing rebuilds the vector; carry the special-missing tags across
      # so a second write does not degrade .A-.Z/._ to plain missing.
      tag <- attr(cols[[j]], "sas_missing", exact = TRUE)
      cols[[j]] <- .realize_temporal(cols[[j]], dt, disp)
      if (!is.null(tag)) {
        attr(cols[[j]], "sas_missing") <- tag
      }
    }
    cols_meta[[j]] <- .meta_col_from_namestr(ns, mem$name, dt)
  }
  col_names <- vapply(namestrs, function(ns) ns$name, character(1))
  names(cols) <- col_names
  names(cols_meta) <- col_names

  df <- structure(
    cols,
    names = col_names,
    row.names = .set_row_names(max(as.integer(nobs), 0L)),
    class = "data.frame"
  )

  ds_meta <- .assemble_dataset_meta(
    itemGroupOID = paste0("IG.", mem$name),
    name = mem$name,
    label = if (nzchar(mem$label)) mem$label else NULL,
    records = as.integer(nobs),
    encoding = resolved_enc,
    keys = .meta_keys(cols_meta)
  )
  meta <- artoo_meta_class(dataset = ds_meta, columns = cols_meta)
  list(data = df, meta = meta)
}

# ---- exported wrappers ------------------------------------------------------

#' Write a dataset to SAS XPORT
#'
#' Serialize a data frame to a SAS Transport (`.xpt`) file in v5 (the FDA
#' submission standard) or v8 (extended names and labels), preserving the
#' `artoo_meta` a column can hold. The emit end of the artoo workflow
#' (spec -> apply_spec -> write_xpt); a thin wrapper over [write_dataset()]
#' with `format = "xpt"`.
#'
#' @details
#' **What XPORT can carry.** An `.xpt` file's NAMESTR stores only variable
#' name, label, length, and SAS format. CDISC metadata beyond that
#' (keySequence, codelist, origin, targetDataType, ...) and the source
#' encoding are not representable in the bytes; they ride the in-session
#' `artoo_meta` and the sidecar in self-describing formats (Dataset-JSON,
#' Parquet, rds). XPORT also cannot distinguish an empty string from `NA`
#' (both store as blanks) and drops trailing spaces.
#'
#' **Character ISO dates (`--DTC`) write as text.** A character column whose
#' `dataType` is `date`/`datetime`/`time` with no numeric `targetDataType` is
#' the CDISC ISO 8601 text form -- the SDTM `--DTC` convention -- and stores
#' as a character variable, partial dates (`"1951"`, `"1951-12"`) included,
#' byte for byte. The SAS-numeric encoding (with `DATE9.`-style formats) is
#' used for columns that are R `Date`/`POSIXct`/`hms` or whose
#' metadata records `targetDataType = "integer"` (the ADaM numeric-date
#' convention). A character column *under* `targetDataType = "integer"`
#' aborts loudly -- a partial date can never become a SAS numeric silently.
#'
#' @param x *The dataset to write.* `<data.frame>: required`. Typically the
#'   output of [apply_spec()], carrying `artoo_meta`.
#' @param path *Destination `.xpt` path.* `<character(1)>: required`.
#' @param version *XPORT transport version.* `<integer(1)>: default 5`. `5`
#'   (the FDA standard: names <= 8 characters, labels <= 40 bytes) or `8`
#'   (names <= 32, long labels).
#' @param encoding *Target charset.* `<character(1)> | NULL`. `NULL`
#'   (default) inherits the source encoding recorded in `artoo_meta`, else
#'   UTF-8. IANA and SAS names (`"US-ASCII"`, `"wlatin1"`) both work.
#'
#'   **Tip:** any SAS or IANA spelling listed by [artoo_encodings()] is
#'   accepted.
#' @param on_invalid *Policy for values not representable in `encoding`.*
#'   `<character(1)>: default "error"`. One of `"error"`, `"replace"`
#'   (substitute `?` and warn), or `"ignore"` (drop them).
#' @param created *Header timestamp.* `<POSIXct(1)> | NULL`. `NULL` (default)
#'   stamps the current time; freeze it for byte-stable output.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'
#' @examples
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists
#' )
#'
#' # ---- Example 1: write a conformed dataset as v5 (FDA standard) ----
#' #
#' # apply_spec() attaches the metadata; write_xpt() carries the label, length,
#' # and SAS format for each variable into the transport file.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".xpt")
#' write_xpt(adsl, path)
#'
#' # ---- Example 2: v8 for long names, with a frozen timestamp ----
#' #
#' # Version 8 keeps names over 8 characters; a fixed `created` makes the bytes
#' # reproducible. DM is SDTM, so it conforms against the bundled sdtm_spec.
#' dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#' path8 <- tempfile(fileext = ".xpt")
#' write_xpt(dm, path8, version = 8, created = as.POSIXct("2020-01-01", tz = "UTC"))
#'
#' @seealso [read_xpt()] for the inverse; [write_dataset()] for the generic
#'   dispatcher.
#' @export
write_xpt <- function(
  x,
  path,
  version = 5,
  encoding = NULL,
  on_invalid = c("error", "replace", "ignore"),
  created = NULL
) {
  on_invalid <- match.arg(on_invalid)
  write_dataset(
    x,
    path,
    format = "xpt",
    version = version,
    encoding = encoding,
    on_invalid = on_invalid,
    created = created
  )
}

#' Read a dataset from SAS XPORT
#'
#' Read a SAS Transport (`.xpt`) file (v5 or v8) back to a data frame,
#' restoring the `artoo_meta` its NAMESTR records carry and realizing SAS
#' date/datetime/time variables to R `Date` / `POSIXct` / `hms::hms`. The
#' ingest end of the I/O layer; a thin wrapper over [read_dataset()] with
#' `format = "xpt"`.
#'
#' @details
#' The character encoding is auto-detected (UTF-8 if every character value is
#' valid UTF-8, else Windows-1252) and recorded on the returned
#' `artoo_meta`, so a later [write_xpt()] reproduces it; pass `encoding` to
#' override. XPORT cannot record its own encoding, so this detection is a
#' heuristic. See [write_xpt()] for what XPORT can and cannot preserve.
#'
#' @param path *Source `.xpt` path.* `<character(1)>: required`.
#' @param encoding *Force a source charset.* `<character(1)> | NULL`. `NULL`
#'   (default) auto-detects (UTF-8 when every character value and label is
#'   valid UTF-8, else Windows-1252). IANA and SAS names both work.
#'
#'   **Tip:** any SAS or IANA spelling listed by [artoo_encodings()] is
#'   accepted.
#' @param col_select *Variables to read.* `<character> | NULL`. `NULL`
#'   (default) reads every column; otherwise a vector of variable names
#'   (matching the names as stored, uppercase for v5). Columns return in file
#'   order, and the `artoo_meta` is filtered to match.
#'
#'   **Note:** an unknown name is a `artoo_error_input`, never a silent drop.
#' @param n_max *Maximum records to read.* `<numeric(1)>: default Inf`. Caps
#'   the row count; the returned `artoo_meta` reports the rows actually read.
#' @param member *Which member of a multi-member transport file to read.*
#'   `<character(1) | numeric(1)> | NULL`. A transport file can hold several
#'   datasets; pass a member name (case-insensitive) or 1-based index to pick
#'   one. `NULL` (default) reads a single-member file directly and aborts on
#'   a multi-member file, pointing at [xpt_members()].
#'
#'   **Tip:** `xpt_members(path)` lists what a file holds before you choose.
#'
#' @return *A `<data.frame>`* carrying `artoo_meta` (read it with
#'   [get_meta()]).
#'
#' @examples
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists
#' )
#'
#' # ---- Example 1: round-trip a conformed dataset through xpt ----
#' #
#' # Write ADSL, read it back; the variable labels and lengths survive.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' path <- tempfile(fileext = ".xpt")
#' write_xpt(adsl, path)
#' back <- read_xpt(path)
#' get_meta(back)@columns$STUDYID$label
#'
#' # ---- Example 2: pick one member of a multi-member transport file ----
#' #
#' # Build a two-member file by concatenating two single-member files (every
#' # member section is 80-byte padded), then read one dataset out of it.
#' dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#' p_dm <- tempfile(fileext = ".xpt")
#' write_xpt(dm, p_dm)
#' multi <- tempfile(fileext = ".xpt")
#' writeBin(
#'   c(
#'     readBin(path, "raw", file.size(path)),
#'     readBin(p_dm, "raw", file.size(p_dm))[-(1:240)]
#'   ),
#'   multi
#' )
#' xpt_members(multi)$name
#' nrow(read_xpt(multi, member = "DM"))
#'
#' @seealso [xpt_members()] to list a file's members; [write_xpt()] for the
#'   inverse; [read_dataset()] for the generic dispatcher.
#' @export
read_xpt <- function(
  path,
  encoding = NULL,
  col_select = NULL,
  n_max = Inf,
  member = NULL
) {
  read_dataset(
    path,
    format = "xpt",
    encoding = encoding,
    col_select = col_select,
    n_max = n_max,
    member = member
  )
}

#' List the members of a SAS XPORT transport file
#'
#' Report every dataset (member) a SAS Transport (`.xpt`) file holds, with
#' its label, variable count, and row count -- the survey step before
#' [read_xpt()] with `member =` picks one. A single-member file (the FDA
#' submission convention) returns one row.
#'
#' @details
#' **v5 has no recorded row count.** A v8 member records its rows; a v5
#' member's count is derived from the byte span up to the next member (or end
#' of file) minus trailing padding, so an all-character v5 member whose last
#' row is entirely blank reports one row fewer (the documented v5 ambiguity,
#' see [write_xpt()]).
#'
#' @param path *Source `.xpt` path.* `<character(1)>: required`. A file that
#'   is not a valid XPORT library aborts with `artoo_error_codec`.
#'
#' @return *A `<data.frame>`* with one row per member and columns `member`
#'   (1-based index), `name`, `label`, `nvars`, and `nobs`. Pass `member` or
#'   `name` to [read_xpt()].
#'
#' @examples
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists
#' )
#'
#' # ---- Example 1: a single-member file reports one row ----
#' #
#' # The FDA convention is one dataset per transport file.
#' dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#' p <- tempfile(fileext = ".xpt")
#' write_xpt(dm, p)
#' xpt_members(p)
#'
#' # ---- Example 2: survey a multi-member file, then read one member ----
#' #
#' # Concatenate two single-member files into one library and list it.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' p2 <- tempfile(fileext = ".xpt")
#' write_xpt(adsl, p2)
#' multi <- tempfile(fileext = ".xpt")
#' writeBin(
#'   c(
#'     readBin(p, "raw", file.size(p)),
#'     readBin(p2, "raw", file.size(p2))[-(1:240)]
#'   ),
#'   multi
#' )
#' xpt_members(multi)
#'
#' @seealso [read_xpt()] with `member =` to read one of them.
#' @export
xpt_members <- function(path) {
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
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  lib <- .xpt_parse_library(con, call)
  members <- .xpt_scan_members(con, lib$version, path, call)
  data.frame(
    member = vapply(members, function(m) m$member, integer(1)),
    name = vapply(members, function(m) m$name, character(1)),
    label = vapply(members, function(m) m$label, character(1)),
    nvars = vapply(members, function(m) m$nvars, integer(1)),
    nobs = vapply(members, function(m) m$nobs, integer(1)),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

.register_codec(
  "xpt",
  encode = ".encode_xpt",
  decode = ".decode_xpt",
  extensions = c("xpt", "xport"),
  mode = "rw"
)
