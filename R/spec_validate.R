# spec_validate.R -- S7 validators for artoo_spec and artoo_meta.
#
# These run at construction (the last line of defence behind the friendly
# artoo_spec() constructor). Each returns NULL when valid or a character
# vector of issues, which S7 reports.

# Check one slot's required columns and storage types. Returns a character
# vector of issues (empty when clean). A slot with no columns and no rows is
# treated as uninitialised and skipped.
#' @noRd
.validate_slot <- function(df, schema, req, slot) {
  if (ncol(df) == 0L && nrow(df) == 0L) {
    return(character(0))
  }
  issues <- character(0)
  missing <- setdiff(req, names(df))
  if (length(missing)) {
    issues <- c(
      issues,
      sprintf(
        "spec slot `%s` is missing required column%s: %s.",
        slot,
        if (length(missing) > 1L) "s" else "",
        paste(missing, collapse = ", ")
      )
    )
  }
  for (nm in intersect(names(schema), names(df))) {
    want <- schema[[nm]]
    got <- df[[nm]]
    ok <- switch(
      want,
      character = is.character(got),
      integer = is.integer(got),
      numeric = ,
      double = is.numeric(got),
      logical = is.logical(got),
      TRUE
    )
    if (!ok) {
      issues <- c(
        issues,
        sprintf(
          "spec slot `%s` column `%s` must be %s, not %s.",
          slot,
          nm,
          want,
          class(got)[[1]]
        )
      )
    }
  }
  issues
}

#' Validate a artoo_spec
#' @noRd
.spec_validate <- function(self) {
  issues <- character(0)

  # One spec = one standard: the property is a scalar (NA permitted).
  if (length(self@standard) != 1L) {
    issues <- c(
      issues,
      sprintf(
        "@standard must be a single value (NA when unspecified), not length %d.",
        length(self@standard)
      )
    )
  }

  issues <- c(
    issues,
    .validate_slot(
      self@datasets,
      .spec_cols_datasets,
      .spec_req_datasets,
      "datasets"
    ),
    .validate_slot(
      self@variables,
      .spec_cols_variables,
      .spec_req_variables,
      "variables"
    ),
    .validate_slot(
      self@codelists,
      .spec_cols_codelists,
      .spec_req_codelists,
      "codelists"
    ),
    .validate_slot(
      self@methods,
      .spec_cols_methods,
      .spec_req_methods,
      "methods"
    ),
    .validate_slot(
      self@comments,
      .spec_cols_comments,
      .spec_req_comments,
      "comments"
    ),
    .validate_slot(
      self@documents,
      .spec_cols_documents,
      .spec_req_documents,
      "documents"
    )
  )

  vars <- self@variables
  dsets <- self@datasets
  clists <- self@codelists

  # Variable data types must be canonical CDISC dataTypes.
  if ("data_type" %in% names(vars) && nrow(vars)) {
    bad <- vars$data_type[
      !is.na(vars$data_type) & !(vars$data_type %in% .cdisc_datatypes)
    ]
    if (length(bad)) {
      issues <- c(
        issues,
        sprintf(
          "variables$data_type has non-CDISC value%s: %s.",
          if (length(unique(bad)) > 1L) "s" else "",
          paste(unique(bad), collapse = ", ")
        )
      )
    }
  }

  # target_data_type, when present, must be in the CDISC set.
  if ("target_data_type" %in% names(vars) && nrow(vars)) {
    bad <- vars$target_data_type[
      !is.na(vars$target_data_type) &
        !(vars$target_data_type %in% .cdisc_targettypes)
    ]
    if (length(bad)) {
      issues <- c(
        issues,
        sprintf(
          "variables$target_data_type must be one of %s; got %s.",
          paste(.cdisc_targettypes, collapse = ", "),
          paste(unique(bad), collapse = ", ")
        )
      )
    }
  }

  # Duplicate (dataset, variable) definitions are ambiguous (which label?
  # which type?); the friendly constructor reports the exact rows, this is
  # the last line of defence.
  if (all(c("dataset", "variable") %in% names(vars)) && nrow(vars)) {
    key <- paste(vars$dataset, vars$variable, sep = ".")
    keyed <- !is.na(vars$dataset) & !is.na(vars$variable)
    dup <- unique(key[keyed][duplicated(key[keyed])])
    if (length(dup)) {
      issues <- c(
        issues,
        sprintf(
          "variables define duplicate (dataset, variable) pair%s: %s.",
          if (length(dup) > 1L) "s" else "",
          paste(utils::head(dup, 5L), collapse = ", ")
        )
      )
    }
  }

  # Cross-slot: every variable's dataset must exist in datasets.
  if (
    all(c("dataset") %in% names(vars)) &&
      "dataset" %in% names(dsets) &&
      nrow(vars) &&
      nrow(dsets)
  ) {
    orphan <- setdiff(unique(vars$dataset), dsets$dataset)
    orphan <- orphan[!is.na(orphan)]
    if (length(orphan)) {
      issues <- c(
        issues,
        sprintf(
          "variables reference dataset%s not in `datasets`: %s.",
          if (length(orphan) > 1L) "s" else "",
          paste(orphan, collapse = ", ")
        )
      )
    }
  }

  # Cross-slot: every codelist_id used must resolve in codelists.
  if ("codelist_id" %in% names(vars) && nrow(vars)) {
    used <- unique(vars$codelist_id[
      !is.na(vars$codelist_id) & nzchar(vars$codelist_id)
    ])
    known <- if ("codelist_id" %in% names(clists)) {
      unique(clists$codelist_id)
    } else {
      character(0)
    }
    unresolved <- setdiff(used, known)
    if (length(unresolved)) {
      issues <- c(
        issues,
        sprintf(
          "variables reference unresolved codelist_id%s: %s.",
          if (length(unresolved) > 1L) "s" else "",
          paste(unresolved, collapse = ", ")
        )
      )
    }
  }

  if (length(issues)) issues else NULL
}

