# spec_print.R — print/format methods for the two front-door S7 objects,
# artoo_spec and artoo_meta.
#
# The renderers are plain functions (.format_spec / .format_meta) so they are
# testable under devtools::load_all(); the S7 print/format methods (which only
# dispatch in an installed build) delegate to them. Plain S3 on the qualified
# class name ("artoo::artoo_spec"), NOT S7::method(print, ...)<-, for the same
# dispatch-hijack reason documented in spec_check_report.R.

# Up to `n` names as "A, B, C", with a "(+K more)" tail when truncated. Empty
# vector renders as "(none)".
#' @noRd
.preview_names <- function(x, n = 8L) {
  x <- x[!is.na(x) & nzchar(x)]
  if (!length(x)) {
    return("(none)")
  }
  if (length(x) > n) {
    paste0(
      paste(x[seq_len(n)], collapse = ", "),
      sprintf(" (+%d more)", length(x) - n)
    )
  } else {
    paste(x, collapse = ", ")
  }
}

# A single scalar field from a 1-row study frame, or NA when absent/blank.
#' @noRd
.study_scalar <- function(study, field) {
  if (!(field %in% names(study)) || !nrow(study)) {
    return(NA_character_)
  }
  v <- study[[field]][[1L]]
  if (length(v) != 1L || is.na(v) || !nzchar(as.character(v))) {
    return(NA_character_)
  }
  as.character(v)
}

#' @noRd
.format_spec <- function(x) {
  # A valid artoo_spec always carries the schema columns (datasets$dataset,
  # codelists$codelist_id), so no presence guard is needed here.
  ds_names <- x@datasets$dataset
  n_ds <- length(ds_names[!is.na(ds_names)])
  n_var <- nrow(x@variables)
  cl_ids <- x@codelists$codelist_id
  n_cl <- length(unique(cl_ids[!is.na(cl_ids)]))

  study_name <- .study_scalar(x@study, "study_name")
  header <- sprintf(
    "Study: %s",
    if (is.na(study_name)) "(unspecified)" else study_name
  )
  standard <- sprintf(
    "Standard: %s",
    if (is.na(x@standard)) "(unspecified)" else x@standard
  )

  lines <- c(
    "<artoo_spec>",
    header,
    standard,
    sprintf("Datasets:  %d", n_ds),
    sprintf("Variables: %d", n_var),
    sprintf("Codelists: %d", n_cl)
  )

  # Only surface the supporting-metadata slots when they carry rows, so a
  # minimal spec prints a short, uncluttered summary.
  support <- c(
    Methods = nrow(x@methods),
    Comments = nrow(x@comments),
    Documents = nrow(x@documents)
  )
  support <- support[support > 0L]
  for (nm in names(support)) {
    lines <- c(lines, sprintf("%s: %d", nm, support[[nm]]))
  }
  if (!is.null(x@values) && is.data.frame(x@values) && nrow(x@values)) {
    lines <- c(lines, sprintf("Value-level: %d", nrow(x@values)))
  }

  c(lines, sprintf("Spec for: %s", .preview_names(ds_names)))
}

# One "NAME  dataType" preview line per column, padded to the longest name.
#' @noRd
.format_meta_columns <- function(cols, n = 6L) {
  nms <- names(cols)
  shown <- utils::head(nms, n)
  pad <- max(nchar(shown), 0L)
  lines <- vapply(
    shown,
    function(nm) {
      dt <- cols[[nm]]$dataType %||% "?"
      sprintf("  %-*s  %s", pad, nm, dt)
    },
    character(1)
  )
  more <- length(nms) - length(shown)
  if (more > 0L) {
    lines <- c(lines, sprintf("  ... (+%d more)", more))
  }
  unname(lines)
}

#' @noRd
.format_meta <- function(x) {
  ds <- x@dataset
  cols <- x@columns
  name <- ds$name %||% "(unnamed)"
  label <- ds$label
  head_line <- if (!is.null(label) && nzchar(label)) {
    sprintf("Dataset: %s (%s)", name, label)
  } else {
    sprintf("Dataset: %s", name)
  }

  records <- ds$records
  keys <- ds$keys

  lines <- c("<artoo_meta>", head_line)
  if (!is.null(records)) {
    lines <- c(lines, sprintf("Records: %d", as.integer(records)))
  }
  lines <- c(lines, sprintf("Columns: %d", length(cols)))
  if (!is.null(keys) && length(keys)) {
    lines <- c(lines, sprintf("Keys:    %s", paste(keys, collapse = ", ")))
  }
  if (length(cols)) {
    lines <- c(lines, .format_meta_columns(cols))
  }
  lines
}

# ---- print / format ---------------------------------------------------------

#' @exportS3Method print artoo::artoo_spec
`print.artoo::artoo_spec` <- function(x, ...) {
  cat(.format_spec(x), sep = "\n")
  invisible(x)
}

#' @exportS3Method format artoo::artoo_spec
`format.artoo::artoo_spec` <- function(x, ...) {
  .format_spec(x)
}

#' @exportS3Method print artoo::artoo_meta
`print.artoo::artoo_meta` <- function(x, ...) {
  cat(.format_meta(x), sep = "\n")
  invisible(x)
}

#' @exportS3Method format artoo::artoo_meta
`format.artoo::artoo_meta` <- function(x, ...) {
  .format_meta(x)
}
