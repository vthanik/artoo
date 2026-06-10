# codec_xpt.R -- the SAS XPORT (xpt) codec, v5 (FDA submission default) and
# v8 (extended names/labels). Single-member only (one dataset = one file).
#
# The XPORT framing (LIBRARY/MEMBER/NAMESTR/OBS headers, the 140-byte namestr,
# and the v8 LABELV8 long-name/long-label extension) is built from the SAS
# XPORT v5/v8 transport spec. All metadata flows through the vport_meta spine
# -- the codec never reads or writes raw column attributes -- and all
# transcoding goes through encoding.R. The byte/float/temporal mechanics reuse
# the existing building blocks (xpt_ieee.R, xpt_util.R, vport_temporal.R).
#
# Honesty contracts (see write_xpt/read_xpt @details):
#  - C3: an .xpt file's NAMESTR holds only name/label/length/format. CDISC
#    metadata beyond that (keySequence, codelist, origin, targetDataType, ...)
#    and the source encoding are NOT representable in the .xpt bytes; they ride
#    the live in-session vport_meta (and the sidecar in other containers).
#  - C4: "" and NA_character_ are physically identical in XPORT (both blanks);
#    a genuine empty string reads back as NA. Trailing spaces are likewise not
#    recoverable.
#  - C5: SAS per-variable transcode=NO has no NAMESTR field, so vport cannot
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
    .str_to_raw("", 8L),
    .int_to_pib2(0L),
    .int_to_pib2(0L),
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
      .int_to_pib2(0L),
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
  has_meta <- is_vport_meta(meta)
  label_trunc <- character(0)
  recs <- vector("list", length(nms))
  for (i in seq_along(nms)) {
    nm <- nms[i]
    col <- x[[nm]]
    cm <- if (has_meta) meta@columns[[nm]] else NULL

    if (is.factor(col)) {
      cli::cli_abort(
        c(
          "Column {.var {nm}} is a factor.",
          "i" = "Convert it with {.fn as.character} before writing."
        ),
        class = "vport_error_type",
        call = call
      )
    }
    if (is.list(col)) {
      cli::cli_abort(
        c(
          "Column {.var {nm}} is a list column.",
          "i" = "xpt cannot store list columns."
        ),
        class = "vport_error_type",
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
    display <- if (!is.null(cm)) cm$displayFormat else NULL
    display <- .resolve_display_format(
      dt,
      if (is.null(display)) NA else display
    )
    vtype <- .xpt_vartype(dt)
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
        cli::cli_abort(
          c(
            "Cannot coerce column {.var {nm}} to numeric for xpt.",
            "x" = "Offending value{?s}: {.val {bad}}."
          ),
          class = "vport_error_codec",
          call = call
        )
      }
      # xpt cannot represent infinity; fail loud rather than silently writing a
      # SAS missing (consistent with the finite-overflow guard below).
      if (any(is.infinite(num))) {
        cli::cli_abort(
          c(
            "Column {.var {nm}} contains infinite values.",
            "i" = "xpt cannot represent infinity; remove or recode them first."
          ),
          class = "vport_error_codec",
          call = call
        )
      }
      fin <- is.finite(num)
      if (any(abs(num[fin]) >= .xpt_ibm_max)) {
        cli::cli_abort(
          c(
            "Column {.var {nm}} exceeds the IBM-370 magnitude limit.",
            "i" = "xpt numerics cap near 7.2e75."
          ),
          class = "vport_error_codec",
          call = call
        )
      }
      bytes <- .ieee_to_ibm(num, missing = tag)
      nlng <- 8L
    } else {
      chr <- .to_target(as.character(col), target_enc, on_invalid, call)
      bw <- nchar(chr, type = "bytes")
      bw[is.na(chr)] <- 0L
      declared <- if (!is.null(cm) && !is.null(cm$length)) {
        as.integer(cm$length)
      } else {
        0L
      }
      nlng <- max(declared, max(bw, 1L))
      if (version == 5L && nlng > 200L) {
        cli::cli_abort(
          c(
            "Column {.var {nm}} needs {nlng} bytes, over the v5 limit of 200.",
            "i" = "Use {.code version = 8} or shorten the data."
          ),
          class = "vport_error_codec",
          call = call
        )
      }
      bytes <- if (nobs) {
        unlist(lapply(seq_len(nobs), function(k) {
          .str_to_raw_bytes(if (is.na(chr[k])) "" else chr[k], nlng)
        }))
      } else {
        raw(0)
      }
    }

    out_name <- nm
    if (version == 5L) {
      up <- toupper(nm)
      if (!grepl("^[A-Z_][A-Z0-9_]{0,7}$", up)) {
        cli::cli_abort(
          c(
            "Variable name {.var {nm}} is not valid for xpt v5.",
            "i" = "v5 names are 1-8 chars of letters, digits, or underscore, not starting with a digit."
          ),
          class = "vport_error_codec",
          call = call
        )
      }
      out_name <- up
    }
    if (version == 5L && length(charToRaw(label_t)) > 40L) {
      label_trunc <- c(label_trunc, nm)
    }

    fmt <- .parse_format_str(if (is.na(display)) "" else display)
    recs[[i]] <- list(
      name = out_name,
      label = label_t,
      label_ns = label_ns,
      vartype = vtype,
      length = nlng,
      format_name = fmt$name,
      formatl = fmt$length,
      formatd = fmt$decimals,
      bytes = bytes
    )
  }
  if (length(label_trunc)) {
    cli::cli_warn(
      c(
        "Truncated {length(label_trunc)} label{?s} to 40 bytes for xpt v5: {.var {label_trunc}}.",
        "i" = "Use {.code version = 8} to keep long labels."
      ),
      class = "vport_warning_encoding"
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
    cli::cli_abort(
      c(
        "{.arg version} must be 5 or 8.",
        "x" = "You supplied {.val {version}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }

  if (is_vport_meta(meta)) {
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
    cli::cli_abort(
      c(
        "Dataset name {.val {ds_name}} is not valid for xpt.",
        "i" = "Member names are ASCII letters, digits, or underscore, not starting with a digit."
      ),
      class = "vport_error_codec",
      call = call
    )
  }
  # The dataset label is metadata: transcode with "replace" (a stray glyph
  # never aborts a write), then truncate to the 40-byte field on a character
  # boundary. Unlike variable labels, v8 has no long-label extension for it.
  ds_label <- .to_target(ds_label, target_enc, "replace", call)
  ds_label40 <- .trunc_bytes_boundary(ds_label, target_enc, 40L)
  if (!identical(ds_label40, ds_label)) {
    cli::cli_warn(
      c(
        "Truncated the dataset label to 40 bytes for xpt.",
        "i" = "XPORT stores at most 40 bytes of dataset label."
      ),
      class = "vport_warning_encoding"
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

  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
  }
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
    cli::cli_abort(
      c(
        "Not a valid XPORT transport file.",
        "x" = "Unrecognised library header."
      ),
      class = "vport_error_codec",
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
    cli::cli_abort(
      c("Not a valid XPORT member.", "x" = "Missing MEMBER header."),
      class = "vport_error_codec",
      call = call
    )
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
    cli::cli_abort(
      c(
        "Not a valid XPORT member.",
        "x" = "Could not read the variable count from the NAMESTR header."
      ),
      class = "vport_error_codec",
      call = call
    )
  }
  list(name = ds_name, label = ds_label, nvars = nvars)
}

#' @noRd
.xpt_parse_namestr <- function(raw140, version) {
  vartype <- .pib2_to_int(raw140[1:2])
  var_length <- .pib2_to_int(raw140[5:6])
  varnum <- .pib2_to_int(raw140[7:8])
  name <- .raw_to_str(raw140[9:16])
  label <- .raw_to_str(raw140[17:56])
  format_name <- .raw_to_str(raw140[57:64])
  formatl <- .pib2_to_int(raw140[65:66])
  formatd <- .pib2_to_int(raw140[67:68])
  npos <- .pib4_to_int(raw140[85:88])
  if (version == 8L) {
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
    npos = npos
  )
}

#' @noRd
.xpt_parse_namestr_block <- function(
  con,
  nvars,
  version,
  call = rlang::caller_env()
) {
  total <- nvars * 140L
  block <- if (total > 0L) .read_bytes(con, total, call) else raw(0)
  namestrs <- lapply(seq_len(nvars), function(i) {
    off <- (i - 1L) * 140L
    .xpt_parse_namestr(block[(off + 1L):(off + 140L)], version)
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

# v5 stores no obs count: it is the data section after the OBS header, blank-
# padded to an 80-byte boundary. Compute floor(remaining / obs_length) then
# trim trailing all-blank records (padding). Single-member, so no next-MEMBER
# scan. The ambiguity is confined to all-character data (a numeric field is
# never all-blank), where a genuine trailing all-NA row is indistinguishable
# from padding -- an inherent v5 limitation (see C4).
#' @noRd
.xpt_compute_v5_nobs <- function(con, obs_length, path) {
  start <- seek(con, where = NA)
  remaining <- file.info(path)$size - start
  if (remaining <= 0 || obs_length == 0L) {
    return(0L)
  }
  all_raw <- readBin(con, what = "raw", n = remaining)
  max_nobs <- length(all_raw) %/% obs_length
  while (max_nobs > 0L) {
    s <- (max_nobs - 1L) * obs_length + 1L
    e <- max_nobs * obs_length
    if (all(all_raw[s:e] == as.raw(0x20))) {
      max_nobs <- max_nobs - 1L
    } else {
      break
    }
  }
  seek(con, where = start)
  max_nobs
}

# Read the OBS section into a named list of columns. Field slicing is driven by
# the parsed npos/nlng. Numerics are right-zero-padded from nlng (2-8 bytes) to
# 8 before .ibm_to_ieee (real SAS stores high-order bytes only); they carry the
# sas_missing tag. Characters are byte-passthrough strings (converted later).
#' @noRd
.xpt_read_obs <- function(
  con,
  namestrs,
  nobs,
  obs_length,
  call = rlang::caller_env()
) {
  nvars <- length(namestrs)
  col_names <- vapply(namestrs, function(ns) ns$name, character(1))
  if (nobs == 0L || obs_length == 0L) {
    cols <- lapply(namestrs, function(ns) {
      if (ns$vartype == 1L) numeric(0) else character(0)
    })
    names(cols) <- col_names
    return(cols)
  }
  all_data <- .read_bytes(con, nobs * obs_length, call)
  raw_mat <- matrix(all_data, nrow = obs_length, ncol = nobs)
  cols <- vector("list", nvars)
  for (j in seq_len(nvars)) {
    ns <- namestrs[[j]]
    rf <- ns$npos + 1L
    rt <- ns$npos + ns$length
    if (ns$vartype == 1L) {
      vr <- raw_mat[rf:rt, , drop = FALSE]
      if (ns$length < 8L) {
        vr <- rbind(vr, matrix(as.raw(0x00), 8L - ns$length, nobs))
      }
      cols[[j]] <- .ibm_to_ieee(as.vector(vr))
    } else {
      cols[[j]] <- .raw_mat_to_strvec(raw_mat[rf:rt, , drop = FALSE], NULL)
    }
  }
  names(cols) <- col_names
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
  col <- list(
    itemOID = paste0("IT.", dataset, ".", ns$name),
    name = ns$name,
    label = if (nzchar(ns$label)) ns$label else NULL,
    dataType = dt,
    length = if (ns$vartype == 2L && ns$length > 0L) {
      as.integer(ns$length)
    } else {
      NULL
    },
    displayFormat = if (nzchar(disp)) disp else NULL
  )
  .drop_null(col)
}

# decode contract: (path, <codec args>, call) -> list(data, meta).
#' @noRd
.decode_xpt <- function(
  path,
  encoding = NULL,
  call = rlang::caller_env()
) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)

  lib <- .xpt_parse_library(con, call)
  version <- lib$version
  mem <- .xpt_parse_member(con, version, call)
  namestrs <- .xpt_parse_namestr_block(con, mem$nvars, version, call)

  nxt <- .xpt_record_str(con, call)
  if (
    grepl("LABELV8", nxt, fixed = TRUE) || grepl("LABELV9", nxt, fixed = TRUE)
  ) {
    namestrs <- .xpt_parse_label_extension(con, nxt, namestrs, call)
    nxt <- .xpt_record_str(con, call)
  }
  nobs <- .xpt_parse_obs_header(nxt, version)
  obs_length <- if (length(namestrs)) {
    sum(vapply(namestrs, function(ns) ns$length, integer(1)))
  } else {
    0L
  }
  if (is.na(nobs)) {
    nobs <- .xpt_compute_v5_nobs(con, obs_length, path)
  }
  cols <- .xpt_read_obs(con, namestrs, nobs, obs_length, call)

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
  meta <- vport_meta_class(dataset = ds_meta, columns = cols_meta)
  list(data = df, meta = meta)
}

# ---- exported wrappers ------------------------------------------------------

#' Write a dataset to SAS XPORT
#'
#' Serialize a data frame to a SAS Transport (`.xpt`) file in v5 (the FDA
#' submission standard) or v8 (extended names and labels), preserving the
#' `vport_meta` a column can hold. The emit end of the vport workflow
#' (spec -> apply_spec -> write_xpt); a thin wrapper over [write_dataset()]
#' with `format = "xpt"`.
#'
#' @details
#' **What XPORT can carry.** An `.xpt` file's NAMESTR stores only variable
#' name, label, length, and SAS format. CDISC metadata beyond that
#' (keySequence, codelist, origin, targetDataType, ...) and the source
#' encoding are not representable in the bytes; they ride the in-session
#' `vport_meta` and the sidecar in self-describing formats (Dataset-JSON,
#' Parquet, rds). XPORT also cannot distinguish an empty string from `NA`
#' (both store as blanks) and drops trailing spaces.
#'
#' @param x *The dataset to write.* `<data.frame>: required`. Typically the
#'   output of [apply_spec()], carrying `vport_meta`.
#' @param path *Destination `.xpt` path.* `<character(1)>: required`.
#' @param version *XPORT transport version.* `<integer(1)>: default 5`. `5`
#'   (the FDA standard: names <= 8 characters, labels <= 40 bytes) or `8`
#'   (names <= 32, long labels).
#' @param encoding *Target charset.* `<character(1)> | NULL`. `NULL`
#'   (default) inherits the source encoding recorded in `vport_meta`, else
#'   UTF-8. IANA and SAS names (`"US-ASCII"`, `"wlatin1"`) both work.
#' @param on_invalid *Policy for values not representable in `encoding`.*
#'   `<character(1)>: default "error"`. One of `"error"`, `"replace"`
#'   (substitute `?` and warn), or `"ignore"` (drop them).
#' @param created *Header timestamp.* `<POSIXct(1)> | NULL`. `NULL` (default)
#'   stamps the current time; freeze it for byte-stable output.
#'
#' @return *The input `x`*, invisibly, so a write can sit mid-pipeline.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: write a conformed dataset as v5 (FDA standard) ----
#' #
#' # apply_spec() attaches the metadata; write_xpt() carries the label, length,
#' # and SAS format for each variable into the transport file.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
#' path <- tempfile(fileext = ".xpt")
#' write_xpt(adsl, path)
#'
#' # ---- Example 2: v8 for long names, with a frozen timestamp ----
#' #
#' # Version 8 keeps names over 8 characters; a fixed `created` makes the bytes
#' # reproducible.
#' dm <- apply_spec(cdisc_dm, spec, "DM", on_error = "off")
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
#' restoring the `vport_meta` its NAMESTR records carry and realizing SAS
#' date/datetime/time variables to R `Date` / `POSIXct` / `vport_time`. The
#' ingest end of the I/O layer; a thin wrapper over [read_dataset()] with
#' `format = "xpt"`.
#'
#' @details
#' The character encoding is auto-detected (UTF-8 if every character value is
#' valid UTF-8, else Windows-1252) and recorded on the returned
#' `vport_meta`, so a later [write_xpt()] reproduces it; pass `encoding` to
#' override. XPORT cannot record its own encoding, so this detection is a
#' heuristic. See [write_xpt()] for what XPORT can and cannot preserve.
#'
#' @param path *Source `.xpt` path.* `<character(1)>: required`.
#' @param encoding *Force a source charset.* `<character(1)> | NULL`. `NULL`
#'   (default) auto-detects (UTF-8 when every character value and label is
#'   valid UTF-8, else Windows-1252). IANA and SAS names both work.
#'
#' @return *A `<data.frame>`* carrying `vport_meta` (read it with
#'   [get_meta()]).
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: round-trip a conformed dataset through xpt ----
#' #
#' # Write ADSL, read it back; the variable labels and lengths survive.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
#' path <- tempfile(fileext = ".xpt")
#' write_xpt(adsl, path)
#' back <- read_xpt(path)
#' get_meta(back)@columns$STUDYID$label
#'
#' # ---- Example 2: the metadata names the dataset and row count ----
#' #
#' # The restored vport_meta exposes the dataset-level attributes.
#' get_meta(back)@dataset$records
#'
#' @seealso [write_xpt()] for the inverse; [read_dataset()] for the generic
#'   dispatcher.
#' @export
read_xpt <- function(path, encoding = NULL) {
  read_dataset(path, format = "xpt", encoding = encoding)
}

.register_codec(
  "xpt",
  encode = ".encode_xpt",
  decode = ".decode_xpt",
  extensions = c("xpt", "xport"),
  mode = "rw"
)
