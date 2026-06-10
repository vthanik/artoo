# validate_spec.R -- dataset-scoped spec validation -> vport_check.
#
# Each check is a small vectorized `.chk_*` that returns a 0+ row findings
# frame via `.finding()`; validate_spec() binds them once. Severity and
# dimension for every finding come from the open catalog
# (inst/spec_rules.json), the single source of truth, so code and catalog
# cannot drift. vport uses its own behavioral check ids only.

# ---- Catalog loader (cached) --------------------------------------------

.spec_rules_env <- new.env(parent = emptyenv())

# The known dimensions/severities a catalog entry may use.
.spec_dimensions <- c(
  "study",
  "dataset",
  "variable",
  "value",
  "codelist",
  "method",
  "comment",
  "document",
  "ct",
  "arm"
)
.spec_severities <- c("error", "warning", "note")

#' @noRd
.spec_rules <- function() {
  if (is.null(.spec_rules_env$rules)) {
    rlang::check_installed("jsonlite", reason = "to read the rule catalog.")
    path <- system.file("spec_rules.json", package = "vport")
    if (!nzchar(path)) {
      cli::cli_abort(
        "Rule catalog {.file spec_rules.json} is missing from the install.",
        class = "vport_error_validation"
      )
    }
    r <- jsonlite::fromJSON(path, simplifyDataFrame = TRUE)
    .check_rules_df(r)
    .spec_rules_env$rules <- r
  }
  .spec_rules_env$rules
}

# Validate the catalog shape (H20). Aborts on a malformed catalog.
#' @noRd
.check_rules_df <- function(r) {
  need <- c("id", "dimension", "severity", "requires_data", "scope", "status")
  miss <- setdiff(need, names(r))
  if (length(miss)) {
    cli::cli_abort(
      "Rule catalog is missing column{?s}: {.val {miss}}.",
      class = "vport_error_validation"
    )
  }
  if (!all(r$severity %in% .spec_severities)) {
    cli::cli_abort(
      "Rule catalog has an unknown severity.",
      class = "vport_error_validation"
    )
  }
  if (!all(r$dimension %in% .spec_dimensions)) {
    cli::cli_abort(
      "Rule catalog has an unknown dimension.",
      class = "vport_error_validation"
    )
  }
  if (anyDuplicated(r$id)) {
    cli::cli_abort(
      "Rule catalog has duplicate ids.",
      class = "vport_error_validation"
    )
  }
  invisible(r)
}

#' @noRd
.spec_rule <- function(id) {
  r <- .spec_rules()
  row <- r[r$id == id, , drop = FALSE]
  if (nrow(row) != 1L) {
    cli::cli_abort(
      "Unknown check id {.val {id}} (not in the rule catalog).",
      class = "vport_error_validation"
    )
  }
  row
}

# ---- Findings primitives ------------------------------------------------

#' @noRd
.empty_findings <- function() {
  data.frame(
    check = character(0),
    dimension = character(0),
    severity = character(0),
    dataset = character(0),
    variable = character(0),
    message = character(0),
    stringsAsFactors = FALSE
  )
}

# Build a findings frame for one check; dimension/severity come from the
# catalog by check_id. `message` drives the row count; dataset/variable
# recycle. Zero messages -> zero rows.
#' @noRd
.finding <- function(check_id, dataset, variable, message) {
  if (!length(message)) {
    return(.empty_findings())
  }
  meta <- .spec_rule(check_id)
  data.frame(
    check = check_id,
    dimension = meta$dimension,
    severity = meta$severity,
    dataset = dataset,
    variable = variable,
    message = message,
    stringsAsFactors = FALSE
  )
}

#' @noRd
.bind_findings <- function(parts) {
  parts <- Filter(function(x) !is.null(x) && nrow(x), parts)
  if (!length(parts)) {
    return(.empty_findings())
  }
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}

# TRUE where x is NA or empty/whitespace.
#' @noRd
.blank <- function(x) {
  is.na(x) | !nzchar(trimws(as.character(x)))
}

