# members.R — members(): the format-neutral "what datasets are in this?" probe.
#
# XPORT is the only multi-dataset container artoo handles; .json / .ndjson /
# .parquet / .rds are one dataset per file. members() unifies them: an xpt
# library lists every member, a single-dataset file reports one row, and a
# directory inventories each dataset file it holds. The xpt branch reuses
# xpt_members() and every single-dataset branch reuses the codec through
# read_dataset(), so the attributes are correct by construction (no second
# parser to drift).

# One xpt library -> the uniform members frame (reuse xpt_members()).
#' @noRd
.members_xpt <- function(path) {
  m <- xpt_members(path)
  data.frame(
    file = basename(path),
    member = m$name,
    label = m$label,
    records = m$nobs,
    variables = m$nvars,
    format = "xpt",
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

# One single-dataset file -> a one-row members frame. Mirrors columns()'s meta
# guard: a plain .rds / .parquet may carry no artoo_meta, so a bare get_meta()
# would error -- fall back to the basename and NA label.
#' @noRd
.members_single <- function(path, codec, call = rlang::caller_env()) {
  x <- read_dataset(path)
  has_meta <- is.character(attr(x, "metadata_json", exact = TRUE))
  meta <- if (has_meta) get_meta(x) else NULL
  nm <- if (is.null(meta)) NULL else meta@dataset$name
  member <- if (is.null(nm) || is.na(nm) || !nzchar(nm)) {
    tools::file_path_sans_ext(basename(path))
  } else {
    nm
  }
  label <- if (is.null(meta)) {
    NA_character_
  } else {
    meta@dataset$label %||% NA_character_
  }
  data.frame(
    file = basename(path),
    member = member,
    label = label,
    records = nrow(x),
    variables = ncol(x),
    format = codec$format,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

# Every extension any registered codec claims (the membership test for the
# directory branch -- distinct from .codec_for_ext, which ABORTS on a miss).
#' @noRd
.known_extensions <- function() {
  unique(unlist(lapply(.registered_formats(), function(f) {
    .artoo_codecs[[f]]$extensions
  })))
}

# A directory -> every dataset file it holds (non-recursive), one row per
# contained dataset. Non-dataset files are skipped; a dataset-free directory
# returns the canonical empty frame (no abort). A malformed dataset file is
# NOT swallowed: its codec's path-bearing abort names it.
#' @noRd
.members_dir <- function(path, call = rlang::caller_env()) {
  files <- list.files(path, full.names = TRUE)
  files <- files[!dir.exists(files)]
  keep <- tolower(tools::file_ext(files)) %in% .known_extensions()
  files <- sort(files[keep])
  if (!length(files)) {
    return(.empty_members())
  }
  rows <- lapply(files, function(f) {
    codec <- .codec_for_ext(tolower(tools::file_ext(f)), call = call)
    if (codec$format == "xpt") {
      .members_xpt(f)
    } else {
      .members_single(f, codec, call = call)
    }
  })
  out <- do.call(rbind, rows)
  # method = "radix": deterministic C-locale order, independent of LC_COLLATE.
  out <- out[order(out$file, out$member, method = "radix"), , drop = FALSE]
  out
}

#' @noRd
.empty_members <- function() {
  data.frame(
    file = character(0),
    member = character(0),
    label = character(0),
    records = integer(0),
    variables = integer(0),
    format = character(0),
    stringsAsFactors = FALSE
  )
}

#' List the datasets in a file or directory
#'
#' Inventory the dataset(s) a path contains, one row per dataset, dispatched
#' by extension through the same codec registry as [read_dataset()]. A SAS
#' XPORT library lists every member; a single-dataset file (`.json`,
#' `.ndjson`, `.parquet`, `.rds`) reports one row; a directory inventories
#' each dataset file it holds. The format-neutral companion to the
#' xpt-specific [xpt_members()].
#'
#' @details
#' **One dataset per file, except XPORT.** XPORT is the only multi-dataset
#' container artoo handles, so only an `.xpt` path can return more than one
#' row. Every other format is one dataset per file.
#'
#' **A directory is inventoried, not descended.** Only the files directly in
#' the directory are listed (no recursion); files whose extension no codec
#' claims are skipped, and a directory with no dataset files returns an
#' empty inventory rather than aborting. A dataset file that fails to read
#' aborts with its codec's error, naming the file.
#'
#' **Note:** counting `records` reads the file through its codec (the one
#' lossless reader), so members() is an honest count, not a header guess; for
#' a large directory it reads every dataset.
#'
#' @param path *A dataset file or a directory.* `<character(1)>: required`. A
#'   path to a dataset file (`.xpt`, `.json`, `.ndjson`, `.parquet`, `.rds`)
#'   or to a directory holding such files. A path that does not exist, or a
#'   file whose extension no codec claims, aborts.
#'
#' @return *A `<artoo_members>` data frame*, one row per dataset, with columns
#'   `file` (source basename), `member` (dataset name), `label`, `records`
#'   (row count), `variables` (column count), and `format` (the codec
#'   format). Empty when a directory holds no dataset files. It is an ordinary
#'   data frame underneath.
#'
#' @examples
#' dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#'
#' # ---- Example 1: one dataset in a file ----
#' #
#' # A single-dataset format reports exactly one member.
#' p <- tempfile(fileext = ".json")
#' write_json(dm, p)
#' members(p)
#'
#' # ---- Example 2: every dataset in a directory ----
#' #
#' # Point members() at a folder to inventory each dataset file it holds, one
#' # row per dataset, dispatched by extension.
#' dir <- tempfile("datasets")
#' dir.create(dir)
#' write_json(dm, file.path(dir, "dm.json"))
#' write_rds(dm, file.path(dir, "dm.rds"))
#' members(dir)
#'
#' @seealso
#' **Members of one XPORT file:** [xpt_members()].
#'
#' **Per-variable attributes:** [columns()] for one dataset's variable pane.
#' @export
members <- function(path) {
  call <- rlang::caller_env()
  .check_path(path, call)
  if (dir.exists(path)) {
    out <- .members_dir(path, call = call)
  } else {
    if (!file.exists(path)) {
      .artoo_abort(
        c(
          "{.arg path} does not exist.",
          "x" = "No file or directory at {.path {path}}."
        ),
        kind = "input",
        call = call
      )
    }
    codec <- .codec_for_ext(tools::file_ext(path), call = call)
    out <- if (codec$format == "xpt") {
      .members_xpt(path)
    } else {
      .members_single(path, codec, call = call)
    }
  }
  rownames(out) <- NULL
  class(out) <- c("artoo_members", "data.frame")
  out
}

#' @exportS3Method format artoo_members
format.artoo_members <- function(x, ...) {
  header <- sprintf(
    "<artoo_members> %d dataset%s",
    nrow(x),
    if (nrow(x) == 1L) "" else "s"
  )
  body <- as.data.frame(x)
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
      trimws(paste(mapply(pad, r, widths), collapse = "  "), which = "right")
    }
  )
  c(header, lines)
}

#' @exportS3Method print artoo_members
print.artoo_members <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}
