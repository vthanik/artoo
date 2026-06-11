# spec_accessors.R -- pure, total accessors onto a artoo_spec.

# Abort unless `spec` is a artoo_spec.
#' @noRd
.check_spec_arg <- function(spec, call = rlang::caller_env()) {
  if (!is_artoo_spec(spec)) {
    .artoo_abort(
      c(
        "{.arg spec} must be a {.cls artoo_spec}.",
        "x" = "You supplied {.obj_type_friendly {spec}}.",
        "i" = "Build one with {.fn artoo_spec}."
      ),
      kind = "input",
      call = call
    )
  }
  invisible(spec)
}

# Abort unless `dataset` names a dataset in the spec.
#' @noRd
.check_dataset_arg <- function(spec, dataset, call = rlang::caller_env()) {
  known <- spec_datasets(spec)
  if (length(dataset) != 1L || is.na(dataset) || !(dataset %in% known)) {
    .artoo_abort(
      c(
        "{.arg dataset} must be one of the spec's datasets.",
        "x" = "{.val {dataset}} is not in the spec.",
        "i" = "Available: {.val {known}}."
      ),
      kind = "input",
      call = call
    )
  }
  invisible(dataset)
}

#' Dataset names in a spec
#'
#' List the datasets a specification defines. The result is the set of
#' names you pass as the `dataset` argument to the other accessors and to
#' `apply_spec()`.
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#'
#' @return *A character vector of dataset names*, de-duplicated and with
#'   `NA`s dropped. Empty when the spec has no datasets.
#'
#' @examples
#' # ---- Example 1: the datasets the pilot ADaM spec defines ----
#' #
#' # Build the spec from the bundled CDISC-pilot tables and list its
#' # datasets -- the names you pass to the other accessors.
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists
#' )
#' spec_datasets(spec)
#'
#' @seealso [spec_variables()] for one dataset's variables; [spec_keys()]
#'   for its sort keys.
#' @export
spec_datasets <- function(spec) {
  .check_spec_arg(spec)
  ds <- spec@datasets
  if (!("dataset" %in% names(ds)) || !nrow(ds)) {
    return(character(0))
  }
  unique(ds$dataset[!is.na(ds$dataset)])
}

#' Variables in a spec
#'
#' Return the variable-metadata table for one dataset, or for the whole
#' spec. Each row carries the variable's CDISC `data_type`, label, length,
#' display format, key sequence, and codelist reference.
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#' @param dataset *Restrict to one dataset.* `<character(1)> | NULL`. When
#'   `NULL` (default) every dataset's variables are returned; otherwise only
#'   the named dataset's rows.
#'
#'   **Restriction:** a non-`NULL` `dataset` must name a dataset in the spec
#'   (see [spec_datasets()]); an unknown name aborts with
#'   `artoo_error_input`.
#'
#' @return *A data frame of variable metadata*, one row per variable, with
#'   22 columns (absent ones are filled with typed `NA` at construction):
#'
#'   - `dataset`, `variable` -- the identifying pair (unique within a spec).
#'   - `itemoid` -- the Define-XML / Dataset-JSON item OID, when recorded.
#'   - `label` -- the variable label (<= 40 bytes for XPORT v5).
#'   - `data_type` -- canonical CDISC dataType (`string`, `integer`,
#'     `decimal`, `float`, `double`, `boolean`, `date`, `datetime`, `time`,
#'     `URI`).
#'   - `target_data_type` -- `integer`/`decimal` when a temporal variable
#'     stores as a SAS-epoch numeric; `NA` means ISO 8601 text (`--DTC`).
#'   - `length` -- declared storage length (bytes for character).
#'   - `display_format`, `informat` -- SAS format / informat strings.
#'   - `key_sequence` -- 1-based position in the dataset sort key.
#'   - `order` -- column position in the dataset.
#'   - `codelist_id`, `method_id`, `comment_id` -- references into the
#'     codelists / methods / comments slots.
#'   - `mandatory` -- logical obligation flag (`NA` is treated as
#'     mandatory by [check_spec()]).
#'   - `significant_digits` -- for `decimal` variables.
#'   - `origin`, `source`, `predecessor`, `assigned_value`, `pages`,
#'     `role` -- Define-XML provenance fields, carried as-is.
#'
#'   Filter or arrange it with ordinary base / `dplyr` verbs.
#'
#' @examples
#' spec <- artoo_spec(cdisc_sdtm_datasets, cdisc_sdtm_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: one dataset's variables ----
#' #
#' # Pass a dataset name to get just that domain's variables, already
#' # canonicalised to CDISC dataTypes.
#' head(spec_variables(spec, "DM")[, c("variable", "label", "data_type")])
#'
#' # ---- Example 2: every variable across the spec ----
#' #
#' # Omit `dataset` to get the full table, e.g. to count variables per domain.
#' table(spec_variables(spec)$dataset)
#'
#' @seealso [spec_datasets()] for the dataset names; [spec_codelists()] for a
#'   variable's controlled terminology.
#' @export
spec_variables <- function(spec, dataset = NULL) {
  .check_spec_arg(spec)
  vars <- spec@variables
  if (is.null(dataset)) {
    return(vars)
  }
  .check_dataset_arg(spec, dataset)
  vars[!is.na(vars$dataset) & vars$dataset == dataset, , drop = FALSE]
}