# Non-blank values of one column, or character(0) when absent.
#' @noRd
.refs <- function(df, col) {
  if (is.null(df) || !is.data.frame(df) || !(col %in% names(df))) {
    return(character(0))
  }
  v <- df[[col]]
  unique(trimws(as.character(v[!.blank(v)])))
}

# ---- Scope ---------------------------------------------------------------

# Build the scoped validation view: variables/values filtered to the
# scoped datasets, plus the referenced sub-universe of methods/comments/
# codelists/documents (FK closure), and the full supporting tables for
# resolve/uniqueness checks.
#' @noRd
.scope_spec <- function(spec, dataset) {
  whole <- is.null(dataset)
  all_ds <- spec_datasets(spec)
  scope <- if (whole) all_ds else dataset

  dsets <- spec@datasets
  if (nrow(dsets)) {
    dsets <- dsets[
      !is.na(dsets$dataset) & dsets$dataset %in% scope,
      ,
      drop = FALSE
    ]
  }
  vars <- spec@variables
  if (!whole && nrow(vars)) {
    vars <- vars[!is.na(vars$dataset) & vars$dataset %in% scope, , drop = FALSE]
  }
  vals <- spec@values
  if (!is.data.frame(vals)) {
    vals <- NULL
  } else if (!whole && "dataset" %in% names(vals) && nrow(vals)) {
    vals <- vals[!is.na(vals$dataset) & vals$dataset %in% scope, , drop = FALSE]
  }

  ref_codelist <- unique(c(
    .refs(vars, "codelist_id"),
    .refs(vals, "codelist_id")
  ))
  cl_ref <- spec@codelists
  if (nrow(cl_ref)) {
    cl_ref <- cl_ref[cl_ref$codelist_id %in% ref_codelist, , drop = FALSE]
  }
  ref_method <- unique(c(.refs(vars, "method_id"), .refs(vals, "method_id")))
  ref_comment <- unique(c(
    .refs(vars, "comment_id"),
    .refs(vals, "comment_id"),
    .refs(dsets, "comment_id"),
    .refs(cl_ref, "comment_id")
  ))
  mt_all <- spec@methods
  cm_all <- spec@comments
  mt_ref <- if (nrow(mt_all)) {
    mt_all[mt_all$method_id %in% ref_method, , drop = FALSE]
  } else {
    mt_all
  }
  cm_ref <- if (nrow(cm_all)) {
    cm_all[cm_all$comment_id %in% ref_comment, , drop = FALSE]
  } else {
    cm_all
  }
  ref_document <- unique(c(
    .refs(mt_ref, "document_id"),
    .refs(cm_ref, "document_id")
  ))

  list(
    spec = spec,
    whole = whole,
    scope = scope,
    datasets = dsets,
    variables = vars,
    values = vals,
    codelists_all = spec@codelists,
    codelists_ref = cl_ref,
    methods_all = mt_all,
    comments_all = cm_all,
    documents_all = spec@documents,
    methods_ref = mt_ref,
    comments_ref = cm_ref,
    ref_method = ref_method,
    ref_comment = ref_comment,
    ref_document = ref_document
  )
}

#' @noRd
.study_label <- function(spec) {
  study <- spec@study
  if (!nrow(study)) {
    return("(unspecified)")
  }
  hit <- names(study)[
    tolower(names(study)) %in% c("studyname", "study_name", "studyid")
  ]
  for (nm in hit) {
    v <- as.character(study[[nm]])[1]
    if (!.blank(v)) {
      return(v)
    }
  }
  "(unspecified)"
}

# ---- Checks (Wave 2: all dimensions, headline coverage) -----------------

#' @noRd
.chk_study_name <- function(sc) {
  study <- sc$spec@study
  if (!nrow(study)) {
    return(.finding(
      "study_name_present",
      NA_character_,
      NA_character_,
      "No study-level metadata; the study name is unknown."
    ))
  }
  label <- .study_label(sc$spec)
  if (identical(label, "(unspecified)")) {
    .finding(
      "study_name_present",
      NA_character_,
      NA_character_,
      "Study name is missing or blank."
    )
  } else {
    .empty_findings()
  }
}

