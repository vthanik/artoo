# spec_check_report.R -- render a vport_check as a sectioned text report
# (datacompy `.report()` style) and the S7 print/format methods.
#
# The renderer is the plain function `.format_check()` so it is testable
# under devtools::load_all(); the S7 print/format methods (which only
# dispatch in an installed build) just delegate to it.

.check_rule <- function(width = 56) strrep("-", width)

# One finding line: "[check] message  (dataset.variable)", newline-collapsed
# and truncated so it stays a single tidy line.
#' @noRd
.format_finding_line <- function(check, dataset, variable, message) {
  msg <- gsub("[\r\n]+", " ", message)
  msg <- gsub("[[:space:]]+", " ", trimws(msg))
  if (nchar(msg) > 120L) {
    msg <- paste0(substr(msg, 1L, 117L), "...")
  }
  loc <- ""
  if (!is.na(dataset) && nzchar(dataset)) {
    loc <- dataset
    if (!is.na(variable) && nzchar(variable)) {
      loc <- paste0(dataset, ".", variable)
    }
  } else if (!is.na(variable) && nzchar(variable)) {
    loc <- variable
  }
  line <- sprintf("[%s] %s", check, msg)
  if (nzchar(loc)) {
    line <- sprintf("%s  (%s)", line, loc)
  }
  line
}

# Lines for one severity section, with per-section truncation.
#' @noRd
.format_section <- function(f, severity, title, cap = 15L) {
  rows <- f[f$severity == severity, , drop = FALSE]
  if (!nrow(rows)) {
    return(character(0))
  }
  shown <- utils::head(rows, cap)
  lines <- vapply(
    seq_len(nrow(shown)),
    function(i) {
      .format_finding_line(
        shown$check[i],
        shown$dataset[i],
        shown$variable[i],
        shown$message[i]
      )
    },
    character(1)
  )
  more <- nrow(rows) - nrow(shown)
  if (more > 0L) {
    lines <- c(lines, sprintf("... and %d more (see x@findings)", more))
  }
  c(title, .check_rule(nchar(title)), lines, "")
}

#' @noRd
.format_check <- function(x) {
  f <- x@findings
  s <- x@summary
  n_err <- sum(f$severity == "error")
  n_warn <- sum(f$severity == "warning")
  n_note <- sum(f$severity == "note")

  scope <- if (length(x@scope)) paste(x@scope, collapse = ", ") else "(none)"
  num <- function(nm) if (is.null(s[[nm]])) 0L else s[[nm]]

  header <- c(
    "vport Spec Check",
    strrep("=", 16L),
    "",
    "Spec Summary",
    .check_rule(12L),
    sprintf("Study: %s", x@study),
    sprintf("Scope: %s", scope),
    sprintf(
      "Datasets: %d    Variables: %d",
      num("n_datasets"),
      num("n_variables")
    ),
    sprintf(
      "Methods referenced: %d    Comments referenced: %d",
      num("n_methods_ref"),
      num("n_comments_ref")
    ),
    ""
  )

  if (!nrow(f)) {
    return(c(header, "No findings.", ""))
  }

  summary_block <- c(
    "Findings Summary",
    .check_rule(16L),
    sprintf("  error    %d", n_err),
    sprintf("  warning  %d", n_warn),
    sprintf("  note     %d", n_note),
    ""
  )

  c(
    header,
    summary_block,
    .format_section(f, "error", "Errors"),
    .format_section(f, "warning", "Warnings"),
    .format_section(f, "note", "Notes")
  )
}

# ---- S7 print / format (dispatch only in an installed build) ------------

S7::method(print, vport_check_class) <- function(x, ...) {
  cat(.format_check(x), sep = "\n")
  invisible(x)
}

S7::method(format, vport_check_class) <- function(x, ...) {
  .format_check(x)
}
