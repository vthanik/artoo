# check_study.R — check_study(), the study-level conformance driver.
#
# Loops check_spec() over a named list of datasets and stacks the findings
# into one frame, so "is my whole study submittable?" is one call instead of
# a hand-written per-dataset loop. The result subclasses artoo_findings, so
# it filters like a frame and feeds repair_spec() directly; its print is the
# dataset x check count matrix.

#' Check a whole study against its spec
#'
#' Run [check_spec()] over every dataset in a study and return one stacked
#' findings frame. Where [check_spec()] answers "does this dataset conform?",
#' `check_study()` answers "is my whole study submittable?" in a single pass,
#' surfacing every dataset's divergences at once instead of one abort at a
#' time. The result is an ordinary findings frame underneath, so filter it by
#' severity or hand it straight to [repair_spec()].
#'
#' @details
#' **One row per divergence, every dataset stacked.** Each dataset's findings
#' carry its name in the `dataset` column, so the frame is the union of the
#' per-dataset [check_spec()] results. Printing renders the dataset-by-check
#' count matrix (the study-level summary); the underlying frame is unchanged.
#'
#' **Data-requiring, like [check_spec()].** `check_study()` checks data
#' against the spec, so it needs the data frames. For the spec's own
#' structural integrity (no data), use [validate_spec()].
#'
#' @param spec *The specification to check against.* `<artoo_spec>:
#'   required`.
#' @param data *The study's datasets.* `<named list of data.frame>:
#'   required`. One entry per dataset, named by the dataset (e.g.
#'   `list(ADSL = adsl, ADAE = adae)`). Every name must be a dataset in
#'   `spec`.
#' @param decode *Which codelist column to check against.* `<character(1)>`.
#'   Passed to [check_spec()]; one of `"none"` (default), `"to_decode"`,
#'   `"to_code"`.
#' @param checks *Which conformance dimensions to run.*
#'   `<artoo_checks> | NULL`. Passed to [check_spec()]; `NULL` (default) runs
#'   every dimension. Build a subset with [artoo_checks()].
#'
#' @return *A `<artoo_study_findings>` data frame* with the same columns as
#'   [check_spec()] (`check`, `dimension`, `severity`, `dataset`, `variable`,
#'   `message`), one row per divergence across all datasets. Zero rows means
#'   the whole study conforms. Print it for the count matrix; treat it as an
#'   ordinary data frame otherwise.
#'
#' @examples
#' # ---- Example 1: scan a whole study in one pass ----
#' #
#' # Loop the conformance check over every dataset's data. A fractional AGE
#' # (the spec types it integer) surfaces as an integer_fraction finding; the
#' # print is a dataset-by-check count matrix.
#' adsl <- cdisc_adsl
#' adsl$AGE <- adsl$AGE + 0.5
#' check_study(adam_spec, list(ADSL = adsl, ADAE = cdisc_adae))
#'
#' # ---- Example 2: feed the findings straight into repair_spec() ----
#' #
#' # The result is an ordinary findings frame, so repair_spec() consumes it to
#' # flip every integer_fraction / integer_overflow variable across the study.
#' findings <- check_study(adam_spec, list(ADSL = adsl))
#' fixed <- repair_spec(adam_spec, findings)
#' spec_variables(fixed, "ADSL")$data_type[
#'   spec_variables(fixed, "ADSL")$variable == "AGE"
#' ]
#'
#' @seealso
#' **One dataset:** [check_spec()]. **Spec structure only:** [validate_spec()].
#'
#' **Repair:** [repair_spec()] to apply the integer fixes the matrix surfaces.
#' @export
check_study <- function(
  spec,
  data,
  decode = c("none", "to_decode", "to_code"),
  checks = NULL
) {
  call <- rlang::caller_env()
  decode <- match.arg(decode)
  .check_spec_arg(spec, call = call)

  if (!is.list(data) || is.data.frame(data) || !length(data)) {
    .artoo_abort(
      c(
        "{.arg data} must be a non-empty named list of data frames.",
        "x" = if (is.data.frame(data)) {
          "You supplied a single data frame."
        } else {
          "You supplied {.obj_type_friendly {data}}."
        },
        "i" = "Name each element by its dataset, e.g. {.code list(ADSL = adsl, ADAE = adae)}."
      ),
      kind = "input",
      call = call
    )
  }
  nms <- names(data)
  if (is.null(nms) || any(!nzchar(nms))) {
    .artoo_abort(
      c(
        "Every element of {.arg data} must be named by its dataset.",
        "i" = "For example {.code list(ADSL = adsl, ADAE = adae)}."
      ),
      kind = "input",
      call = call
    )
  }
  not_df <- !vapply(data, is.data.frame, logical(1))
  if (any(not_df)) {
    .artoo_abort(
      c(
        "Every element of {.arg data} must be a data frame.",
        "x" = "{cli::qty(sum(not_df))} Element{?s} {.val {nms[not_df]}} {?is/are} not a data frame."
      ),
      kind = "input",
      call = call
    )
  }
  known <- spec_datasets(spec)
  unknown <- setdiff(nms, known)
  if (length(unknown)) {
    .artoo_abort(
      c(
        "{cli::qty(unknown)} Dataset{?s} {.val {unknown}} {?is/are} not in the spec.",
        "i" = "Spec datasets: {.val {known}}."
      ),
      kind = "input",
      call = call
    )
  }

  parts <- lapply(nms, function(ds) {
    check_spec(data[[ds]], spec, ds, decode = decode, checks = checks)
  })
  out <- .bind_findings(parts)
  # Remember the checked scope so the print header is meaningful even when no
  # dataset has a finding (the stacked frame is then empty).
  attr(out, "artoo.study_scope") <- nms
  class(out) <- c("artoo_study_findings", "artoo_findings", "data.frame")
  out
}

#' @export
print.artoo_study_findings <- function(x, ...) {
  # A column subset keeps the class but not the report shape; defer to the
  # plain data frame print in that case (mirrors print.artoo_findings).
  need <- c("check", "severity", "dataset", "variable", "message")
  if (!all(need %in% names(x))) {
    return(print.data.frame(x, ...))
  }
  scope <- attr(x, "artoo.study_scope", exact = TRUE)
  n_ds <- if (!is.null(scope)) {
    length(scope)
  } else {
    length(unique(x$dataset[!is.na(x$dataset)]))
  }
  n_err <- sum(x$severity == "error")
  n_warn <- sum(x$severity == "warning")
  n_note <- sum(x$severity == "note")
  cat(sprintf(
    "<artoo_study_findings> %d dataset%s: %d error%s, %d warning%s, %d note%s\n",
    n_ds,
    if (n_ds == 1L) "" else "s",
    n_err,
    if (n_err == 1L) "" else "s",
    n_warn,
    if (n_warn == 1L) "" else "s",
    n_note,
    if (n_note == 1L) "" else "s"
  ))
  if (!nrow(x)) {
    cat("No findings. Every dataset conforms to the spec.\n")
    return(invisible(x))
  }
  # The study-level headline: how many of each check, per dataset. Strip the
  # table's dimension-name labels so it prints as a clean count matrix.
  m <- unclass(table(x$dataset, x$check))
  names(dimnames(m)) <- NULL
  cat("\n")
  print(m)
  cat(
    "\ni Treat this as a findings frame: filter by severity,",
    "or pass it to repair_spec().\n"
  )
  invisible(x)
}