#' @noRd
.chk_dataset_label <- function(sc) {
  d <- sc$datasets
  if (!nrow(d) || !("label" %in% names(d))) {
    return(.empty_findings())
  }
  bad <- .blank(d$label)
  .finding(
    "dataset_label_present",
    d$dataset[bad],
    NA_character_,
    sprintf("Dataset '%s' has no label.", d$dataset[bad])
  )
}

#' @noRd
.chk_dataset_keys <- function(sc) {
  parts <- lapply(sc$scope, function(ds) {
    keys <- spec_keys(sc$spec, ds)
    if (!length(keys)) {
      return(NULL)
    }
    present <- sc$variables$variable[
      !is.na(sc$variables$dataset) & sc$variables$dataset == ds
    ]
    missing <- setdiff(keys, present)
    if (!length(missing)) {
      return(NULL)
    }
    .finding(
      "dataset_keys_resolve",
      ds,
      NA_character_,
      sprintf(
        "Dataset '%s' keys reference variables not in the spec: %s.",
        ds,
        paste(missing, collapse = ", ")
      )
    )
  })
  .bind_findings(parts)
}

#' @noRd
.chk_dataset_comment <- function(sc) {
  d <- sc$datasets
  if (!nrow(d) || !("comment_id" %in% names(d))) {
    return(.empty_findings())
  }
  known <- .refs(sc$comments_all, "comment_id")
  bad <- !.blank(d$comment_id) & !(trimws(d$comment_id) %in% known)
  .finding(
    "dataset_comment_resolves",
    d$dataset[bad],
    NA_character_,
    sprintf(
      "Dataset '%s' references undefined comment '%s'.",
      d$dataset[bad],
      d$comment_id[bad]
    )
  )
}

#' @noRd
.chk_variable_label <- function(sc) {
  v <- sc$variables
  if (!nrow(v) || !("label" %in% names(v))) {
    return(.empty_findings())
  }
  bad <- .blank(v$label)
  .finding(
    "variable_label_present",
    v$dataset[bad],
    v$variable[bad],
    sprintf("Variable %s.%s has no label.", v$dataset[bad], v$variable[bad])
  )
}

#' @noRd
.chk_variable_length <- function(sc) {
  v <- sc$variables
  if (!nrow(v) || !("length" %in% names(v))) {
    return(.empty_findings())
  }
  bad <- !is.na(v$length) & v$length <= 0L
  .finding(
    "variable_length_positive",
    v$dataset[bad],
    v$variable[bad],
    sprintf(
      "Variable %s.%s has non-positive length (%d).",
      v$dataset[bad],
      v$variable[bad],
      v$length[bad]
    )
  )
}

#' @noRd
.chk_variable_sigdigits <- function(sc) {
  v <- sc$variables
  if (!nrow(v) || !("significant_digits" %in% names(v))) {
    return(.empty_findings())
  }
  bad <- !is.na(v$significant_digits) & v$significant_digits < 0L
  .finding(
    "variable_sigdigits_nonneg",
    v$dataset[bad],
    v$variable[bad],
    sprintf(
      "Variable %s.%s has negative significant digits.",
      v$dataset[bad],
      v$variable[bad]
    )
  )
}

#' @noRd
.chk_variable_method_resolves <- function(sc) {
  v <- sc$variables
  if (!nrow(v) || !("method_id" %in% names(v))) {
    return(.empty_findings())
  }
  known <- .refs(sc$methods_all, "method_id")
  bad <- !.blank(v$method_id) & !(trimws(v$method_id) %in% known)
  .finding(
    "variable_method_resolves",
    v$dataset[bad],
    v$variable[bad],
    sprintf(
      "Variable %s.%s references undefined method '%s'.",
      v$dataset[bad],
      v$variable[bad],
      v$method_id[bad]
    )
  )
}

#' @noRd
.chk_variable_comment_resolves <- function(sc) {
  v <- sc$variables
  if (!nrow(v) || !("comment_id" %in% names(v))) {
    return(.empty_findings())
  }
  known <- .refs(sc$comments_all, "comment_id")
  bad <- !.blank(v$comment_id) & !(trimws(v$comment_id) %in% known)
  .finding(
    "variable_comment_resolves",
    v$dataset[bad],
    v$variable[bad],
    sprintf(
      "Variable %s.%s references undefined comment '%s'.",
      v$dataset[bad],
      v$variable[bad],
      v$comment_id[bad]
    )
  )
}

