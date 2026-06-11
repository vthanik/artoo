# conformance.R — the conformance-findings accessor and the classed
# findings frame. check_spec() returns a `artoo_findings` data frame (the
# 6-column findings shape plus a print method); apply_spec() stores that
# same object in the `artoo.conformance` attribute, and conformance() is
# the documented way to read it back. One object, three surfaces, no
# attr() spelunking.

# Class a findings frame for printing. A plain data frame subclass: every
# base/dplyr verb keeps working, only print() changes.
#' @noRd
.as_artoo_findings <- function(f) {
  class(f) <- c("artoo_findings", "data.frame")
  f
}

#' Read the conformance findings a dataset carries
#'
#' Pull the conformance findings [apply_spec()] attached to a conformed
#' data frame — the readable answer to "what did the check find?". The
#' result is the same findings frame [check_spec()] returns (one row per
#' divergence), with a print method that renders a sectioned report, so
#' `conformance(adsl)` at the console is the inspection step the
#' `artoo_warning_conformance` warning points you at.
#'
#' @param x *A data frame produced by [apply_spec()].* `<data.frame>:
#'   required`.
#'
#'   **Requirement:** the conformance check must have run: a frame from
#'   `apply_spec(..., conformance = "off")` (or one rebuilt by a transform
#'   that dropped attributes) carries no findings and aborts with
#'   `artoo_error_input`.
#'
#' @return *A `<artoo_findings>` data frame* with columns `check`,
#'   `dimension`, `severity` (`"error"`, `"warning"`, or `"note"`),
#'   `dataset`, `variable`, and `message`. Zero rows means the data
#'   conformed. Print it for the sectioned report; treat it as an ordinary
#'   data frame for programmatic use.
#'
#' @examples
#' spec <- artoo_spec(
#'   cdisc_sdtm_datasets, cdisc_sdtm_variables,
#'   codelists = cdisc_codelists
#' )
#'
#' # ---- Example 1: inspect what the conform step found ----
#' #
#' # Conforming raw DM records the findings on the result; conformance()
#' # renders them as a report instead of a raw attribute.
#' dm <- suppressWarnings(apply_spec(cdisc_dm, spec, "DM"))
#' conformance(dm)
#'
#' # ---- Example 2: gate a pipeline on error-severity findings ----
#' #
#' # The findings frame is an ordinary data frame: filter by severity to
#' # drive your own logic.
#' f <- conformance(dm)
#' nrow(f[f$severity == "error", ])
#'
#' @seealso [apply_spec()] which attaches the findings; [check_spec()] for
#'   the same check on demand; [artoo_checks()] to select dimensions.
#' @export
conformance <- function(x) {
  call <- rlang::caller_env()
  f <- attr(x, "artoo.conformance", exact = TRUE)
  if (is.null(f)) {
    .artoo_abort(
      c(
        "{.arg x} carries no conformance findings.",
        "x" = "No {.field artoo.conformance} attribute was found.",
        "i" = "Run {.fn apply_spec} with {.code conformance = \"warn\"} or {.code \"abort\"}, or call {.fn check_spec} directly."
      ),
      kind = "input",
      call = call
    )
  }
  .as_artoo_findings(f)
}

#' @export
print.artoo_findings <- function(x, ...) {
  # A column subset (f[, c("check", "severity")]) keeps the class but not
  # the report shape; print it as the plain data frame it now is.
  need <- c("check", "severity", "dataset", "variable", "message")
  if (!all(need %in% names(x))) {
    return(print.data.frame(x, ...))
  }
  n_err <- sum(x$severity == "error")
  n_warn <- sum(x$severity == "warning")
  n_note <- sum(x$severity == "note")
  ds <- unique(x$dataset[!is.na(x$dataset)])
  scope <- if (length(ds)) paste0(" ", paste(ds, collapse = ", ")) else ""
  cat(sprintf(
    "<artoo_findings>%s: %d error%s, %d warning%s, %d note%s\n",
    scope,
    n_err,
    if (n_err == 1L) "" else "s",
    n_warn,
    if (n_warn == 1L) "" else "s",
    n_note,
    if (n_note == 1L) "" else "s"
  ))
  if (!nrow(x)) {
    cat("No findings. The data conforms to the spec.\n")
    return(invisible(x))
  }
  cat(
    .format_section(x, "error", "Errors"),
    .format_section(x, "warning", "Warnings"),
    .format_section(x, "note", "Notes"),
    sep = "\n"
  )
  invisible(x)
}
