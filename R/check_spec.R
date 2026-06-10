# check_spec.R -- the data-conformance checker (engine == "data").
#
# check_spec() compares a data frame against one dataset's spec and returns a
# findings data frame. It reuses the metadata already in the spec (labels,
# types, lengths, codelists, keys) and builds findings through the shared
# catalog-driven .finding() (findings.R), so it emits the same 6-column shape
# as validate_spec() and its severities come from the same rule catalog. It is
# distinct from validate_spec(), which checks the spec's own integrity (engine
# == "spec"). apply_spec(on_error=) runs this and attaches the result.

#' Check a dataset against its spec
#'
#' Compare a data frame to one dataset's specification and report where they
#' diverge. This is the data-conformance check at the end of the vport
#' workflow (spec -> apply_spec -> check_spec): it reuses the metadata the
#' spec already carries (variables, types, lengths, codelists, keys). It is
#' distinct from [validate_spec()], which checks the spec's own internal
#' integrity rather than the data. Both report findings keyed to the same open
#' rule catalog.
#'
#' @details
#' **Findings, not enforcement.** `check_spec()` never modifies data; it
#' returns every divergence it finds. [apply_spec()] runs it and decides what
#' to do via its `on_error` argument (warn, abort, off). The dimensions
#' checked are: missing variables (spec variable absent from the data), extra
#' variables (data column the spec does not declare), type mismatch, character
#' length overflow, codelist membership, and displayFormat validity.
#'
#' **Decode-aware membership.** `decode` selects which codelist column the
#' data is checked against, matching [apply_spec()]'s decode step:
#' `"none"`/`"to_code"` check against the codelist `term`s, `"to_decode"`
#' against the `decode`s. [apply_spec()] threads its own `decode` through, so
#' a decoded column is not wrongly flagged.
#'
#' @param x *The data frame to check.* `<data.frame>: required`. Typically
#'   the output of [apply_spec()], but any frame works.
#' @param spec *The specification to check against.* `<vport_spec>:
#'   required`.
#' @param dataset *The dataset whose rules apply.* `<character(1)>:
#'   required`.
#'
#'   **Restriction:** must name a dataset in `spec` (see [spec_datasets()]).
#' @param decode *Which codelist column membership is checked against.*
#'   `<character(1)>`. One of `"none"` (default), `"to_decode"`, or
#'   `"to_code"`.
#' @param checks *Which conformance dimensions to evaluate.* `<vport_checks>
#'   | NULL`. When `NULL` (default) every dimension runs; build a control
#'   with [vport_checks()] to disable some.
#'
#' @return *A findings data frame* with columns `check`, `dimension`,
#'   `severity` (`"error"`, `"warning"`, or `"note"`), `dataset`, `variable`,
#'   and `message`, one row per divergence. Zero rows means the data conforms.
#'
#' @examples
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: a conformed dataset has no findings ----
#' #
#' # apply_spec() scaffolds, coerces, and orders to spec; checking the result
#' # against the same spec returns zero rows.
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL", on_error = "off")
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
check_spec <- function(
  x,
  spec,
  dataset,
  decode = c("none", "to_decode", "to_code"),
  checks = NULL
) {
  call <- rlang::caller_env()
  decode <- match.arg(decode)
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
    miss <- setdiff(vars$variable, names(x))
    found[[length(found) + 1L]] <- .finding(
      "missing_variable",
      dataset,
      miss,
      sprintf("Spec variable '%s' is absent from the data.", miss)
    )
  }
  if (checks$extra_variable) {
    extra <- setdiff(names(x), vars$variable)
    found[[length(found) + 1L]] <- .finding(
      "extra_variable",
      dataset,
      extra,
      sprintf("Column '%s' is not declared in the spec.", extra)
    )
  }

  # Per-variable: type mismatch, length overflow, codelist membership,
  # displayFormat validity.
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
        found[[length(found) + 1L]] <- .finding(
          "type_mismatch",
          dataset,
          v,
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
      over <- max(nchar(col, type = "bytes"), 0L, na.rm = TRUE)
      if (over > len) {
        found[[length(found) + 1L]] <- .finding(
          "length_overflow",
          dataset,
          v,
          sprintf(
            "'%s' has values up to %d bytes but the spec length is %d.",
            v,
            over,
            as.integer(len)
          )
        )
      }
    }

    clid <- vars$codelist_id[i]
    if (checks$codelist_membership && !is.na(clid)) {
      clrows <- spec_codelists(spec, clid)
      terms <- if (decode == "to_decode") clrows$decode else clrows$term
      terms <- terms[!is.na(terms)]
      mand <- "mandatory" %in% names(vars) && isTRUE(vars$mandatory[i])
      bad <- .codelist_violations(col, terms, mand)
      if (length(bad)) {
        shown <- ifelse(is.na(bad), "<NA>", as.character(bad))
        found[[length(found) + 1L]] <- .finding(
          "codelist_membership",
          dataset,
          v,
          sprintf(
            "'%s' has %d value(s) outside codelist '%s': %s.",
            v,
            length(bad),
            clid,
            paste(shown[seq_len(min(5L, length(shown)))], collapse = ", ")
          )
        )
      }
    }

    fmt <- vars$display_format[i]
    if (
      checks$display_format &&
        dt %in% c("date", "datetime", "time") &&
        !is.na(fmt)
    ) {
      fmt_name <- .parse_format_str(fmt)$name
      ok <- switch(
        dt,
        date = .is_sas_date_format(fmt_name),
        datetime = .is_sas_datetime_format(fmt_name),
        time = .is_sas_time_format(fmt_name)
      )
      if (!isTRUE(ok)) {
        found[[length(found) + 1L]] <- .finding(
          "display_format",
          dataset,
          v,
          sprintf(
            "'%s' is dataType '%s' but displayFormat '%s' is not a recognized SAS %s format.",
            v,
            dt,
            fmt,
            dt
          )
        )
      }
    }
  }

  .bind_findings(found)
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