#' @noRd
.chk_variable_derived_has_method <- function(sc) {
  v <- sc$variables
  if (!nrow(v) || !("origin" %in% names(v))) {
    return(.empty_findings())
  }
  derived <- !is.na(v$origin) & toupper(trimws(v$origin)) == "DERIVED"
  no_method <- if ("method_id" %in% names(v)) {
    .blank(v$method_id)
  } else {
    rep(TRUE, nrow(v))
  }
  bad <- derived & no_method
  .finding(
    "variable_derived_has_method",
    v$dataset[bad],
    v$variable[bad],
    sprintf(
      "Variable %s.%s has Origin='Derived' but no method.",
      v$dataset[bad],
      v$variable[bad]
    )
  )
}

#' @noRd
.chk_codelist_comment <- function(sc) {
  cl <- sc$codelists_all
  if (!nrow(cl) || !("comment_id" %in% names(cl))) {
    return(.empty_findings())
  }
  # Only referenced codelists are in scope.
  ref <- unique(c(
    .refs(sc$variables, "codelist_id"),
    .refs(sc$values, "codelist_id")
  ))
  cl <- cl[cl$codelist_id %in% ref, , drop = FALSE]
  if (!nrow(cl)) {
    return(.empty_findings())
  }
  known <- .refs(sc$comments_all, "comment_id")
  bad <- !.blank(cl$comment_id) & !(trimws(cl$comment_id) %in% known)
  .finding(
    "codelist_comment_resolves",
    NA_character_,
    cl$codelist_id[bad],
    sprintf(
      "Codelist '%s' references undefined comment '%s'.",
      cl$codelist_id[bad],
      cl$comment_id[bad]
    )
  )
}

# Generic id-uniqueness over a (full) table restricted to referenced ids.
#' @noRd
.chk_id_unique <- function(tbl, key, ref_ids, check_id) {
  if (is.null(tbl) || !nrow(tbl) || !(key %in% names(tbl))) {
    return(.empty_findings())
  }
  ids <- trimws(as.character(tbl[[key]]))
  dup <- unique(ids[duplicated(ids) & !.blank(ids)])
  dup <- dup[dup %in% ref_ids]
  .finding(
    check_id,
    NA_character_,
    dup,
    sprintf("%s '%s' is defined more than once.", key, dup)
  )
}

#' @noRd
.chk_description_present <- function(ref_tbl, key, check_id) {
  if (
    is.null(ref_tbl) || !nrow(ref_tbl) || !("description" %in% names(ref_tbl))
  ) {
    return(.empty_findings())
  }
  bad <- .blank(ref_tbl$description)
  .finding(
    check_id,
    NA_character_,
    ref_tbl[[key]][bad],
    sprintf("%s '%s' has a blank description.", key, ref_tbl[[key]][bad])
  )
}

#' @noRd
.chk_document_resolves <- function(ref_tbl, key, documents_all, check_id) {
  if (
    is.null(ref_tbl) || !nrow(ref_tbl) || !("document_id" %in% names(ref_tbl))
  ) {
    return(.empty_findings())
  }
  known <- .refs(documents_all, "document_id")
  bad <- !.blank(ref_tbl$document_id) &
    !(trimws(ref_tbl$document_id) %in% known)
  .finding(
    check_id,
    NA_character_,
    ref_tbl[[key]][bad],
    sprintf(
      "%s '%s' references undefined document '%s'.",
      key,
      ref_tbl[[key]][bad],
      ref_tbl$document_id[bad]
    )
  )
}

# ---- Wave 3: variable / value-level / codelist breadth + unused ----------

#' @noRd
.chk_variable_order <- function(sc) {
  v <- sc$variables
  if (!nrow(v) || !("order" %in% names(v))) {
    return(.empty_findings())
  }
  bad <- !is.na(v$order) & v$order <= 0L
  .finding(
    "variable_order_positive",
    v$dataset[bad],
    v$variable[bad],
    sprintf(
      "Variable %s.%s has a non-positive order (%d).",
      v$dataset[bad],
      v$variable[bad],
      v$order[bad]
    )
  )
}

