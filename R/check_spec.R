# check_spec.R -- the thin, self-contained conformance check.
#
# check_spec() compares a data frame against one dataset's spec and returns
# a findings data frame. It reuses the exact metadata already in the spec
# (labels, types, lengths, codelists, keys), so it needs no external rule
# catalog -- distinct from validate_spec(), which checks the spec's own
# internal integrity. apply_spec(check=) runs this and attaches the result.

# Empty findings frame (the canonical column shape).
#' @noRd
.no_findings <- function() {
  data.frame(
    check = character(0),
    variable = character(0),
    severity = character(0),
    message = character(0),
    stringsAsFactors = FALSE
  )
}

# One finding row.
#' @noRd
.cs_finding <- function(check, variable, severity, message) {
  data.frame(
    check = check,
    variable = variable,
    severity = severity,
    message = message,
    stringsAsFactors = FALSE
  )
}

#' Check a dataset against its spec
#'
#' Compare a data frame to one dataset's specification and report where they
#' diverge. This is the thin conformance check that sits at the end of the
#' vport workflow (spec -> apply_spec -> check_spec): it reuses the metadata
#' the spec already carries (variables, types, lengths, codelists, keys), so
#' it needs no rule catalog. It is distinct from [validate_spec()], which
#' checks the spec's own internal integrity rather than data.
#'
#' @details
#' **Findings, not enforcement.** `check_spec()` never modifies data; it
#' returns every divergence it finds. [apply_spec()] runs it and decides
#' what to do via its `check` argument (warn, strict, off). The dimensions
#' checked are: missing variables (spec variable absent from the data),
#' extra variables (data column the spec does not declare), type mismatch,
#' character length overflow, and codelist membership.
#'
#' @param x *The data frame to check.* `<data.frame>: required`. Typically
#'   the output of [apply_spec()], but any frame works.
#' @param spec *The specification to check against.* `<vport_spec>:
#'   required`.
#' @param dataset *The dataset whose rules apply.* `<character(1)>:
#'   required`.
#'
#'   **Restriction:** must name a dataset in `spec` (see [spec_datasets()]).
#' @param checks *Which conformance dimensions to evaluate.* `<vport_checks>
#'   | NULL`. When `NULL` (default) every dimension runs; build a control
#'   with [vport_checks()] to disable some.
#'
#' @return *A findings data frame* with columns `check`, `variable`,
#'   `severity` (`"error"` or `"warning"`), and `message`, one row per
#'   divergence. Zero rows means the data conforms.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: a conformed dataset has no findings ----
#' #
#' # apply_spec() scaffolds, coerces, and orders to spec; checking the result
#' # against the same spec returns zero rows.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", check = "off")
#' nrow(check_spec(adsl, spec, "ADSL"))
#'
#' # ---- Example 2: raw data surfaces divergences ----
#' #
#' # Checking a frame with an undeclared column flags it as an extra variable.
#' raw <- cdisc_adsl
#' raw$NOTASPEC <- 1
#' check_spec(raw, spec, "DM")[, c("check", "variable", "severity")]
#'
#' @seealso [apply_spec()] which runs this; [vport_checks()] to select
#'   dimensions; [validate_spec()] for spec integrity.
#' @export
check_spec <- function(x, spec, dataset, checks = NULL) {
  call <- rlang::caller_env()
  checks <- .check_checks_arg(checks, call = call)
  if (!is.data.frame(x)) {
    cli::cli_abort(
      c(
        "{.arg x} must be a data frame.",
        "x" = "You supplied {.obj_type_friendly {x}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  .check_spec_arg(spec, call = call)
  .check_dataset_arg(spec, dataset, call = call)

  vars <- spec_variables(spec, dataset)
  found <- list()

  # Missing / extra variables.
  if (checks$missing_variable) {
    for (v in setdiff(vars$variable, names(x))) {
      found[[length(found) + 1L]] <- .cs_finding(
        "missing_variable",
        v,
        "error",
        sprintf("Spec variable '%s' is absent from the data.", v)
      )
    }
  }
  if (checks$extra_variable) {
    for (v in setdiff(names(x), vars$variable)) {
      found[[length(found) + 1L]] <- .cs_finding(
        "extra_variable",
        v,
        "warning",
        sprintf("Column '%s' is not declared in the spec.", v)
      )
    }
  }

  # Per-variable: type mismatch, length overflow, codelist membership.
  for (i in seq_len(nrow(vars))) {
    v <- vars$variable[i]
    if (!(v %in% names(x))) {
      next
    }
    col <- x[[v]]
    dt <- vars$data_type[i]

    if (checks$type_mismatch && !is.na(dt)) {
      want <- .type_storage(dt)
      have <- .storage_of(col)
      if (!is.na(have) && have != want) {
        found[[length(found) + 1L]] <- .cs_finding(
          "type_mismatch",
          v,
          "warning",
          sprintf(
            "'%s' is stored as %s but the spec dataType '%s' wants %s.",
            v,
            have,
            dt,
            want
          )
        )
      }
    }

    len <- vars$length[i]
    if (checks$length_overflow && !is.na(len) && is.character(col)) {
      over <- max(nchar(col), 0L, na.rm = TRUE)
      if (over > len) {
        found[[length(found) + 1L]] <- .cs_finding(
          "length_overflow",
          v,
          "warning",
          sprintf(
            "'%s' has values up to %d chars but the spec length is %d.",
            v,
            over,
            as.integer(len)
          )
        )
      }
    }

    clid <- vars$codelist_id[i]
    if (checks$codelist_membership && !is.na(clid)) {
      terms <- spec_codelist(spec, clid)$term
      vals <- as.character(col)
      bad <- unique(vals[!is.na(vals) & !(vals %in% terms)])
      if (length(bad)) {
        found[[length(found) + 1L]] <- .cs_finding(
          "codelist_membership",
          v,
          "error",
          sprintf(
            "'%s' has %d value(s) outside codelist '%s': %s.",
            v,
            length(bad),
            clid,
            paste(bad[seq_len(min(5L, length(bad)))], collapse = ", ")
          )
        )
      }
    }
  }

  if (!length(found)) {
    return(.no_findings())
  }
  out <- do.call(rbind, found)
  rownames(out) <- NULL
  out
}

# The vport storage mode of a column ("character"/"integer"/"double"/
# "logical"), matching .type_storage()'s vocabulary. Factors read as
# character; NA for anything exotic.
#' @noRd
.storage_of <- function(col) {
  if (is.factor(col) || is.character(col)) {
    "character"
  } else if (is.integer(col)) {
    "integer"
  } else if (is.double(col)) {
    "double"
  } else if (is.logical(col)) {
    "logical"
  } else {
    NA_character_
  }
}