#' Validate a artoo_meta
#' @noRd
.meta_validate <- function(self) {
  issues <- character(0)
  cols <- self@columns
  if (length(cols)) {
    if (is.null(names(cols)) || any(!nzchar(names(cols)))) {
      issues <- c(
        issues,
        "artoo_meta@columns must be a named list (keyed by variable)."
      )
    }
    for (nm in names(cols)) {
      col <- cols[[nm]]
      # List key and the column's own `name` must agree, or keyed lookups
      # (keys, codelist projection, col_select) silently target the wrong row.
      if (!is.null(col$name) && !identical(as.character(col$name), nm)) {
        issues <- c(
          issues,
          sprintf(
            "artoo_meta column `%s` has a mismatched name field: %s.",
            nm,
            as.character(col$name)
          )
        )
      }
      dt <- col$dataType %||% col$data_type
      if (!is.null(dt) && !(dt %in% .cdisc_datatypes)) {
        issues <- c(
          issues,
          sprintf(
            "artoo_meta column `%s` has non-CDISC dataType: %s.",
            nm,
            dt
          )
        )
      }
      tdt <- col$targetDataType
      if (!is.null(tdt) && !(tdt %in% .cdisc_targettypes)) {
        issues <- c(
          issues,
          sprintf(
            "artoo_meta column `%s` has non-CDISC targetDataType: %s.",
            nm,
            tdt
          )
        )
      }
      for (fld in c("length", "keySequence")) {
        v <- col[[fld]]
        if (!is.null(v) && (length(v) != 1L || !is.numeric(v) || is.na(v))) {
          issues <- c(
            issues,
            sprintf(
              "artoo_meta column `%s` has a non-integer %s.",
              nm,
              fld
            )
          )
        }
      }
    }
  }
  keys <- self@dataset$keys
  if (!is.null(keys) && length(cols)) {
    missing <- setdiff(keys, names(cols))
    if (length(missing)) {
      issues <- c(
        issues,
        sprintf(
          "artoo_meta@dataset$keys reference unknown column%s: %s.",
          if (length(missing) > 1L) "s" else "",
          paste(missing, collapse = ", ")
        )
      )
    }
  }
  if (length(issues)) issues else NULL
}