#' @noRd
.chk_variable_length_for_text <- function(sc) {
  v <- sc$variables
  if (!nrow(v) || !all(c("data_type", "length") %in% names(v))) {
    return(.empty_findings())
  }
  needs_len <- v$data_type %in% c("string", "integer")
  bad <- needs_len & is.na(v$length)
  .finding(
    "variable_length_for_text",
    v$dataset[bad],
    v$variable[bad],
    sprintf(
      "Variable %s.%s is %s but has no length.",
      v$dataset[bad],
      v$variable[bad],
      v$data_type[bad]
    )
  )
}

# Value-level rows live in the passthrough `values` slot; every check is
# guarded on the column being present.
#' @noRd
.chk_value_resolve <- function(sc, col, parent_ids, check_id, label) {
  vl <- sc$values
  if (is.null(vl) || !nrow(vl) || !(col %in% names(vl))) {
    return(.empty_findings())
  }
  ds <- if ("dataset" %in% names(vl)) vl$dataset else NA_character_
  var <- if ("variable" %in% names(vl)) vl$variable else NA_character_
  bad <- !.blank(vl[[col]]) & !(trimws(vl[[col]]) %in% parent_ids)
  .finding(
    check_id,
    ds[bad],
    var[bad],
    sprintf(
      "Value-level row references undefined %s '%s'.",
      label,
      vl[[col]][bad]
    )
  )
}

#' @noRd
.chk_value_whereclause <- function(sc) {
  vl <- sc$values
  if (is.null(vl) || !nrow(vl) || !("where_clause" %in% names(vl))) {
    return(.empty_findings())
  }
  ds <- if ("dataset" %in% names(vl)) vl$dataset else NA_character_
  var <- if ("variable" %in% names(vl)) vl$variable else NA_character_
  bad <- .blank(vl$where_clause)
  .finding(
    "value_whereclause_present",
    ds[bad],
    var[bad],
    "A value-level row has no where-clause."
  )
}

#' @noRd
.chk_value_variable <- function(sc) {
  vl <- sc$values
  if (
    is.null(vl) || !nrow(vl) || !all(c("dataset", "variable") %in% names(vl))
  ) {
    return(.empty_findings())
  }
  v <- sc$variables
  key <- paste(vl$dataset, vl$variable)
  known <- paste(v$dataset, v$variable)
  bad <- !.blank(vl$variable) & !(key %in% known)
  .finding(
    "value_variable_resolves",
    vl$dataset[bad],
    vl$variable[bad],
    sprintf(
      "Value-level row %s.%s is not a variable in the dataset.",
      vl$dataset[bad],
      vl$variable[bad]
    )
  )
}

#' @noRd
.chk_codelist_terms <- function(sc) {
  cl <- sc$codelists_ref
  if (is.null(cl) || !nrow(cl) || !("codelist_id" %in% names(cl))) {
    return(.empty_findings())
  }
  has_term <- "term" %in% names(cl)
  parts <- lapply(unique(cl$codelist_id), function(id) {
    rows <- cl[cl$codelist_id == id, , drop = FALSE]
    terms <- if (has_term) rows$term[!.blank(rows$term)] else character(0)
    if (length(terms)) {
      return(NULL)
    }
    .finding(
      "codelist_terms_present",
      NA_character_,
      id,
      sprintf("Codelist '%s' defines no terms.", id)
    )
  })
  .bind_findings(parts)
}

# Unreferenced supporting metadata (whole-spec mode only).
#' @noRd
.chk_unused <- function(tbl, key, ref_ids, check_id, label) {
  if (is.null(tbl) || !nrow(tbl) || !(key %in% names(tbl))) {
    return(.empty_findings())
  }
  defined <- unique(trimws(as.character(tbl[[key]])))
  defined <- defined[nzchar(defined)]
  unused <- setdiff(defined, ref_ids)
  .finding(
    check_id,
    NA_character_,
    unused,
    sprintf("%s '%s' is defined but never referenced.", label, unused)
  )
}

