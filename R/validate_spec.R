# validate_spec.R -- public, self-contained spec validation.
#
# Beyond the structural validation that vport_spec() runs at construction,
# validate_spec() checks submission-readiness with vport's own bundled,
# intrinsic rules (no external rule engine, no heraldrules dependency). It
# returns findings invisibly when clean and throws on any error-severity
# finding ("throw as we find").

# Build the findings table for a spec. Columns: check, dataset, variable,
# severity ("error" | "warning" | "note"), message.
#' @noRd
.spec_findings <- function(spec) {
  rows <- list()
  add <- function(
    check,
    severity,
    message,
    dataset = NA_character_,
    variable = NA_character_
  ) {
    rows[[length(rows) + 1L]] <<- data.frame(
      check = check,
      dataset = dataset,
      variable = variable,
      severity = severity,
      message = message,
      stringsAsFactors = FALSE
    )
  }

  dsets <- spec@datasets
  vars <- spec@variables

  # Dataset labels present (submission expectation).
  if (nrow(dsets)) {
    for (i in seq_len(nrow(dsets))) {
      lab <- if ("label" %in% names(dsets)) dsets$label[[i]] else NA_character_
      if (is.na(lab) || !nzchar(lab)) {
        add(
          "dataset_label",
          "warning",
          sprintf("Dataset '%s' has no label.", dsets$dataset[[i]]),
          dataset = dsets$dataset[[i]]
        )
      }
    }
  }

  # Variable-level checks.
  if (nrow(vars)) {
    for (i in seq_len(nrow(vars))) {
      ds <- vars$dataset[[i]]
      v <- vars$variable[[i]]
      lab <- if ("label" %in% names(vars)) vars$label[[i]] else NA_character_
      if (is.na(lab) || !nzchar(lab)) {
        add(
          "variable_label",
          "note",
          sprintf("Variable %s.%s has no label.", ds, v),
          dataset = ds,
          variable = v
        )
      }
      len <- if ("length" %in% names(vars)) vars$length[[i]] else NA_integer_
      if (!is.na(len) && len <= 0L) {
        add(
          "variable_length",
          "error",
          sprintf("Variable %s.%s has non-positive length (%d).", ds, v, len),
          dataset = ds,
          variable = v
        )
      }
      sd <- if ("significant_digits" %in% names(vars)) {
        vars$significant_digits[[i]]
      } else {
        NA_integer_
      }
      if (!is.na(sd) && sd < 0L) {
        add(
          "variable_significant_digits",
          "error",
          sprintf("Variable %s.%s has negative significant_digits.", ds, v),
          dataset = ds,
          variable = v
        )
      }
    }
  }

  # Sort keys must reference variables present in the dataset.
  for (ds in spec_datasets(spec)) {
    keys <- spec_keys(spec, ds)
    if (!length(keys)) {
      next
    }
    present <- vars$variable[!is.na(vars$dataset) & vars$dataset == ds]
    missing <- setdiff(keys, present)
    if (length(missing)) {
      add(
        "key_resolves",
        "error",
        sprintf(
          "Dataset '%s' keys reference variable(s) not in the spec: %s.",
          ds,
          paste(missing, collapse = ", ")
        ),
        dataset = ds
      )
    }
  }

  if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(
      check = character(0),
      dataset = character(0),
      variable = character(0),
      severity = character(0),
      message = character(0),
      stringsAsFactors = FALSE
    )
  }
}

#' Validate a specification for submission-readiness
#'
#' Run vport's intrinsic, self-contained checks over a `vport_spec` and
#' report what would block a clean submission. Structural validity (required
#' columns, types, cross-slot references) is already guaranteed by
#' [vport_spec()] at construction; `validate_spec()` adds the
#' submission-readiness layer (labels present, sort keys resolvable, length
#' and significant-digits sane). It returns the findings invisibly when the
#' spec is clean and aborts the moment an error-severity issue is found.
#'
#' @details
#' **Self-contained.** The rule set is bundled in vport; there is no external
#' rule-engine dependency. The set is deliberately thin and intrinsic, not a
#' full Define-XML conformance engine.
#'
#' @param spec *The specification to validate.*
#'   `<vport_spec>: required`. Build one with [vport_spec()].
#'
#' @return *A data frame of findings* (`check`, `dataset`, `variable`,
#'   `severity`, `message`), returned invisibly when no error-severity
#'   finding exists. Aborts with class `vport_error_validation` otherwise.
#'
#' @examples
#' # ---- Example 1: a clean spec returns its findings invisibly ----
#' #
#' # The bundled CDISC demo spec is fully labelled with resolvable keys, so it
#' # passes; the findings data frame comes back (here empty).
#' ds <- cdisc_datasets
#' ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
#' spec <- vport_spec(ds, cdisc_variables, codelists = cdisc_codelists)
#' validate_spec(spec)
#'
#' # ---- Example 2: catch the error instead of stopping ----
#' #
#' # Point a key at a variable that is not in the spec: that is an
#' # error-severity finding, so validate_spec() throws. Catch it to inspect.
#' bad_ds <- cdisc_datasets
#' bad_ds$keys[bad_ds$dataset == "DM"] <- "NOTAVAR"
#' bad <- vport_spec(bad_ds, cdisc_variables, codelists = cdisc_codelists)
#' tryCatch(
#'   validate_spec(bad),
#'   vport_error_validation = function(e) conditionMessage(e)
#' )
#'
#' @seealso [vport_spec()] to build a spec; [spec_variables()] to inspect it.
#' @export
validate_spec <- function(spec) {
  call <- rlang::caller_env()
  .check_spec_arg(spec, call)
  findings <- .spec_findings(spec)
  err <- findings[findings$severity == "error", , drop = FALSE]
  if (nrow(err)) {
    msgs <- utils::head(err$message, 3L)
    cli::cli_abort(
      c(
        "Spec is not submission-ready, {nrow(err)} error-severity finding{?s}.",
        stats::setNames(msgs, rep("x", length(msgs))),
        "i" = "Inspect every finding in the returned data frame."
      ),
      class = "vport_error_validation",
      call = call
    )
  }
  invisible(findings)
}
