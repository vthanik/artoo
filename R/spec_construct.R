# spec_construct.R -- the friendly artoo_spec() constructor.

# Coerce one slot to its schema: drop to a plain data frame, error on a
# missing required column, coerce known columns to their storage mode, fill
# missing optional columns with a typed NA, and leave unknown columns as-is.
#' @noRd
.coerce_slot <- function(df, schema, req, slot, call) {
  if (is.null(df)) {
    cols <- lapply(schema, function(m) .na_mode(m, 0L))
    return(as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE))
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
  missing <- setdiff(req, names(df))
  if (length(missing)) {
    cli::cli_abort(
      c(
        "{.arg {slot}} is missing a required column{cli::qty(missing)}{?s}: {.val {missing}}.",
        "i" = "Required: {.val {req}}."
      ),
      class = "artoo_error_spec",
      call = call
    )
  }
  n <- nrow(df)
  for (nm in intersect(names(schema), names(df))) {
    df[[nm]] <- .coerce_mode(df[[nm]], schema[[nm]])
  }
  for (nm in setdiff(names(schema), names(df))) {
    df[[nm]] <- .na_mode(schema[[nm]], n)
  }
  df
}

#' Construct a CDISC specification
#'
#' Build and validate a `artoo_spec` from dataset, variable, and codelist
#' tables. Each table is coerced to a plain data frame, missing optional
#' columns are filled with typed `NA`s, every variable type is canonicalised
#' to the CDISC `dataType` vocabulary, and cross-slot integrity (dataset and
#' codelist references) is checked before the object is returned. The spec
#' is the lingua franca the rest of artoo reads, applies, and serialises.
#'
#' @details
#' **Coerce, then validate.** Each table is first coerced to a plain data
#' frame (a `tibble` is accepted and demoted); known columns are cast to
#' their storage mode and absent optional columns are added as typed `NA`,
#' so every downstream reader can trust the schema. Validation runs only
#' after coercion, on the completed slots.
#'
#' **Type canonicalisation.** `variables$data_type` is mapped through the
#' closed CDISC `dataType` vocabulary (`string`, `integer`, `decimal`,
#' `float`, `double`, `boolean`, `date`, `datetime`, `time`, `URI`). Common
#' SAS / P21 spellings resolve automatically (`"text"`, `"Char"`,
#' `"integer (8)"`, ...); an unrecognised token aborts with
#' `artoo_error_type`.
#'
#' **Cross-slot integrity.** Construction fails (`artoo_error_spec`) if a
#' variable names a dataset absent from `datasets`, or references a
#' `codelist_id` absent from `codelists`.
#'
#' @param datasets *Dataset-level metadata table.*
#'   `<data.frame>: required`. One row per dataset; must carry a `dataset`
#'   column. Optional columns `label`, `class`, `structure`, `keys` are
#'   filled with `NA` when absent.
#' @param variables *Variable-level metadata table.*
#'   `<data.frame>: required`. One row per variable; must carry `dataset`,
#'   `variable`, and `data_type`. The `data_type` column is canonicalised to
#'   a CDISC `dataType` (e.g. `"text"` becomes `"string"`).
#'
#'   **Requirement:** every `dataset` value must appear in `datasets`.
#' @param codelists *Controlled-terminology terms.*
#'   `<data.frame> | NULL`. Must carry `codelist_id` and `term` when
#'   supplied.
#'
#'   **Interaction:** every `codelist_id` referenced by `variables` must
#'   resolve here.
#' @param study *Study-level metadata.* `<data.frame> | NULL`. A single row
#'   of named study fields (e.g. `studyid`, `standard`).
#' @param values *Value-level (VLM) metadata.* `<data.frame> | NULL`.
#' @param methods *Derivation methods.* `<data.frame> | NULL`. The
#'   Define-XML method definitions variables reference by `method_id`; must
#'   carry `method_id` when supplied. Completeness (e.g. a referenced
#'   method has a description) is checked by [validate_spec()], not here.
#' @param comments *Comment definitions.* `<data.frame> | NULL`. Referenced
#'   by `comment_id`; must carry `comment_id` when supplied.
#' @param documents *Document references.* `<data.frame> | NULL`. Referenced
#'   by `document_id`; must carry `document_id` when supplied.
#'
#' @return *A validated `artoo_spec` object.* Inspect it with
#'   [spec_datasets()] / [spec_variables()], or check it with
#'   [validate_spec()].
#'
#' @examples
#' # ---- Example 1: build a spec from the bundled CDISC-pilot tables ----
#' #
#' # `cdisc_datasets` and `cdisc_variables` hold the CDISC pilot ADaM
#' # metadata in the shape artoo_spec() expects; the constructor
#' # canonicalises every type and checks cross-slot integrity.
#' spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' spec_datasets(spec)
#'
#' # ---- Example 2: a focused spec for a single dataset ----
#' #
#' # Slice the bundled tables to one dataset (DM) to build a smaller spec.
#' dm_ds <- cdisc_datasets[cdisc_datasets$dataset == "DM", ]
#' dm_var <- cdisc_variables[cdisc_variables$dataset == "DM", ]
#' dm_spec <- artoo_spec(dm_ds, dm_var, codelists = cdisc_codelists)
#' head(spec_variables(dm_spec, "DM")[, c("variable", "label", "data_type")])
#'
#' @seealso
#' **Inspect:** [spec_datasets()], [spec_variables()], [spec_codelists()],
#' [spec_keys()], [spec_study()].
#'
#' **Check:** [validate_spec()]. **Predicate:** [is_artoo_spec()].
#' @export
artoo_spec <- function(
  datasets = NULL,
  variables = NULL,
  codelists = NULL,
  study = NULL,
  values = NULL,
  methods = NULL,
  comments = NULL,
  documents = NULL
) {
  call <- rlang::caller_env()
  if (is.null(datasets) || is.null(variables)) {
    cli::cli_abort(
      c(
        "Both {.arg datasets} and {.arg variables} are required.",
        "i" = "Pass at least a {.code dataset} table and a variable table."
      ),
      class = "artoo_error_input",
      call = call
    )
  }
  datasets <- .coerce_slot(
    datasets,
    .spec_cols_datasets,
    .spec_req_datasets,
    "datasets",
    call
  )
  variables <- .coerce_slot(
    variables,
    .spec_cols_variables,
    .spec_req_variables,
    "variables",
    call
  )
  codelists <- .coerce_slot(
    codelists,
    .spec_cols_codelists,
    .spec_req_codelists,
    "codelists",
    call
  )
  methods <- .coerce_slot(
    methods,
    .spec_cols_methods,
    .spec_req_methods,
    "methods",
    call
  )
  comments <- .coerce_slot(
    comments,
    .spec_cols_comments,
    .spec_req_comments,
    "comments",
    call
  )
  documents <- .coerce_slot(
    documents,
    .spec_cols_documents,
    .spec_req_documents,
    "documents",
    call
  )
  study <- if (is.null(study)) {
    data.frame()
  } else {
    as.data.frame(study, stringsAsFactors = FALSE, check.names = FALSE)
  }

  # Demote a tibble (or other data-frame subclass) value-level table to a
  # plain data frame, so every slot is a uniform data.frame and a spec
  # round-trips identically through write_spec()/read_spec().
  if (!is.null(values)) {
    values <- as.data.frame(
      values,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  }

  # Canonicalise each variable's data_type to a CDISC dataType.
  if (nrow(variables)) {
    variables$data_type <- vapply(
      seq_len(nrow(variables)),
      function(i) {
        .parse_type(
          variables$data_type[[i]],
          variable = variables$variable[[i]],
          call = call
        )
      },
      character(1)
    )
  }

  .spec_check_refs(datasets, variables, codelists, call)

  artoo_spec_class(
    study = study,
    datasets = datasets,
    variables = variables,
    codelists = codelists,
    methods = methods,
    comments = comments,
    documents = documents,
    values = values
  )
}

# Friendly cross-slot reference checks (the S7 validator repeats these as a
# last line of defence). Each message carries a single varying quantity so
# cli pluralisation is unambiguous.
#' @noRd
.spec_check_refs <- function(datasets, variables, codelists, call) {
  if (nrow(variables)) {
    # Duplicate (dataset, variable) definitions make every downstream step
    # ambiguous (which label? which type?). Fail at construction, with the
    # exact rows, instead of deep inside apply_spec() after the user has
    # already derived everything. read_spec(on_duplicate=) offers the
    # keep-first policy for workbooks that ship with duplicates.
    key <- paste(variables$dataset, variables$variable, sep = ".")
    keyed <- !is.na(variables$dataset) & !is.na(variables$variable)
    dup_keys <- unique(key[keyed][duplicated(key[keyed])])
    if (length(dup_keys)) {
      lines <- vapply(
        utils::head(dup_keys, 3L),
        function(k) {
          rows <- which(keyed & key == k)
          sprintf(
            "Rows %s of {.arg variables} all define %s.",
            paste(rows, collapse = " and "),
            k
          )
        },
        character(1)
      )
      cli::cli_abort(
        c(
          "{.arg variables} defines {length(dup_keys)} variable{?s} more than once.",
          stats::setNames(lines, rep("x", length(lines))),
          "i" = "Remove the duplicate rows, or read the file with {.code read_spec(path, on_duplicate = \"first\")}."
        ),
        class = "artoo_error_spec",
        call = call
      )
    }
    orphan <- setdiff(unique(variables$dataset), datasets$dataset)
    orphan <- orphan[!is.na(orphan)]
    if (length(orphan)) {
      cli::cli_abort(
        c(
          "Some variables reference a dataset not in {.arg datasets}.",
          "x" = "Unknown dataset{?s}: {.val {orphan}}.",
          "i" = "Add the dataset to {.arg datasets}, or fix {.arg variables}."
        ),
        class = "artoo_error_spec",
        call = call
      )
    }
    used <- unique(variables$codelist_id[
      !is.na(variables$codelist_id) & nzchar(variables$codelist_id)
    ])
    known <- if ("codelist_id" %in% names(codelists)) {
      unique(codelists$codelist_id)
    } else {
      character(0)
    }
    unresolved <- setdiff(used, known)
    if (length(unresolved)) {
      cli::cli_abort(
        c(
          "Some variables reference a codelist not in {.arg codelists}.",
          "x" = "Unresolved codelist_id{?s}: {.val {unresolved}}.",
          "i" = "Add the codelist's terms to {.arg codelists}."
        ),
        class = "artoo_error_spec",
        call = call
      )
    }
  }
}

#' Test for a artoo_spec object
#'
#' Report whether an object is a `artoo_spec` -- the validated CDISC
#' specification that drives the artoo workflow (spec -> apply_spec ->
#' read_/write_). [artoo_spec()] builds one; this is the type guard before you
#' pass it to [apply_spec()] or reach into it with the spec accessors.
#'
#' @param x *Object to test.* `<any>`.
#'
#' @return *A `<logical(1)>`*: `TRUE` when `x` is a `artoo_spec`, else `FALSE`.
#'
#' @examples
#' # ---- Example 1: guard a built specification ----
#' #
#' # artoo_spec() assembles and validates a spec; is_artoo_spec() confirms the
#' # type before you drive apply_spec() with it.
#' spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' is_artoo_spec(spec)
#'
#' # ---- Example 2: an ordinary object is not a spec ----
#' #
#' # Any non-artoo_spec value -- a bare data frame, say -- returns FALSE.
#' is_artoo_spec(cdisc_dm)
#'
#' @seealso [artoo_spec()] to build one; [is_artoo_meta()] for the metadata
#'   guard.
#' @export
is_artoo_spec <- function(x) {
  S7::S7_inherits(x, artoo_spec_class)
}