#' Codelist terms
#'
#' Return the controlled-terminology terms and decodes a spec carries: one
#' codelist's terms when `codelist_id` names it, or the full `codelists` slot
#' when `codelist_id` is `NULL`. Use it to inspect the values a coded variable
#' is allowed to take before applying the spec. Mirrors the
#' [spec_variables()] filter pattern.
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#' @param codelist_id *The codelist to return.* `<character(1)> | NULL`. When
#'   `NULL` (default) the whole codelists table is returned.
#'
#'   **Restriction:** a non-`NULL` id must name a codelist present in the
#'   spec's `codelists` slot; an unknown id aborts with `artoo_error_input`.
#'
#' @return *A data frame of codelist terms*, one row per term: every term
#'   when `codelist_id` is `NULL`, else the named codelist's terms. Columns:
#'
#'   - `codelist_id` -- the codelist identifier variables reference.
#'   - `term` -- the submission value (what conformed data carries).
#'   - `decode` -- the human-readable decoded value.
#'   - `order` -- display order within the codelist.
#'   - `extended` -- `TRUE` marks an extensible codelist (sponsor terms
#'     allowed; non-members downgrade to notes in [check_spec()]).
#'   - `comment_id` -- reference into the comments slot.
#'
#' @examples
#' # ---- Example 1: the terms behind a coded variable ----
#' #
#' # SEX is coded against C66731; spec_codelists() returns the terms and their
#' # decodes that apply_spec() will enforce or decode.
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists
#' )
#' spec_codelists(spec, "C66731")
#'
#' # ---- Example 2: the whole codelists table ----
#' #
#' # Called with no id, it returns every term across every codelist.
#' head(spec_codelists(spec))
#'
#' @seealso [spec_variables()] for which variables reference a codelist.
#' @export
spec_codelists <- function(spec, codelist_id = NULL) {
  .check_spec_arg(spec)
  cl <- spec@codelists
  if (is.null(codelist_id)) {
    return(cl)
  }
  known <- if ("codelist_id" %in% names(cl)) {
    unique(cl$codelist_id)
  } else {
    character(0)
  }
  if (
    length(codelist_id) != 1L || is.na(codelist_id) || !(codelist_id %in% known)
  ) {
    .artoo_abort(
      c(
        "{.arg codelist_id} must be a codelist in the spec.",
        "x" = "{.val {codelist_id}} is not present.",
        "i" = "Available: {.val {known}}."
      ),
      kind = "input",
      call = rlang::caller_env()
    )
  }
  cl[!is.na(cl$codelist_id) & cl$codelist_id == codelist_id, , drop = FALSE]
}