# ---- Controlled terminology vs input data (only when data supplied) -----

# Resolve the data frame for one scoped dataset from the `data` argument:
# a single data.frame (single-dataset scope) or a named list keyed by
# dataset. NULL when no data is available for that dataset.
#' @noRd
.scope_data <- function(data, ds, scope, call) {
  if (is.null(data)) {
    return(NULL)
  }
  if (is.data.frame(data)) {
    if (length(scope) != 1L) {
      cli::cli_abort(
        c(
          "A single {.arg data} frame needs a length-1 {.arg dataset}.",
          "x" = "Got {length(scope)} datasets in scope.",
          "i" = "Name the dataset, or pass a named list of data frames."
        ),
        class = "vport_error_input",
        call = call
      )
    }
    return(data)
  }
  if (is.list(data) && !is.null(names(data))) {
    return(data[[ds]])
  }
  cli::cli_abort(
    c(
      "{.arg data} must be a data frame or a named list of data frames.",
      "x" = "You supplied {.obj_type_friendly {data}}."
    ),
    class = "vport_error_input",
    call = call
  )
}

# The codelist terms a value is allowed to take, plus NA-acceptability:
# a mandatory variable's NA is a violation; otherwise NA/"" are allowed
# (after metatools::get_bad_ct). Returns the offending (bad) data values.
#' @noRd
.ct_bad_values <- function(values, terms, mandatory) {
  allow <- trimws(as.character(terms))
  if (!isTRUE(mandatory)) {
    allow <- c(allow, NA_character_, "")
  }
  v <- trimws(as.character(values))
  v_na <- is.na(values)
  ok <- (v %in% allow) | (v_na & !isTRUE(mandatory))
  unique(values[!ok])
}

#' @noRd
.chk_ct <- function(sc, data, call) {
  v <- sc$variables
  if (!nrow(v) || !("codelist_id" %in% names(v))) {
    return(.empty_findings())
  }
  parts <- list()
  for (ds in sc$scope) {
    df <- .scope_data(data, ds, sc$scope, call)
    if (is.null(df) || !is.data.frame(df)) {
      next
    }
    rows <- v[!is.na(v$dataset) & v$dataset == ds, , drop = FALSE]
    for (i in seq_len(nrow(rows))) {
      var <- rows$variable[i]
      clid <- rows$codelist_id[i]
      # Spec variable absent from the data frame.
      if (!(var %in% names(df))) {
        parts[[length(parts) + 1L]] <- .finding(
          "variable_present_in_data",
          ds,
          var,
          sprintf(
            "Variable %s.%s is not a column in the supplied data.",
            ds,
            var
          )
        )
        next
      }
      if (.blank(clid)) {
        next
      }
      terms <- sc$codelists_all$term[
        !is.na(sc$codelists_all$codelist_id) &
          sc$codelists_all$codelist_id == trimws(clid)
      ]
      terms <- terms[!.blank(terms)]
      if (!length(terms)) {
        next
      }
      col <- unique(df[[var]])
      mand <- "mandatory" %in% names(rows) && isTRUE(rows$mandatory[i])

      bad <- .ct_bad_values(col, terms, mand)
      if (length(bad)) {
        shown <- ifelse(is.na(bad), "<NA>", as.character(bad))
        parts[[length(parts) + 1L]] <- .finding(
          "ct_value_in_codelist",
          ds,
          var,
          sprintf(
            "%s.%s has value%s not in codelist %s: %s.",
            ds,
            var,
            if (length(bad) > 1L) "s" else "",
            trimws(clid),
            paste(shown, collapse = ", ")
          )
        )
      }
      data_vals <- trimws(as.character(col[!is.na(col)]))
      unused <- setdiff(trimws(as.character(terms)), data_vals)
      if (length(unused)) {
        parts[[length(parts) + 1L]] <- .finding(
          "ct_term_unused",
          ds,
          var,
          sprintf(
            "Codelist %s term%s not present in %s.%s data: %s.",
            trimws(clid),
            if (length(unused) > 1L) "s" else "",
            ds,
            var,
            paste(unused, collapse = ", ")
          )
        )
      }
    }
  }
  .bind_findings(parts)
}

