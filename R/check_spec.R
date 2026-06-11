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
#' checked are: missing variables (split into mandatory, an error, and
#' permissible, a warning), extra variables (data column the spec does not
#' declare), type mismatch, character length overflow, the hard 200-byte XPORT
#' v5 / FDA character limit, codelist membership, label drift against the spec,
#' key uniqueness, and displayFormat validity.
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

  # Missing variables, split by obligation: a missing mandatory variable (or one
  # whose mandatory flag is NA, treated conservatively as mandatory) is an error
  # (missing_variable); a missing permissible variable is a warning
  # (missing_permissible). Each bucket has its own toggle.
  if (checks$missing_variable || checks$missing_permissible) {
    miss <- setdiff(vars$variable, names(x))
    mand <- .is_mandatory(vars$mandatory[match(miss, vars$variable)])
    if (checks$missing_variable) {
      mv <- miss[mand]
      found[[length(found) + 1L]] <- .finding(
        "missing_variable",
        dataset,
        mv,
        sprintf("Spec variable '%s' is absent from the data.", mv)
      )
    }
    if (checks$missing_permissible) {
      mp <- miss[!mand]
      found[[length(found) + 1L]] <- .finding(
        "missing_permissible",
        dataset,
        mp,
        sprintf("Permissible spec variable '%s' is absent from the data.", mp)
      )
    }
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

  # XPORT naming rules on the ACTUAL columns (the spec-side
  # variable_name_length rule covers declared names; this one also catches
  # extra/renamed columns and bad characters before a write aborts).
  if (checks$variable_name) {
    bad <- .xpt_name_problems(names(x))
    found[[length(found) + 1L]] <- .finding(
      "variable_name",
      dataset,
      names(bad),
      sprintf("Column name '%s' %s.", names(bad), unname(bad))
    )
  }
  if (checks$dataset_name) {
    badds <- .xpt_name_problems(dataset)
    found[[length(found) + 1L]] <- .finding(
      "dataset_name",
      dataset,
      NA_character_,
      sprintf("Dataset name '%s' %s.", names(badds), unname(badds))
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

    # Hard SAS XPORT v5 / FDA cap, independent of the spec's declared length:
    # a character value may not exceed 200 bytes.
    if (checks$char_length_limit && is.character(col)) {
      maxb <- max(nchar(col, type = "bytes"), 0L, na.rm = TRUE)
      if (maxb > 200L) {
        found[[length(found) + 1L]] <- .finding(
          "char_length_limit",
          dataset,
          v,
          sprintf(
            "'%s' has values up to %d bytes, over the 200-byte XPORT v5 limit.",
            v,
            maxb
          )
        )
      }
    }

    # 32-bit overflow: an integer-typed variable carried as double (or text)
    # can hold values R's integer cannot; coercion would turn them NA.
    if (checks$integer_overflow && identical(dt, "integer")) {
      nv <- suppressWarnings(as.numeric(col))
      over <- !is.na(nv) & abs(nv) > .Machine$integer.max
      if (any(over)) {
        found[[length(found) + 1L]] <- .finding(
          "integer_overflow",
          dataset,
          v,
          sprintf(
            "'%s' has %d value(s) beyond R's 32-bit integer range (max %s); coercion would lose them to NA.",
            v,
            sum(over),
            format(.Machine$integer.max, big.mark = ",")
          )
        )
      }
    }

    # Label-attribute byte limit (the spec-side variable_label_length rule
    # covers spec labels; this one catches labels carried only as attributes).
    if (checks$label_length) {
      col_lab <- attr(col, "label", exact = TRUE)
      if (!is.null(col_lab)) {
        labb <- nchar(as.character(col_lab), type = "bytes")
        if (labb > 40L) {
          found[[length(found) + 1L]] <- .finding(
            "label_length",
            dataset,
            v,
            sprintf(
              "'%s' label attribute is %d bytes, over the 40-byte XPORT v5 / FDA limit.",
              v,
              labb
            )
          )
        }
      }
    }

    if (checks$label_match) {
      col_lab <- attr(col, "label", exact = TRUE)
      spec_lab <- vars$label[i]
      if (
        !is.null(col_lab) &&
          !.blank(spec_lab) &&
          !identical(as.character(col_lab), as.character(spec_lab))
      ) {
        found[[length(found) + 1L]] <- .finding(
          "label_match",
          dataset,
          v,
          sprintf(
            "'%s' label '%s' differs from the spec label '%s'.",
            v,
            as.character(col_lab),
            as.character(spec_lab)
          )
        )
      }
    }

    clid <- vars$codelist_id[i]
    if (
      (checks$codelist_membership || checks$codelist_membership_extensible) &&
        !is.na(clid)
    ) {
      clrows <- spec_codelists(spec, clid)
      # An extensible codelist (extended = TRUE) enumerates examples, not the
      # closed universe: a non-member is a note (sponsor term), not an error.
      extensible <- "extended" %in%
        names(clrows) &&
        any(clrows$extended %in% TRUE)
      check_id <- if (extensible) {
        "codelist_membership_extensible"
      } else {
        "codelist_membership"
      }
      run <- if (extensible) {
        checks$codelist_membership_extensible
      } else {
        checks$codelist_membership
      }
      if (run) {
        terms <- if (decode == "to_decode") clrows$decode else clrows$term
        terms <- terms[!is.na(terms)]
        mand <- "mandatory" %in% names(vars) && isTRUE(vars$mandatory[i])
        bad <- .codelist_violations(col, terms, mand)
        if (length(bad)) {
          shown <- ifelse(is.na(bad), "<NA>", as.character(bad))
          found[[length(found) + 1L]] <- .finding(
            check_id,
            dataset,
            v,
            sprintf(
              "'%s' has %d value(s) outside %scodelist '%s': %s.",
              v,
              length(bad),
              if (extensible) "extensible " else "",
              clid,
              paste(shown[seq_len(min(5L, length(shown)))], collapse = ", ")
            )
          )
        }
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

  # Dataset-level: the spec-declared key variables must uniquely identify the
  # rows. Short-circuit unless every key column is present (an absent key is
  # missing_variable's job). An all-NA key row pastes to "NA" and a repeated
  # NA-key counts as a duplicate, which is correct: a key should not be NA.
  if (checks$key_uniqueness) {
    keys <- spec_keys(spec, dataset)
    if (length(keys) && all(keys %in% names(x))) {
      z <- do.call(paste, c(x[keys], sep = "\x1f"))
      ndup <- sum(duplicated(z) | duplicated(z, fromLast = TRUE))
      if (ndup) {
        found[[length(found) + 1L]] <- .finding(
          "key_uniqueness",
          dataset,
          NA_character_,
          sprintf(
            "Key (%s) is not unique: %d row(s) share a duplicate key.",
            paste(keys, collapse = ", "),
            ndup
          )
        )
      }
    }
  }

  .bind_findings(found)
}

# XPORT naming problems for a vector of names: returns a named character
# vector (name -> problem phrase), empty when all conform. The v5 profile is
# 1-8 ASCII letters/digits/underscore not starting with a digit; v8 extends
# the length to 32. One phrase per name (the worst problem wins).
#' @noRd
.xpt_name_problems <- function(nms) {
  out <- character(0)
  n <- nchar(nms)
  bad_chars <- !grepl("^[A-Za-z_][A-Za-z0-9_]*$", nms)
  for (i in seq_along(nms)) {
    if (bad_chars[i]) {
      out[nms[
        i
      ]] <- "contains characters outside ASCII letters, digits, and underscore"
    } else if (n[i] > 32L) {
      out[nms[i]] <- sprintf(
        "is %d characters, over the 32-character XPORT v8 limit",
        n[i]
      )
    } else if (n[i] > 8L) {
      out[nms[i]] <- sprintf(
        "is %d characters, over the 8-character XPORT v5 limit",
        n[i]
      )
    }
  }
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