#' Sort keys for a dataset
#'
#' Parse a dataset's sort keys into a character vector of variable names.
#' These keys drive the sort step of `apply_spec()` and the `keySequence`
#' written to each output format.
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#' @param dataset *The dataset whose keys to parse.* `<character(1)>:
#'   required`.
#'
#'   **Restriction:** must name a dataset in the spec.
#'
#' @return *A character vector of key variable names*, split from the
#'   dataset's `keys` cell (whitespace- or comma-separated). Empty when no
#'   keys are declared.
#'
#' @examples
#' # ---- Example 1: parse a dataset's sort keys ----
#' #
#' # Declare DM's keys, then read them back as the ordered vector apply_spec()
#' # sorts by. (STUDYID and USUBJID are real DM variables in the demo data.)
#' ds <- cdisc_sdtm_datasets
#' ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
#' spec <- artoo_spec(ds, cdisc_sdtm_variables, codelists = cdisc_codelists)
#' spec_keys(spec, "DM")
#'
#' @seealso [spec_datasets()] for the dataset names; [spec_variables()] for
#'   the variables a key must reference.
#' @export
spec_keys <- function(spec, dataset) {
  .check_spec_arg(spec)
  .check_dataset_arg(spec, dataset)
  ds <- spec@datasets
  raw <- ds$keys[!is.na(ds$dataset) & ds$dataset == dataset]
  raw <- raw[!is.na(raw) & nzchar(raw)]
  if (!length(raw)) {
    return(character(0))
  }
  .split_keys(raw[[1]])
}

# Split a dataset's keys string ("STUDYID USUBJID", commas tolerated) into
# the ordered key variable names. Shared by spec_keys() and the
# key_sequence derivation in artoo_spec().
#' @noRd
.split_keys <- function(raw) {
  keys <- unlist(strsplit(raw, "[[:space:],]+"))
  keys[nzchar(keys)]
}

#' The CDISC standard a spec implements
#'
#' Return the one CDISC standard the specification carries (e.g.
#' `"ADaMIG 1.1"`, `"SDTMIG 3.2"`). A `artoo_spec` is single-standard by
#' construction -- [artoo_spec()] aborts when its sources mix standards --
#' so this is always a scalar; `NA` when no source named one.
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#'
#' @return *A `<character(1)>`*: the standard, or `NA` when unspecified.
#'
#' @examples
#' # ---- Example 1: the standard set at construction ----
#' #
#' # Pass the standard explicitly (or let it resolve from a P21 workbook's
#' # Standard column / a Define-XML study block) and read it back.
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists,
#'   standard = "ADaMIG 1.1"
#' )
#' spec_standard(spec)
#'
#' # ---- Example 2: unspecified resolves to NA ----
#' #
#' # A spec built without any standard source carries NA.
#' bare <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists
#' )
#' spec_standard(bare)
#'
#' @seealso [spec_study()] for the rest of the study-level metadata;
#'   [artoo_spec()] for how the standard is resolved.
#' @export
spec_standard <- function(spec) {
  .check_spec_arg(spec)
  spec@standard
}

