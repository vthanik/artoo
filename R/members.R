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
    # WHAT NO TEST HERE CAN SEE: this branch runs only for a file carrying no
    # artoo metadata, which today means a plain saveRDS() .rds -- and .rds
    # cannot be gzipped. So .path_stem()'s gz peel is unobservable at this
    # call site, and swapping it for file_path_sans_ext(basename(.)) passes
    # every test. It stays because it is correct for the inputs this branch
    # would see if a gzip-capable codec ever stopped recording a name; the
    # peel is load-bearing, and tested, in the folder resolver.
    .path_stem(path)
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
# Extensions whose codec can sit behind transparent gzip. read_dataset()
# peels `.gz` for exactly these (`.resolve_format`, R/io.R), so anything that
# INVENTORIES files for it must peel the same ones or a readable file becomes
# invisible -- or worse, aborts, which is what members("dm.ndjson.gz") did on
# a file write_ndjson()'s own examples produce.
#' @noRd
.gz_extensions <- function() {
  unique(unlist(lapply(c("json", "ndjson"), function(f) {
    .artoo_codecs[[f]]$extensions
  })))
}

# The extension that decides the codec, after peeling transparent gzip.
# `dm.parquet.gz` keeps `gz` and stays unhandled, because read_dataset()
# refuses it too.
#' @noRd
.effective_ext <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (!identical(ext, "gz")) {
    return(ext)
  }
  inner <- tolower(tools::file_ext(sub("\\.gz$", "", path, ignore.case = TRUE)))
  if (inner %in% .gz_extensions()) inner else ext
}

# The basename with its dataset extension removed, gzip peeled first, so
# `dm.json.gz` stems to `dm` exactly as `dm.json` does.
#' @noRd
.path_stem <- function(path) {
  base <- basename(path)
  gz <- tolower(tools::file_ext(base)) == "gz"
  base[gz] <- sub("\\.gz$", "", base[gz], ignore.case = TRUE)
  tools::file_path_sans_ext(base)
}

#' @noRd
.known_extensions <- function(formats = NULL) {
  unique(unlist(lapply(formats %||% .registered_formats(), function(f) {
    .artoo_codecs[[f]]$extensions
  })))
}

# Validate a user-supplied `format` restriction: NULL, or a character vector
# of registered format NAMES. Each element goes through .resolve_codec(), so
# an unknown name gets the same message and the same condition class that
# read_dataset(format = ) already gives -- one vocabulary, not two.
#
# Names, not extensions, because the registry maps one name to several
# extensions: "parquet" claims both .parquet and .pq, so an extension-shaped
# argument would silently inventory half a directory.
#' @noRd
.members_formats <- function(
  format,
  arg = "format",
  call = rlang::caller_env()
) {
  if (is.null(format)) {
    return(NULL)
  }
  if (!is.character(format) || !length(format)) {
    known <- .registered_formats()
    .artoo_abort(
      c(
        "{.arg {arg}} must name at least one registered format.",
        "x" = "You supplied {.obj_type_friendly {format}}.",
        "i" = "Registered formats: {.val {known}}."
      ),
      kind = "input",
      call = call
    )
  }
  for (f in format) {
    .resolve_codec(f, call = call)
  }
  format
}

# A directory -> every dataset file it holds (non-recursive), one row per
# contained dataset. Non-dataset files are skipped; a dataset-free directory
# returns the canonical empty frame (no abort). A malformed dataset file is
# NOT swallowed: its codec's path-bearing abort names it.
#' @noRd
.members_dir <- function(path, formats = NULL, call = rlang::caller_env()) {
  files <- list.files(path, full.names = TRUE)
  files <- files[!dir.exists(files)]
  keep <- vapply(files, .effective_ext, character(1), USE.NAMES = FALSE) %in%
    .known_extensions(formats)
  files <- sort(files[keep])
  if (!length(files)) {
    return(.empty_members())
  }
  rows <- lapply(files, function(f) {
    codec <- .codec_for_ext(.effective_ext(f), call = call)
    if (codec$format == "xpt") {
      .members_xpt(f)
    } else {
      .members_single(f, codec, call = call)
    }
  })
  out <- do.call(rbind, rows)
  # The filter above is by EXTENSION; this is by resolved FORMAT, which is
  # what the restriction actually means and what the single-file branch
  # already tests. They agree only while no two codecs claim one extension,
  # and the registry header says a public register_codec() is anticipated.
  if (!is.null(formats)) {
    out <- out[out$format %in% formats, , drop = FALSE]
  }
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
#' @param format *Restrict the inventory to these formats.* `<character> |
#'   NULL`. Defaults to `NULL`, which inventories every format. Format names
#'   as [artoo_formats()] lists them, not
#'   file extensions: `"parquet"` claims both `.parquet` and `.pq`. `NULL`
#'   inventories every format. Several names are a set, not an order, so
#'   `c("xpt", "json")` lists both and says nothing about which wins.
#'
#'   **Tip:** the reason to pass it is a directory holding the same dataset
#'   in more than one format, where the full inventory lists `dm.xpt` and
#'   `dm.json` as two rows.
#'
#'   **Restriction:** it filters, it does not override. Unlike
#'   [read_dataset()]'s `format`, which reads a file AS the named format
#'   whatever its extension, this narrows which files are inventoried and
#'   leaves extension resolution alone. Naming one file whose format the
#'   restriction excludes aborts, rather than returning an empty inventory
#'   that could not be told apart from an empty directory.
#'
#' @return *A `<artoo_members>` data frame*, one row per dataset, with columns
#'   `file` (source basename), `member` (dataset name), `label`, `records`
#'   (row count), `variables` (column count), and `format` (the codec
#'   format). Empty when a directory holds no dataset files, and likewise when
#'   `format` excludes every one it holds. It is an ordinary data frame
#'   underneath.
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
#' # ---- Example 3: one dataset, two formats, one of them wanted ----
#' #
#' # The same dataset stored twice is two rows, because the inventory reports
#' # what is on disk. Name the format to see only that half.
#' members(dir, format = "json")
#'
#' @seealso
#' **Members of one XPORT file:** [xpt_members()].
#'
#' **Per-variable attributes:** [columns()] for one dataset's variable pane.
#' @export
members <- function(path, format = NULL) {
  call <- rlang::caller_env()
  .check_path(path, call)
  formats <- .members_formats(format, call = call)
  if (dir.exists(path)) {
    out <- .members_dir(path, formats, call = call)
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
    codec <- .codec_for_ext(.effective_ext(path), call = call)
    # A named file whose format the restriction excludes is a contradiction in
    # the call, not a result. Returning an empty inventory would make it
    # indistinguishable from an empty directory -- one of those is an honest
    # answer about a folder, the other is two arguments disagreeing.
    if (!is.null(formats) && !(codec$format %in% formats)) {
      .artoo_abort(
        c(
          "{.arg format} excludes the file {.arg path} names.",
          "x" = "{.path {basename(path)}} is {.val {codec$format}}; you asked for {.val {formats}}.",
          "i" = "Drop {.arg format}, or name {.val {codec$format}} in it."
        ),
        kind = "input",
        call = call
      )
    }
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