#' @noRd
.run_checks <- function(sc) {
  parts <- list(
    .chk_study_name(sc),
    .chk_dataset_label(sc),
    .chk_dataset_keys(sc),
    .chk_dataset_comment(sc),
    .chk_variable_label(sc),
    .chk_variable_length(sc),
    .chk_variable_sigdigits(sc),
    .chk_variable_order(sc),
    .chk_variable_length_for_text(sc),
    .chk_variable_method_resolves(sc),
    .chk_variable_comment_resolves(sc),
    .chk_variable_derived_has_method(sc),
    .chk_value_whereclause(sc),
    .chk_value_variable(sc),
    .chk_value_resolve(
      sc,
      "method_id",
      .refs(sc$methods_all, "method_id"),
      "value_method_resolves",
      "method"
    ),
    .chk_value_resolve(
      sc,
      "comment_id",
      .refs(sc$comments_all, "comment_id"),
      "value_comment_resolves",
      "comment"
    ),
    .chk_value_resolve(
      sc,
      "codelist_id",
      .refs(sc$codelists_all, "codelist_id"),
      "value_codelist_resolves",
      "codelist"
    ),
    .chk_codelist_comment(sc),
    .chk_codelist_terms(sc),
    .chk_id_unique(
      sc$methods_all,
      "method_id",
      sc$ref_method,
      "method_id_unique"
    ),
    .chk_description_present(
      sc$methods_ref,
      "method_id",
      "method_description_present"
    ),
    .chk_document_resolves(
      sc$methods_ref,
      "method_id",
      sc$documents_all,
      "method_document_resolves"
    ),
    .chk_id_unique(
      sc$comments_all,
      "comment_id",
      sc$ref_comment,
      "comment_id_unique"
    ),
    .chk_description_present(
      sc$comments_ref,
      "comment_id",
      "comment_description_present"
    ),
    .chk_document_resolves(
      sc$comments_ref,
      "comment_id",
      sc$documents_all,
      "comment_document_resolves"
    ),
    .chk_id_unique(
      sc$documents_all,
      "document_id",
      .refs(sc$documents_all, "document_id"),
      "document_id_unique"
    )
  )
  # Unreferenced checks only make sense across the whole spec.
  if (isTRUE(sc$whole)) {
    parts <- c(
      parts,
      list(
        .chk_unused(
          sc$methods_all,
          "method_id",
          sc$ref_method,
          "method_unused",
          "Method"
        ),
        .chk_unused(
          sc$comments_all,
          "comment_id",
          sc$ref_comment,
          "comment_unused",
          "Comment"
        ),
        .chk_unused(
          sc$documents_all,
          "document_id",
          sc$ref_document,
          "document_unused",
          "Document"
        )
      )
    )
  }
  .bind_findings(parts)
}

# The set of check ids the engine can emit -- consumed by the parity test.
#' @noRd
.engine_check_ids <- function() {
  c(
    "study_name_present",
    "dataset_label_present",
    "dataset_keys_resolve",
    "dataset_comment_resolves",
    "variable_label_present",
    "variable_length_positive",
    "variable_sigdigits_nonneg",
    "variable_order_positive",
    "variable_length_for_text",
    "variable_method_resolves",
    "variable_comment_resolves",
    "variable_derived_has_method",
    "value_whereclause_present",
    "value_variable_resolves",
    "value_method_resolves",
    "value_comment_resolves",
    "value_codelist_resolves",
    "codelist_comment_resolves",
    "codelist_terms_present",
    "method_id_unique",
    "method_description_present",
    "method_document_resolves",
    "comment_id_unique",
    "comment_description_present",
    "comment_document_resolves",
    "document_id_unique",
    "method_unused",
    "comment_unused",
    "document_unused",
    "ct_value_in_codelist",
    "ct_term_unused",
    "variable_present_in_data"
  )
}