#' Study-level metadata
#'
#' Return the study-level metadata row, or a single field from it. Holds the
#' study identifier and any other study-scoped fields a source provides
#' (the CDISC standard lives on its own property -- see [spec_standard()]).
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#' @param field *Return one field instead of the row.* `<character(1)> |
#'   NULL`. When `NULL` (default) the whole study data frame is returned.
#'
#'   **Restriction:** a non-`NULL` `field` must be a column of the study
#'   table; an unknown field aborts with `artoo_error_input`.
#'
#' @return *The study data frame*, or the value of one `field`.
#'
#' @examples
#' # ---- Example 1: the whole study row, then one field ----
#' #
#' # spec_study() with no field returns the study-level table; pass a field
#' # name to pull a single value such as the study identifier.
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists,
#'   study = data.frame(studyid = "CDISCPILOT01")
#' )
#' spec_study(spec)
#' spec_study(spec, "studyid")
#'
#' @seealso [spec_datasets()] for the datasets the study scopes;
#'   [spec_standard()] for the spec's CDISC standard.
#' @export
spec_study <- function(spec, field = NULL) {
  .check_spec_arg(spec)
  study <- spec@study
  if (is.null(field)) {
    return(study)
  }
  if (length(field) != 1L || !(field %in% names(study))) {
    .artoo_abort(
      c(
        "{.arg field} must be a study-level field.",
        "x" = "{.val {field}} is not present.",
        "i" = "Available: {.val {names(study)}}."
      ),
      kind = "input",
      call = rlang::caller_env()
    )
  }
  study[[field]]
}

#' Derivation methods in a spec
#'
#' Return the method definitions a specification carries. Variables and
#' value-level rows reference these by `method_id`; [validate_spec()] checks
#' that every reference resolves and that each referenced method is
#' complete (has a description).
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#'
#' @return *A data frame of method metadata* (`method_id`, `name`, `type`,
#'   `description`, ...), one row per method. Empty when the spec defines no
#'   methods.
#'
#' @examples
#' # ---- Example 1: the methods a spec defines ----
#' #
#' # Build a spec with one derivation method and read it back.
#' spec <- artoo_spec(
#'   data.frame(dataset = "ADSL"),
#'   data.frame(dataset = "ADSL", variable = "AGEGR1", data_type = "string"),
#'   methods = data.frame(
#'     method_id = "MT.AGEGR1",
#'     description = "Age group from AGE.",
#'     stringsAsFactors = FALSE
#'   )
#' )
#' spec_methods(spec)
#'
#' @seealso [spec_comments()], [spec_documents()], [validate_spec()].
#' @export
spec_methods <- function(spec) {
  .check_spec_arg(spec)
  spec@methods
}

#' Comment definitions in a spec
#'
#' Return the comment definitions a specification carries. Datasets,
#' variables, value-level rows, and codelists reference these by
#' `comment_id`; [validate_spec()] checks the references resolve and each
#' referenced comment has a body.
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#'
#' @return *A data frame of comment metadata* (`comment_id`, `description`,
#'   ...), one row per comment. Empty when the spec defines no comments.
#'
#' @examples
#' # ---- Example 1: the comments a spec defines ----
#' #
#' # Build a spec with one comment and read it back.
#' spec <- artoo_spec(
#'   data.frame(dataset = "ADSL"),
#'   data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
#'   comments = data.frame(
#'     comment_id = "C.AGE",
#'     description = "Age in years at informed consent.",
#'     stringsAsFactors = FALSE
#'   )
#' )
#' spec_comments(spec)
#'
#' @seealso [spec_methods()], [spec_documents()], [validate_spec()].
#' @export
spec_comments <- function(spec) {
  .check_spec_arg(spec)
  spec@comments
}

#' Document references in a spec
#'
#' Return the document references a specification carries. Methods and
#' comments point to these by `document_id`.
#'
#' @param spec *The specification to read.* `<artoo_spec>: required`.
#'
#' @return *A data frame of document metadata* (`document_id`, `title`,
#'   `href`), one row per document. Empty when the spec defines none.
#'
#' @examples
#' # ---- Example 1: the documents a spec defines ----
#' #
#' # Build a spec with one document reference and read it back.
#' spec <- artoo_spec(
#'   data.frame(dataset = "ADSL"),
#'   data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
#'   documents = data.frame(
#'     document_id = "SAP",
#'     title = "Statistical Analysis Plan",
#'     stringsAsFactors = FALSE
#'   )
#' )
#' spec_documents(spec)
#'
#' @seealso [spec_methods()], [spec_comments()], [validate_spec()].
#' @export
spec_documents <- function(spec) {
  .check_spec_arg(spec)
  spec@documents
}
