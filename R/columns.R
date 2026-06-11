# columns.R — columns(): the SAS-viewer-style variable attribute pane.
#
# One row per column of a frame (or of a dataset file), with the attribute
# names a SAS programmer expects from PROC CONTENTS / the Universal Viewer:
# #, Variable, Type, Len, Format, Informat, Label — plus a CDISC Key column
# (the keySequence). Polymorphic: a stamped frame reads its artoo_meta, a
# plain frame is inferred from R classes, and a file path is read through
# the one lossless codec for its extension (reusing the reader guarantees
# the attributes are correct by construction; a header-only parser would be
# a second source of truth).

#' View a dataset's variable attributes, SAS-style
#'
#' Return a one-row-per-variable attribute table — the pane a SAS
#' programmer reads in `PROC CONTENTS` or the Universal Viewer: position,
#' name, Char/Num type, length, format, informat, label, and the CDISC key
#' sequence. This is the quick look after [apply_spec()] stamps a frame, or
#' on any dataset file artoo can read.
#'
#' @details
#' **Every real column shows.** The table covers the *frame's* columns: a
#' column the spec never declared (which [apply_spec()] keeps, never drops)
#' still appears, its attributes inferred from the R class. A plain,
#' never-stamped data frame works the same way — every attribute is
#' inferred.
#'
#' **A path reads through the codec.** A file path is dispatched by
#' extension through the same registry as [read_dataset()], so the
#' attributes come from the one lossless reader (an unknown extension
#' aborts with the registry's known-extensions message).
#'
#' **Tip:** a multi-member XPORT file needs `member =`; without one the
#' xpt reader aborts and points at [xpt_members()] for the listing.
#'
#' **Note:** an `.xpt` path shows a blank `Key`: the XPORT byte layout
#' stores only name, label, length, and formats, so `keySequence` (like
#' codelist and origin) cannot ride in the file. The metadata-carrying
#' formats (`.json`, `.ndjson`, `.parquet`, `.rds`) and the in-session
#' conformed frame show it; re-apply the spec after an xpt read to
#' restore it.
#'
#' @param x *What to describe.* `<data.frame> | <character(1)>: required`.
#'   A stamped frame (carries `artoo_meta`), any plain data frame, or a
#'   path to a dataset file (`.xpt`, `.json`, `.ndjson`, `.parquet`,
#'   `.rds`).
#' @param member *XPORT member to describe.* `<character(1)> | NULL`. Only
#'   meaningful when `x` is a path to a multi-member `.xpt` file.
#'
#' @return *A `<artoo_columns>` data frame* with columns `#`, `Variable`,
#'   `Type`, `Len`, `Format`, `Informat`, `Label`, `Key`, printed
#'   left-aligned. It is an ordinary data frame underneath — filter or
#'   inspect it like one.
#'
#' @examples
#' spec <- artoo_spec(cdisc_adam_datasets, cdisc_adam_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: the column pane of a conformed frame ----
#' #
#' # apply_spec() stamps ADSL with its metadata; columns() reads it back as
#' # the SAS-style attribute table.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
#' columns(adsl)
#'
#' # ---- Example 2: straight off a file ----
#' #
#' # Write the conformed frame to any format and point columns() at the
#' # path; the codec reads it back and the attributes are identical.
#' p <- tempfile(fileext = ".json")
#' write_json(adsl, p)
#' columns(p)
#'
#' @seealso
#' **Members:** [xpt_members()] lists a multi-member XPORT file.
#'
#' **Metadata:** [get_meta()] for the full `artoo_meta`; [apply_spec()]
#' which stamps it.
#' @export
columns <- function(x, member = NULL) {
  call <- rlang::caller_env()
  if (is.character(x)) {
    if (length(x) != 1L || is.na(x) || !nzchar(x)) {
      .artoo_abort(
        c(
          "{.arg x} must be a data frame or a single file path.",
          "x" = "You supplied {.obj_type_friendly {x}}."
        ),
        kind = "input",
        call = call
      )
    }
    # Validate the extension through the registry FIRST (its known-extension
    # abort is the canonical message), then read through the one codec.
    .codec_for_ext(tools::file_ext(x), call = call)
    x <- if (is.null(member)) {
      read_dataset(x)
    } else {
      read_dataset(x, member = member)
    }
  }
  if (!is.data.frame(x)) {
    .artoo_abort(
      c(
        "{.arg x} must be a data frame or a single file path.",
        "x" = "You supplied {.obj_type_friendly {x}}."
      ),
      kind = "input",
      call = call
    )
  }

  has_meta <- is.character(attr(x, "metadata_json", exact = TRUE))
  meta <- if (has_meta) get_meta(x) else NULL
  meta_cols <- if (is.null(meta)) list() else meta@columns
  ds_name <- if (is.null(meta)) NA_character_ else meta@dataset$name %||% NA

  nms <- names(x)
  rows <- lapply(seq_along(nms), function(i) {
    nm <- nms[[i]]
    cm <- meta_cols[[nm]]
    if (is.null(cm)) {
      # Undeclared or never-stamped column: infer from the R class, exactly
      # like the codecs do on write.
      cm <- .col_from_frame_col(nm, x[[i]], ds_name)
    }
    data.frame(
      `#` = i,
      Variable = nm,
      # SAS Type reports STORAGE: character columns are Char, everything
      # else (including numeric-backed dates/times) is Num.
      Type = if (is.character(x[[i]]) || is.factor(x[[i]])) "Char" else "Num",
      Len = cm$length %||% NA_integer_,
      Format = cm$displayFormat %||% NA_character_,
      Informat = cm$informat %||% NA_character_,
      Label = cm$label %||% NA_character_,
      Key = cm$keySequence %||% NA_integer_,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  })
  out <- if (length(rows)) {
    do.call(rbind, rows)
  } else {
    # A zero-column frame still gets the canonical (empty) pane.
    data.frame(
      `#` = integer(0),
      Variable = character(0),
      Type = character(0),
      Len = integer(0),
      Format = character(0),
      Informat = character(0),
      Label = character(0),
      Key = integer(0),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }
  rownames(out) <- NULL
  attr(out, "dataset") <- ds_name
  attr(out, "records") <- nrow(x)
  class(out) <- c("artoo_columns", "data.frame")
  out
}

#' @exportS3Method format artoo_columns
format.artoo_columns <- function(x, ...) {
  # `[` on a data frame drops custom attributes but keeps the class, so a
  # filtered pane arrives here without dataset/records — degrade gracefully.
  ds <- attr(x, "dataset", exact = TRUE) %||% NA_character_
  records <- attr(x, "records", exact = TRUE)
  header <- sprintf(
    "<artoo_columns> %s-- %d variable%s%s",
    if (length(ds) != 1L || is.na(ds)) "" else paste0(ds, " "),
    nrow(x),
    if (nrow(x) == 1L) "" else "s",
    if (is.null(records)) "" else sprintf(", %d obs", records)
  )
  body <- as.data.frame(x)
  # Render every cell left-aligned; NA prints blank (the SAS viewer look).
  # Built by explicit dims so a 0-row pane degrades to the header line.
  cells <- matrix("", nrow = nrow(body), ncol = ncol(body))
  for (j in seq_along(body)) {
    ch <- as.character(body[[j]])
    ch[is.na(ch)] <- ""
    cells[, j] <- ch
  }
  table <- rbind(names(body), cells)
  widths <- apply(nchar(table, type = "width"), 2, max)
  pad <- function(s, w) {
    paste0(s, strrep(" ", w - nchar(s, type = "width")))
  }
  lines <- apply(
    table,
    1,
    function(r) {
      trimws(
        paste(mapply(pad, r, widths), collapse = "  "),
        which = "right"
      )
    }
  )
  c(header, lines)
}

#' @exportS3Method print artoo_columns
print.artoo_columns <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}