#' Validate a specification for submission-readiness
#'
#' Run vport's bundled, self-contained checks over a `vport_spec`,
#' **scoped to the dataset(s) you are working on**, and return a
#' `vport_check` that prints a sectioned report. Every finding is keyed to
#' an open rule in the shipped catalog (see `spec_rules.json`); the result
#' object keeps the findings as a plain data frame in `@findings` for
#' programmatic use.
#'
#' @details
#' **Dataset-scoped.** A spec workbook carries many datasets. Pass
#' `dataset` to validate only the one(s) you are working on -- the
#' methods, comments, and codelists those datasets reference are checked
#' for completeness, but unrelated datasets are not. `dataset = NULL`
#' validates the whole spec.
#'
#' **Collect, do not stop.** Every finding is collected and returned;
#' `validate_spec()` does not abort on an error-severity finding unless
#' `strict = TRUE`.
#'
#' @param spec *The specification to validate.* `<vport_spec>: required`.
#' @param data *Optional input data for controlled-terminology checks.*
#'   `<data.frame> | named list | NULL`. When supplied, data values are
#'   cross-checked against the spec codelists. A single data frame requires
#'   a length-1 `dataset`. (Wired in a later step.)
#' @param dataset *Restrict to one or more datasets.* `<character> | NULL`.
#'   `NULL` (default) validates every dataset.
#'
#'   **Restriction:** each name must be a dataset in the spec.
#' @param strict *Abort on an error-severity finding.* `<logical(1)>:
#'   default FALSE`. When `TRUE`, all findings are still collected, then
#'   the call aborts with `vport_error_validation` if any error exists.
#'
#' @return *A `vport_check` object.* Its `@findings` data frame has columns
#'   `check`, `dimension`, `severity`, `dataset`, `variable`, `message`.
#'   Print it for the sectioned report.
#'
#' @examples
#' # ---- Example 1: validate one dataset ----
#' #
#' # Build a spec from the bundled tables and validate just ADSL; the
#' # result prints a sectioned report and keeps the findings table.
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' chk <- validate_spec(spec, dataset = "ADSL")
#' chk@findings
#'
#' # ---- Example 2: gate on errors with strict ----
#' #
#' # Point a key at a missing variable, then validate strictly and catch
#' # the resulting error.
#' bad_ds <- cdisc_datasets
#' bad_ds$keys[bad_ds$dataset == "DM"] <- "NOTAVAR"
#' bad <- vport_spec(bad_ds, cdisc_variables, codelists = cdisc_codelists)
#' tryCatch(
#'   validate_spec(bad, dataset = "DM", strict = TRUE),
#'   vport_error_validation = function(e) conditionMessage(e)[1]
#' )
#'
#' @seealso [vport_spec()] to build a spec; [spec_methods()] /
#'   [spec_comments()] for the metadata checked.
#' @export
validate_spec <- function(spec, data = NULL, dataset = NULL, strict = FALSE) {
  call <- rlang::caller_env()
  .check_spec_arg(spec, call)
  if (!is.null(dataset)) {
    dataset <- unique(trimws(as.character(dataset)))
    for (ds in dataset) {
      .check_dataset_arg(spec, ds, call)
    }
  }

  sc <- .scope_spec(spec, dataset)
  findings <- .run_checks(sc)
  if (!is.null(data)) {
    findings <- .bind_findings(list(findings, .chk_ct(sc, data, call)))
  }
  rownames(findings) <- NULL

  chk <- vport_check_class(
    findings = findings,
    scope = sc$scope,
    study = .study_label(spec),
    summary = list(
      n_datasets = length(sc$scope),
      n_variables = nrow(sc$variables),
      n_methods_ref = length(sc$ref_method),
      n_comments_ref = length(sc$ref_comment)
    )
  )

  if (strict) {
    nerr <- sum(findings$severity == "error")
    if (nerr) {
      msgs <- utils::head(findings$message[findings$severity == "error"], 3L)
      # Finding messages embed spec values; escape so a "{" renders literally
      # instead of crashing cli interpolation.
      cli::cli_abort(
        c(
          "Spec is not submission-ready, {nerr} error-severity finding{?s}.",
          stats::setNames(.cli_escape(msgs), rep("x", length(msgs))),
          "i" = "Inspect every finding in the returned vport_check."
        ),
        class = "vport_error_validation",
        call = call
      )
    }
  }

  chk
}
