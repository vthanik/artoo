# spec_read.R — read_spec(): native JSON + Pinnacle 21 Excel -> artoo_spec.
#
# The P21 Excel parser is ported from the herald-v0 archive
# (R/spec-read.R) and hardened: artoo-targeted column maps, alias-set
# sheet matching, merged-cell forward fill on every foreign-key column,
# and fail-loud on an unresolvable key. Every path funnels through
# artoo_spec(), which is the single validation surface.

# ---- P21 -> artoo column maps (spreadsheet header -> artoo slot column) ---
# Headers not listed ride along as extra character columns (no silent
# drop); artoo columns absent from P21 are filled with typed NA by the
# artoo_spec() constructor.

#' @noRd
.p21_ds_map <- c(
  "Dataset" = "dataset",
  "Label" = "label",
  "Class" = "class",
  "SubClass" = "subclass",
  "Structure" = "structure",
  "Key Variables" = "keys",
  "Standard" = "standard",
  "Comment" = "comment_id",
  # ---- Define-XML ItemGroupDef attributes ----
  # Pinnacle 21 treats most of these as required for a regulatory submission
  # even though the XSD marks them optional, so a workbook that carries them
  # must not have them dropped on the floor.
  "Domain" = "domain",
  "SAS Dataset Name" = "sas_dataset_name",
  "Purpose" = "purpose",
  "Repeating" = "repeating",
  "Reference Data" = "reference_data",
  "Has No Data" = "has_no_data"
)

#' @noRd
.p21_var_map <- c(
  "Order" = "order",
  "Dataset" = "dataset",
  "Variable" = "variable",
  "Label" = "label",
  "Data Type" = "data_type",
  "Length" = "length",
  "Significant Digits" = "significant_digits",
  "Format" = "display_format",
  "Mandatory" = "mandatory",
  "Assigned Value" = "assigned_value",
  "Codelist" = "codelist_id",
  "Origin" = "origin",
  "Source" = "source",
  # Which document the pages are pages OF. Without a column for it, a
  # workbook round trip kept the page numbers and lost what they point at,
  # so every collected variable came back with an unattachable reference.
  "Origin Document" = "origin_document_id",
  "Pages" = "pages",
  "Method" = "method_id",
  "Predecessor" = "predecessor",
  "Role" = "role",
  "Comment" = "comment_id",
  # ---- Define-XML ItemDef / ItemRef additions ----
  # NOTE: "Description" is deliberately NOT mapped here. Newer Pinnacle 21
  # workbooks carry both a "Label" and a "Description" column, and mapping
  # both to `label` yields two columns of the same name -- the second is then
  # silently dropped on write, with which one survives decided by an
  # undocumented first-name-wins rule. "Label" is the Define-XML
  # Description/TranslatedText, so it is the one artoo reads.
  "SAS Field Name" = "sas_field_name",
  "Has No Data" = "has_no_data"
)

#' @noRd
# The Codelists "Comment" column is a Comment-ID reference, exactly like the
# Variables and Datasets ones: the workbook format documents it as an id
# that must match a row on the Comments sheet, and it becomes
# `CodeList/@def:CommentOID` in Define-XML 2.1.
#
# artoo read it as inline free text and left it unmapped, on the theory that
# mapping it would raise false unresolved-comment findings. It cannot: the
# id resolves against the same Comments sheet every other reference does.
# What the theory actually produced was a codelist with no comment and a
# CommentDef with nothing pointing at it -- an orphan artoo emitted itself.
.p21_codelist_map <- c(
  "ID" = "codelist_id",
  "Order" = "order",
  "Term" = "term",
  "Decoded Value" = "decode",
  # ---- list-level attributes, repeated on every term row ----
  # CodeList/@Name and @DataType are schema-REQUIRED, so a workbook that
  # supplies them and an artoo_spec that drops them cannot produce a valid
  # define.xml. The NCI codes are a Pinnacle 21 conformance check.
  "Name" = "name",
  "Data Type" = "data_type",
  "NCI Codelist Code" = "nci_code",
  "SAS Format Name" = "sas_format_name",
  "Comment" = "comment_id",
  # ---- term-level ----
  "NCI Term Code" = "term_nci_code",
  "Rank" = "rank"
)

#' @noRd
.p21_value_map <- c(
  "Order" = "order",
  "Dataset" = "dataset",
  "Variable" = "variable",
  "Where Clause" = "where_clause",
  "Label" = "label",
  "Data Type" = "data_type",
  "Length" = "length",
  "Significant Digits" = "significant_digits",
  "Format" = "display_format",
  "Mandatory" = "mandatory",
  "Codelist" = "codelist_id",
  "Origin" = "origin",
  "Method" = "method_id",
  "Comment" = "comment_id",
  # The origin-support columns the current workbook generation carries on
  # ValueLevel exactly as it does on Variables. artoo mapped them for
  # Variables and not here, so an `Origin = Predecessor` value-level row
  # read back with no predecessor and wrote an origin describing nothing.
  "Assigned Value" = "assigned_value",
  "Source" = "source",
  "Pages" = "pages",
  "Predecessor" = "predecessor",
  # artoo's own column, matching the one it adds to Variables: a page number
  # says nothing about which document it is a page of, and mapping the pages
  # without it left every value-level page reference dangling.
  "Origin Document" = "origin_document_id"
)

#' @noRd
.p21_method_map <- c(
  "ID" = "method_id",
  "Name" = "name",
  "Type" = "type",
  "Description" = "description",
  "Expression Context" = "expression_context",
  "Expression Code" = "expression_code",
  "Document" = "document_id",
  "Pages" = "pages"
)

#' @noRd
.p21_comment_map <- c(
  "ID" = "comment_id",
  "Description" = "description",
  "Document" = "document_id",
  "Pages" = "pages"
)

#' @noRd
.p21_document_map <- c(
  "ID" = "document_id",
  "Title" = "title",
  "Href" = "href",
  # Which MetaDataVersion container owns the leaf. Without a column for it a
  # workbook author cannot designate the annotated CRF, and every collected
  # variable in the resulting define has no page link at all.
  "Role" = "role"
)

# Per-logical-sheet name alias sets (normalised-exact match against any
# member). Tighter than substring matching, so "Value Level" never
# collides with "Variable Level".
#' @noRd
.p21_sheet_aliases <- list(
  datasets = c("datasets", "dataset", "datasets metadata", "domains"),
  variables = c(
    "variables",
    "variable",
    "variable metadata",
    "variable level metadata"
  ),
  codelists = c("codelists", "codelist", "controlled terminology"),
  valuelevel = c("valuelevel", "value level", "value level metadata"),
  methods = c("methods", "method", "computational methods"),
  comments = c("comments", "comment"),
  documents = c("documents", "document", "leaf", "supplemental documents"),
  study = c("define", "study", "metadata"),
  # Newer workbook generations split these out. Their absence is not an
  # error: an older workbook simply carries the where clause as free text in
  # the ValueLevel sheet, and has no ARM at all.
  whereclauses = c("whereclauses", "where clauses", "where clause"),
  dictionaries = c("dictionaries", "dictionary", "external codelists"),
  standards = c("standards", "standard"),
  arm_displays = c("analysis displays", "analysisdisplays", "displays"),
  arm_results = c("analysis results", "analysisresults", "results"),
  arm_criteria = c("analysis criteria", "analysiscriteria", "criteria")
)

#' @noRd
.p21_where_map <- c(
  "ID" = "where_clause_id",
  "Dataset" = "dataset",
  "Variable" = "variable",
  "Comparator" = "comparator",
  "Value" = "value",
  "Comment" = "comment_id"
)

#' @noRd
.p21_dictionary_map <- c(
  "ID" = "dictionary_id",
  "Name" = "name",
  "Data Type" = "data_type",
  "Dictionary" = "dictionary",
  "Version" = "version",
  "Href" = "href",
  "Ref" = "ref"
)

#' @noRd
.p21_standard_map <- c(
  "ID" = "standard_id",
  "Name" = "name",
  "Type" = "type",
  "Version" = "version",
  "Status" = "status",
  "Publishing Set" = "publishing_set",
  "Comment" = "comment_id"
)

# NOTE: "Description" is deliberately NOT mapped, for the same reason as on
# the Variables sheet: mapping it and "Title" both onto `description` yields
# two columns of the same name, and which one survives is decided by an
# undocumented first-name-wins rule. "Title" is the display's heading, which
# is what arm:ResultDisplay carries.
#' @noRd
.p21_arm_display_map <- c(
  "ID" = "display_id",
  "Name" = "name",
  "Title" = "description",
  "Document" = "document_id",
  "Pages" = "pages"
)

# NOTE: these header names are what the analysis-results sheets are commonly
# spelled, not a transcription of a template artoo has been checked against.
# A header that is not here rides along as a foreign column -- kept on the
# spec and re-emitted to xlsx, but invisible to the Define-XML writer, which
# reads canonical names. Verify against a real workbook before relying on the
# analysis-results path.
# The Analysis Criteria sheet: one row per analysis dataset of a result.
#
# The older workbook generation puts an analysis result's datasets on their
# own sheet rather than packing them into one Selection Criteria cell, and
# its grain is exactly artoo's -- one row per (display, result, dataset)
# with that dataset's own variables and condition. artoo has had the sheet
# alias since the analysis-results work landed and never read the sheet, so
# a result authored this way arrived with no dataset at all and the define
# write refused it.
#' @noRd
.p21_arm_criteria_map <- c(
  "Display" = "display_id",
  "Result" = "result_id",
  "Dataset" = "dataset",
  "Variables" = "variables",
  "Where Clause" = "where_clause_id"
)

#' @noRd
.p21_arm_result_map <- c(
  "Display" = "display_id",
  "ID" = "result_id",
  "Description" = "description",
  "Reason" = "reason",
  "Purpose" = "purpose",
  "Dataset" = "dataset",
  "Variables" = "variables",
  "Parameter" = "parameter_id",
  "Where Clause" = "where_clause_id",
  # The current generation carries the analysis datasets, their conditions
  # and (through PARAMCD) the parameter in ONE cell. artoo's Dataset /
  # Parameter / Where Clause columns are its decomposition; a workbook
  # authored in the standard shape has only this one.
  "Selection Criteria" = "selection_criteria",
  "Join Comment" = "datasets_comment_id",
  "Documentation" = "documentation",
  "Documentation Refs" = "documentation_document_id",
  "Programming Context" = "programming_context",
  "Programming Code" = "programming_code",
  "Programming Document" = "programming_document_id"
)

#' Read a specification from JSON, Excel, or Define-XML
#'
#' Read a clinical-dataset specification into a validated `artoo_spec`,
#' dispatching on the file extension: artoo's native JSON (the inverse of
#' [write_spec()]), a Pinnacle 21 (P21) Excel workbook, or a native
#' Define-XML 2.0/2.1 document. The returned spec is the lingua franca the
#' rest of artoo applies and serialises.
#'
#' @details
#' **Three formats, one validator.** A `.json` file is read as artoo native
#' JSON; a `.xlsx` / `.xls` file is read as a P21 workbook; a `.xml` file is
#' read as Define-XML 2.x. Either way the result is built through
#' [artoo_spec()], so type canonicalisation and cross-slot integrity checks
#' are identical regardless of source.
#'
#' **Define-XML ingestion** (needs the `xml2` package). ItemGroupDefs become
#' datasets (keys derived from the ItemRef KeySequence), ItemRef + ItemDef
#' pairs become variables, CodeLists become codelists
#' (`def:ExtendedValue = "Yes"` marks an extended term), MethodDefs /
#' CommentDefs / leaves become the supporting slots, and ValueListDefs land
#' in the value-level slot with their where-clauses rendered as readable
#' text.
#'
#'   **Note:** an `ExternalCodeList` (MedDRA, ISO-3166) names a dictionary
#'   rather than an enumerable membership list, so it lands in
#'   `dictionaries` rather than `codelists`; a variable that references one
#'   keeps the reference, because a workbook has one column for both.
#'   Define-XML v1.0 (the 2005 model) is refused with guidance.
#'
#' **P21 ingestion.** Sheets are located by a tolerant alias match
#' (case-, space-, and spelling-variant insensitive). Datasets and
#' Variables are required; Codelists and ValueLevel are optional (the
#' latter becomes the spec's value-level slot). Every cell is read as
#' text, then the dataset and codelist foreign keys are forward-filled to
#' recover merged cells (which the Excel reader returns as `NA` on
#' continuation rows). A key that cannot be resolved aborts with
#' `artoo_error_spec` rather than being silently dropped.
#'
#' @param path *The specification file to read.* `<character(1)>:
#'   required`. A `.json` (native), `.xlsx` / `.xls` (P21), or `.xml`
#'   (Define-XML 2.0 or 2.1) file.
#'
#'   **Requirement:** reading a P21 workbook needs the `readxl` package, and
#'   reading a define.xml needs `xml2`.
#' @param datasets *Read only these datasets.* `<character> | NULL`. `NULL`
#'   (default) reads the whole spec. Otherwise the spec is scoped to the
#'   named datasets before validation, so one broken sheet elsewhere in a
#'   workbook cannot block the dataset you are working on. An unknown name
#'   aborts listing what the file defines.
#' @param on_duplicate *Policy for a variable defined more than once.*
#'   `<character(1)>`. A workbook row duplicated within one dataset makes
#'   the spec ambiguous; the finding is reported with its source location
#'   (sheet and row numbers for Excel). One of:
#'   * `"error"` (default) abort, naming each duplicate's rows.
#'   * `"first"` keep the first definition of each, dropping the rest with
#'     a message.
#'   * `"warn"` keep the first definition and warn
#'     (`artoo_warning_spec`).
#'
#' @return *A validated `artoo_spec`.* Inspect it with [spec_datasets()] /
#'   [spec_variables()], check it with [validate_spec()], or persist it
#'   with [write_spec()].
#'
#' @examples
#' # ---- Example 1: round-trip a spec through native JSON ----
#' #
#' # write_spec() and read_spec() are inverses on the JSON path: the spec
#' # that comes back is identical to the one written.
#' spec <- artoo_spec(cdisc_sdtm_datasets, cdisc_sdtm_variables, codelists = cdisc_codelists)
#' path <- tempfile(fileext = ".json")
#' write_spec(spec, path)
#' back <- read_spec(path)
#' identical(back, spec)
#'
#' # ---- Example 2: scope the read to one dataset ----
#' #
#' # `datasets =` reads just the domain you are working on — validation is
#' # scoped with it, so a problem elsewhere in the workbook cannot block
#' # this dataset.
#' dm_spec <- read_spec(path, datasets = "DM")
#' spec_datasets(dm_spec)
#' head(spec_variables(dm_spec, "DM")[, c("variable", "label", "data_type")])
#'
#' @seealso
#' **Inverse:** [write_spec()] serialises a spec to native JSON.
#'
#' **Build / inspect:** [artoo_spec()], [spec_datasets()],
#' [spec_variables()], [validate_spec()].
#' @export
read_spec <- function(
  path,
  datasets = NULL,
  on_duplicate = c("error", "first", "warn")
) {
  call <- rlang::caller_env()
  on_duplicate <- match.arg(on_duplicate)
  if (
    !is.null(datasets) &&
      (!is.character(datasets) || !length(datasets) || anyNA(datasets))
  ) {
    .artoo_abort(
      c(
        "{.arg datasets} must be a character vector of dataset names.",
        "x" = "You supplied {.obj_type_friendly {datasets}}."
      ),
      kind = "input",
      call = call
    )
  }
  .check_path(path, call = call)
  if (!file.exists(path)) {
    .artoo_abort(
      c(
        "Spec file {.path {path}} does not exist.",
        "i" = "Pass a path to a {.val .json}, {.val .xlsx} or {.val .xml} spec."
      ),
      kind = "input",
      call = call
    )
  }
  ext <- tolower(tools::file_ext(path))
  switch(
    ext,
    json = .read_spec_json(path, datasets, on_duplicate, call),
    xlsx = ,
    xls = .read_spec_xlsx(path, datasets, on_duplicate, call),
    xml = .read_spec_define(path, datasets, on_duplicate, call),
    .artoo_abort(
      c(
        "Unsupported spec file type {.val {ext}}.",
        "i" = "read_spec() reads {.val .json}, Pinnacle 21 {.val .xlsx}, and Define-XML 2.x {.val .xml}."
      ),
      kind = "input",
      call = call
    )
  )
}

# ---- shared read-time guards ----------------------------------------------

# Scope the raw spec tables to the requested datasets BEFORE validation, so
# a problem confined to one sheet's other domains never blocks the dataset
# being read. Unknown names abort listing what the file defines.
#' @noRd
.spec_scope_tables <- function(tables, datasets, call) {
  if (is.null(datasets)) {
    return(tables)
  }
  datasets <- unique(trimws(datasets))
  avail <- if (
    is.data.frame(tables$datasets) && "dataset" %in% names(tables$datasets)
  ) {
    unique(trimws(tables$datasets$dataset))
  } else {
    character(0)
  }
  unknown <- setdiff(datasets, avail)
  if (length(unknown)) {
    .artoo_abort(
      c(
        "Unknown dataset{?s} in {.arg datasets}: {.val {unknown}}.",
        "i" = "The spec defines: {.val {avail}}."
      ),
      kind = "input",
      call = call
    )
  }
  keep_rows <- function(df) {
    if (is.null(df) || !is.data.frame(df) || !("dataset" %in% names(df))) {
      return(df)
    }
    df[!is.na(df$dataset) & trimws(df$dataset) %in% datasets, , drop = FALSE]
  }
  tables$datasets <- keep_rows(tables$datasets)
  tables$variables <- keep_rows(tables$variables)
  tables$values <- keep_rows(tables$values)

  # A where clause is a GROUP of range checks, and one of them may name a
  # variable in another dataset -- a VS value conditioned on DM.COUNTRY. So
  # the whole clause goes when ANY of its checks names a dataset out of
  # scope: keeping the rest would change which rows it selects, which is
  # worse than losing it.
  wc <- tables$where_clauses
  if (is.data.frame(wc) && nrow(wc)) {
    out <- rep(FALSE, nrow(wc))
    if ("dataset" %in% names(wc)) {
      out <- out | (!is.na(wc$dataset) & !(trimws(wc$dataset) %in% datasets))
    }
    # A Define-XML read leaves `dataset` NA and puts the authority in
    # `itemoid`, so scoping on the dataset column alone left every clause
    # conditioning on an out-of-scope domain behind, dangling.
    kept <- if ("itemoid" %in% names(tables$variables)) {
      as.character(tables$variables$itemoid)
    } else {
      character(0)
    }
    if ("itemoid" %in% names(wc) && length(kept)) {
      out <- out | (!is.na(wc$itemoid) & !(wc$itemoid %in% kept))
    }
    doomed <- unique(as.character(wc$where_clause_id)[out])
    tables$where_clauses <- wc[
      !(as.character(wc$where_clause_id) %in% doomed),
      ,
      drop = FALSE
    ]
  }

  # Analysis results name their analysis dataset, and a display with no
  # results left is a display of nothing.
  ar <- tables$arm_results
  if (is.data.frame(ar) && nrow(ar) && "dataset" %in% names(ar)) {
    tables$arm_results <- keep_rows(ar)
    ad <- tables$arm_displays
    if (is.data.frame(ad) && nrow(ad)) {
      tables$arm_displays <- ad[
        as.character(ad$display_id) %in%
          as.character(tables$arm_results$display_id),
        ,
        drop = FALSE
      ]
    }
  }
  .spec_scope_referenced(tables)
}

# Drop the shared metadata nothing in scope still points at.
#
# Scoping removes the referrers, so what is left is not the author's orphan
# but one artoo just made: writing a spec scoped to two ADaM datasets
# produced a define.xml its own linter flagged thirty-two times, for
# codelists, methods and comments belonging to datasets the spec no longer
# contains. An orphan in an UNSCOPED spec is left exactly where it is --
# that one is the author's, and artoo does not edit a spec it was not asked
# to narrow.
#
# References are found by column SUFFIX, not by an enumerated list of column
# names. One comment is reachable through eight columns across seven slots
# (`comment_id`, and `datasets_comment_id` on an analysis result), and every
# hand-written list of them was missing one -- each omission turning an
# orphan this pass removed into a dangling reference, which is worse.
#' @noRd
.spec_scope_referenced <- function(tables) {
  # Columns holding a reference of this kind: the bare id, or any column
  # ending in it. `except` is the slot that DEFINES the id, whose own column
  # is the definition -- counting it made every orphan look referenced by
  # itself.
  refs <- function(pattern, except) {
    out <- unlist(
      lapply(names(tables), function(nm) {
        df <- tables[[nm]]
        if (identical(nm, except) || !is.data.frame(df) || !nrow(df)) {
          return(NULL)
        }
        cols <- grep(pattern, names(df), value = TRUE)
        unlist(lapply(cols, function(cl) as.character(df[[cl]])))
      }),
      use.names = FALSE
    )
    unique(out[!is.na(out)])
  }
  prune <- function(slot, id, keep) {
    df <- tables[[slot]]
    if (!is.data.frame(df) || !nrow(df) || !(id %in% names(df))) {
      return(df)
    }
    df[as.character(df[[id]]) %in% keep, , drop = FALSE]
  }
  # A codelist row is one TERM, so the whole list goes or none of it does.
  tables$codelists <- prune(
    "codelists",
    "codelist_id",
    refs("(^|_)codelist_id$", "codelists")
  )
  tables$methods <- prune(
    "methods",
    "method_id",
    refs("(^|_)method_id$", "methods")
  )
  # A method's formal expressions go with the method they belong to.
  tables$method_expressions <- prune(
    "method_expressions",
    "method_id",
    as.character(tables$methods$method_id)
  )
  # Comments after codelists and methods: a comment may hang off one of
  # those, so its referrers are counted once they are gone.
  tables$comments <- prune(
    "comments",
    "comment_id",
    refs("(^|_)comment_id$", "comments")
  )
  # A document is pruned only when nothing points at it AND it sits in no
  # container: the annotated CRF and the supplemental documents are
  # referenced by their container rather than by an id, so an id-only test
  # would delete the two leaves every submission has. `archive_location_id`
  # is a leaf reference under another name.
  docs <- tables$documents
  if (is.data.frame(docs) && nrow(docs) && "document_id" %in% names(docs)) {
    held <- c(
      refs("(^|_)document_id$", "documents"),
      refs("(^|_)archive_location_id$", "documents")
    )
    contained <- if ("role" %in% names(docs)) {
      !is.na(docs$role) & docs$role != "other"
    } else {
      rep(FALSE, nrow(docs))
    }
    tables$documents <- docs[
      contained | as.character(docs$document_id) %in% held,
      ,
      drop = FALSE
    ]
  }
  tables
}

# Resolve duplicate (dataset, variable) definitions at read time, reporting
# each duplicate's SOURCE location ("Variables sheet rows 276 and 280" for
# Excel, table rows otherwise) — the actionable form of the finding the
# constructor would otherwise raise with bare table indices. `rows` aligns
# original source row numbers to `variables`; NULL falls back to indices.
#' @noRd
.resolve_duplicate_variables <- function(
  variables,
  on_duplicate,
  where,
  rows = NULL,
  call = rlang::caller_env()
) {
  if (
    is.null(variables) ||
      !nrow(variables) ||
      !all(c("dataset", "variable") %in% names(variables))
  ) {
    return(variables)
  }
  if (is.null(rows)) {
    rows <- seq_len(nrow(variables))
  }
  key <- paste(variables$dataset, variables$variable, sep = ".")
  keyed <- !is.na(variables$dataset) & !is.na(variables$variable)
  dup_keys <- unique(key[keyed][duplicated(key[keyed])])
  if (!length(dup_keys)) {
    return(variables)
  }
  lines <- vapply(
    utils::head(dup_keys, 5L),
    function(k) {
      at <- rows[keyed & key == k]
      sprintf(
        "%s rows %s all define %s.",
        where,
        paste(at, collapse = " and "),
        k
      )
    },
    character(1)
  )
  if (on_duplicate == "error") {
    .artoo_abort(
      c(
        "The spec defines {length(dup_keys)} variable{?s} more than once.",
        stats::setNames(lines, rep("x", length(lines))),
        "i" = "Fix the source, or keep the first definition of each with {.code on_duplicate = \"first\"}."
      ),
      kind = "spec",
      call = call
    )
  }
  if (on_duplicate == "warn") {
    .artoo_warn(
      c(
        "Keeping the first definition of {length(dup_keys)} duplicated variable{?s}.",
        stats::setNames(lines, rep("x", length(lines)))
      ),
      kind = "spec",
      call = call
    )
  } else {
    .artoo_inform(
      "Kept the first definition of {length(dup_keys)} duplicated variable{?s}.",
      kind = "spec"
    )
  }
  drop <- keyed & duplicated(key) & key %in% dup_keys
  variables[!drop, , drop = FALSE]
}

# ---- Native JSON --------------------------------------------------------

#' @noRd
.read_spec_json <- function(
  path,
  datasets = NULL,
  on_duplicate = "error",
  call = rlang::caller_env()
) {
  raw <- jsonlite::fromJSON(path, simplifyDataFrame = TRUE)
  .check_spec_json_version(raw[["artoo_spec_version"]], call)

  # An empty array [] simplifies to an empty list; a JSON null to NULL.
  # Both mean "no rows" -> NULL, which artoo_spec() rebuilds as the typed
  # empty slot.
  pick <- function(nm) {
    x <- raw[[nm]]
    if (is.null(x)) {
      return(NULL)
    }
    if (is.data.frame(x)) {
      return(if (nrow(x)) x else NULL)
    }
    NULL
  }

  tables <- .spec_scope_tables(
    list(
      datasets = pick("datasets"),
      variables = pick("variables"),
      values = pick("values")
    ),
    datasets,
    call
  )
  variables <- .resolve_duplicate_variables(
    tables$variables,
    on_duplicate,
    where = "The variables table",
    call = call
  )

  # The scalar standard rides its own top-level key (a JSON null reads back
  # as NULL, which the constructor resolves to NA).
  artoo_spec(
    datasets = tables$datasets,
    variables = variables,
    codelists = pick("codelists"),
    study = pick("study"),
    values = tables$values,
    methods = pick("methods"),
    comments = pick("comments"),
    documents = pick("documents"),
    standard = raw[["standard"]],
    standards = pick("standards"),
    where_clauses = pick("where_clauses"),
    method_expressions = pick("method_expressions"),
    arm_displays = pick("arm_displays"),
    arm_results = pick("arm_results"),
    dictionaries = pick("dictionaries")
  )
}

#' @noRd
# Warn only when a file was written by a NEWER artoo than this one. An older
# file is read correctly -- every v1 field is still recognised -- so warning
# about it was false, and a warning that cries wolf gets filtered out.
#' @noRd
.check_spec_json_version <- function(v, call) {
  if (is.null(v)) {
    return(invisible())
  }
  v <- as.character(v)[1L]
  supported <- .spec_json_version
  newer <- suppressWarnings(as.numeric(v) > as.numeric(supported))
  if (isTRUE(newer) || is.na(newer) && !identical(v, supported)) {
    .artoo_warn(
      c(
        "Spec JSON version {.val {v}} is newer than the supported version {.val {supported}}.",
        "i" = "Reading anyway; fields added after {.val {supported}} are ignored."
      ),
      kind = "spec",
      call = call
    )
  }
  invisible()
}

# ---- Pinnacle 21 Excel --------------------------------------------------

#' @noRd
.read_spec_xlsx <- function(
  path,
  datasets = NULL,
  on_duplicate = "error",
  call = rlang::caller_env()
) {
  rlang::check_installed("readxl", reason = "to read a Pinnacle 21 Excel spec.")
  sheets <- readxl::excel_sheets(path)

  ds_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$datasets)
  var_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$variables)
  cl_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$codelists)
  vl_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$valuelevel)
  mt_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$methods)
  cm_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$comments)
  doc_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$documents)
  st_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$study)
  wc_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$whereclauses)
  dict_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$dictionaries)
  std_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$standards)
  ad_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$arm_displays)
  ar_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$arm_results)
  crit_sheet <- .match_p21_sheet(sheets, .p21_sheet_aliases$arm_criteria)

  scope <- datasets # the user's dataset filter; `datasets` becomes the table
  datasets <- .read_p21_tab(path, ds_sheet)
  variables <- .read_p21_tab(path, var_sheet, track_rows = TRUE)
  codelists <- .read_p21_tab(path, cl_sheet)
  values <- .read_p21_tab(path, vl_sheet)
  methods <- .read_p21_tab(path, mt_sheet)
  comments <- .read_p21_tab(path, cm_sheet)
  documents <- .read_p21_tab(path, doc_sheet)
  study_raw <- .read_p21_tab(path, st_sheet)
  where_raw <- .read_p21_tab(path, wc_sheet)
  dict_raw <- .read_p21_tab(path, dict_sheet)
  std_raw <- .read_p21_tab(path, std_sheet)
  ad_raw <- .read_p21_tab(path, ad_sheet)
  ar_raw <- .read_p21_tab(path, ar_sheet)
  crit_raw <- .read_p21_tab(path, crit_sheet)

  # A newer workbook generation carries BOTH "Label" and "Description".
  # Mapping both onto `label` yields two columns of the same name, so only
  # Label is mapped -- but a workbook that carries Description ALONE would
  # then read no label at all. Fall back only when Label mapped nothing.

  # Required sheets must be present AND carry rows (H7).
  .require_p21_sheet(datasets, ds_sheet, "Datasets", sheets, call)
  .require_p21_sheet(variables, var_sheet, "Variables", sheets, call)

  datasets <- .normalise_p21_cols(datasets, .p21_ds_map)
  variables <- .normalise_p21_cols(variables, .p21_var_map)
  codelists <- .normalise_p21_cols(codelists, .p21_codelist_map)
  values <- .normalise_p21_cols(values, .p21_value_map)
  # AFTER normalisation, and on all three sheets that carry a label. The
  # two workbook generations spell the header differently -- `Description`
  # in the older, `Label` in the newer -- and running this beforehand
  # guarded on a column name that did not exist yet, so a sheet carrying
  # both minted a ghost `label.1`, then a `label.2`, one per round trip.
  datasets <- .p21_description_fallback(datasets)
  variables <- .p21_description_fallback(variables)
  values <- .p21_description_fallback(values)
  methods <- .normalise_p21_cols(methods, .p21_method_map)
  comments <- .normalise_p21_cols(comments, .p21_comment_map)
  documents <- .normalise_p21_cols(documents, .p21_document_map)

  # Forward-fill the merged foreign-key columns (readxl leaves NA on
  # continuation rows of a merged cell), then trim stray whitespace so a
  # padded key still resolves.
  variables <- .fill_down(variables, "dataset")
  values <- .fill_down(values, "dataset")
  codelists <- .fill_down(codelists, "codelist_id")
  datasets <- .trim_cols(datasets, c("dataset", "comment_id"))
  variables <- .trim_cols(
    variables,
    c("dataset", "variable", "codelist_id", "method_id", "comment_id")
  )
  codelists <- .trim_cols(codelists, c("codelist_id", "comment_id"))
  methods <- .trim_cols(methods, c("method_id", "document_id"))
  comments <- .trim_cols(comments, c("comment_id", "document_id"))
  documents <- .trim_cols(documents, "document_id")

  # A still-blank dataset means a blank first row or broken merge: fail
  # loud rather than orphan the variable on an NA dataset.
  .check_filled(variables, "dataset", "Variables", call)

  # Scope to the requested datasets BEFORE the duplicate guard, so a
  # problem confined to another domain's rows never blocks this read; then
  # resolve duplicates with their actual sheet + Excel row locations.
  scoped <- .spec_scope_tables(
    list(datasets = datasets, variables = variables, values = values),
    scope,
    call
  )
  datasets <- scoped$datasets
  values <- scoped$values
  variables <- .resolve_duplicate_variables(
    scoped$variables,
    on_duplicate,
    where = sprintf("Sheet '%s'", var_sheet),
    rows = scoped$variables[[".artoo_row"]],
    call = call
  )
  variables[[".artoo_row"]] <- NULL

  # Drop P21 codelist header rows (an id/name but no submission term) and
  # trailing blank-key rows in the supporting-metadata sheets.
  codelists <- .scope_codelists(codelists, call)
  methods <- .drop_blank_key(methods, "method_id")
  comments <- .drop_blank_key(comments, "comment_id")
  documents <- .role_from_href(
    .normalise_document_roles(.drop_blank_key(documents, "document_id"))
  )

  # ---- where clauses, from whichever shape the workbook uses -------------
  # A WhereClauses sheet is authoritative; without one, the ValueLevel
  # "Where Clause" column holds free text and is parsed. The two generations
  # are distinguished by the sheet's presence, not by inspecting the column.
  where_clauses <- if (!is.null(where_raw) && nrow(where_raw)) {
    parsed <- .wc_from_sheet(
      .normalise_p21_cols(where_raw, .p21_where_map),
      call
    )
    .wc_check_value_refs(values, parsed, call)
    parsed
  } else {
    derived <- .wc_from_values(values, call)
    values <- derived$values
    derived$where_clauses
  }

  dictionaries <- .nullify_empty(
    .drop_blank_key(
      .normalise_p21_cols(dict_raw, .p21_dictionary_map),
      "dictionary_id"
    )
  )
  standards <- .nullify_empty(
    .drop_blank_key(
      .normalise_p21_cols(std_raw, .p21_standard_map),
      "standard_id"
    )
  )
  # A P21 workbook MERGES the display cell across a display's results and the
  # result id across a result's analysis-dataset rows, exactly as it merges
  # the dataset cell on the Variables sheet. Without the same forward fill
  # the continuation rows arrive with a blank key and .drop_blank_key()
  # deletes them -- silently, and most of the ARM with them.
  arm_displays <- .nullify_empty(
    .collapse_arm_displays(
      .drop_blank_key(
        .fill_down(
          .normalise_p21_cols(ad_raw, .p21_arm_display_map),
          "display_id"
        ),
        "display_id"
      ),
      call
    )
  )
  # Fill BOTH keys, then drop on the per-dataset payload rather than on the
  # key: filling `result_id` and dropping on a blank `result_id` makes the
  # drop unreachable for every row below the first, so a trailing "Note: see
  # SAP section 9.1" row is absorbed as a continuation of the last result.
  # This mirrors codelists, which fill `codelist_id` and drop on `term`.
  arm_results <- .nullify_empty(
    .drop_blank_arm_result(
      .fill_down(
        .fill_down(
          .normalise_p21_cols(ar_raw, .p21_arm_result_map),
          "display_id"
        ),
        "result_id"
      ),
      .normalise_p21_cols(ar_raw, .p21_arm_result_map)
    )
  )

  # The older generation keeps an analysis result's datasets on their own
  # sheet, at exactly artoo's grain. Joining it in is what gives a result
  # its `arm:AnalysisDataset` children; without it the result reached the
  # writer naming no dataset and the write refused it.
  arm_results <- .arm_join_criteria(
    arm_results,
    .nullify_empty(.normalise_p21_cols(crit_raw, .p21_arm_criteria_map)),
    call
  )
  resolved <- .arm_resolve_conditions(arm_results, where_clauses, call)
  arm_results <- resolved$arm_results
  where_clauses <- resolved$where_clauses

  # A Study sheet that states a standard name and version has said enough to
  # be a standards row, which is what Define-XML 2.1 needs and a bare name
  # is not.
  standards <- .mint_primary_standard(
    standards,
    .resolve_standard(
      NULL,
      datasets,
      .study_standard_pair(.p21_study(
        .nullify_empty(study_raw)
      )),
      call
    )
  )

  # Analysis results authored in the standard shape carry their datasets,
  # conditions and parameter packed into one Selection Criteria cell. Expand
  # it into artoo's grain and mint the clauses it names, reusing the same
  # parser the ValueLevel column goes through so the two cannot diverge.
  expanded <- .arm_from_criteria(arm_results, where_clauses, call)
  arm_results <- expanded$arm_results
  where_clauses <- expanded$where_clauses

  # A SECOND scoping pass. The tables above are built after the first one --
  # the where clauses are derived from the ValueLevel sheet, the analysis
  # results read from their own sheets -- so scoping only the first three
  # left every clause and analysis result naming an out-of-scope dataset
  # behind, dangling in the define written from it.
  late <- .spec_scope_tables(
    list(
      datasets = datasets,
      variables = variables,
      values = values,
      where_clauses = where_clauses,
      arm_displays = arm_displays,
      arm_results = arm_results
    ),
    scope,
    call
  )
  where_clauses <- late$where_clauses
  arm_displays <- late$arm_displays
  arm_results <- late$arm_results

  artoo_spec(
    datasets = datasets,
    variables = variables,
    codelists = .nullify_empty(codelists),
    study = .p21_study(.nullify_empty(study_raw)),
    values = .nullify_empty(values),
    methods = .nullify_empty(methods),
    comments = .nullify_empty(comments),
    documents = .nullify_empty(documents),
    where_clauses = where_clauses,
    dictionaries = dictionaries,
    standards = standards,
    arm_displays = arm_displays,
    arm_results = arm_results
  )
}

# Derive structured where clauses from the free-text ValueLevel column, for
# workbook generations that carry no WhereClauses sheet.
#
# Ids are CONTENT-ADDRESSED, not positional. Two properties matter:
#
#   * STABLE. A positional id shifts the moment the caller scopes the read to
#     a subset of datasets, so the same condition in the same workbook would
#     get a different id depending on how it was read.
#   * SHARED. Define-XML's model is one def:WhereClauseDef referenced by many
#     ItemRefs. Minting a fresh id per row emits a pile of identical
#     definitions instead.
#
# The id stays readable -- WC.<dataset>.<variable>, suffixed only on a genuine
# content collision -- rather than a hash of the values. Hashing is what the
# prior art does, and its own source calls that scheme legacy "warts and all".
#
# The minted id is written BACK into values$where_clause, converging both
# workbook generations on the foreign-key form. Otherwise the only link
# between a value-level row and its condition is the free text, and a writer
# could re-join them only by position -- which breaks silently the moment
# `values` is filtered or reordered.
#' @noRd
.wc_from_values <- function(values, call = rlang::caller_env()) {
  none <- list(where_clauses = NULL, values = values)
  if (
    is.null(values) ||
      !nrow(values) ||
      !"where_clause" %in% names(values)
  ) {
    return(none)
  }
  txt <- values$where_clause
  keep <- !is.na(txt) & nzchar(trimws(txt))
  if (!any(keep)) {
    return(none)
  }
  col <- function(nm) {
    if (nm %in% names(values)) {
      as.character(values[[nm]])
    } else {
      rep(NA_character_, nrow(values))
    }
  }
  ds <- col("dataset")
  vr <- col("variable")

  by_content <- new.env(parent = emptyenv())
  taken <- new.env(parent = emptyenv())
  parts <- list()
  ids <- rep(NA_character_, nrow(values))

  for (i in which(keep)) {
    if (is.na(ds[[i]]) || is.na(vr[[i]])) {
      .artoo_abort(
        c(
          "A value-level row carries a where clause but names no dataset or variable.",
          "x" = "Row {i}: {.val {txt[[i]]}}.",
          "i" = "A where clause qualifies a specific variable, so both are needed."
        ),
        kind = "p21_sheet",
        call = call
      )
    }
    key <- paste(ds[[i]], vr[[i]], trimws(txt[[i]]), sep = "\r")
    known <- by_content[[key]]
    if (!is.null(known)) {
      ids[[i]] <- known
      next
    }
    base <- sprintf("WC.%s.%s", ds[[i]], vr[[i]])
    id <- base
    n <- 1L
    while (!is.null(taken[[id]])) {
      n <- n + 1L
      id <- sprintf("%s.%d", base, n)
    }
    rows <- .wc_parse_text(txt[[i]], id, call)
    if (is.null(rows)) {
      next
    }
    # Only the unqualified checks belong to this value's dataset; a check
    # written `DM.COUNTRY EQ USA` named its own and the parser kept it.
    rows$dataset[is.na(rows$dataset)] <- ds[[i]]
    assign(id, TRUE, envir = taken)
    assign(key, id, envir = by_content)
    ids[[i]] <- id
    parts[[length(parts) + 1L]] <- rows
  }

  # Converge on the foreign-key form: the value-level row now names its
  # clause, exactly as a tabular workbook would.
  written <- !is.na(ids)
  values$where_clause[written] <- ids[written]

  list(
    where_clauses = if (length(parts)) do.call(rbind, parts) else NULL,
    values = values
  )
}

# Warn when a ValueLevel row names a where clause the sheet does not define.
# Matching is exact, so a case-only near-miss would otherwise be a silent
# dangling reference.
#' @noRd
.wc_check_value_refs <- function(values, parsed, call = rlang::caller_env()) {
  if (is.null(values) || !nrow(values) || !"where_clause" %in% names(values)) {
    return(invisible(NULL))
  }
  used <- unique(values$where_clause[!is.na(values$where_clause)])
  used <- used[nzchar(used)]
  known <- unique(parsed$where_clause_id)
  missing <- setdiff(used, known)
  if (!length(missing)) {
    return(invisible(NULL))
  }
  near <- missing[toupper(missing) %in% toupper(known)]
  msg <- "{length(missing)} value-level row{?s} name{?s/} a where clause the WhereClauses sheet does not define: {.val {missing}}."
  if (length(near)) {
    msg <- c(
      msg,
      "i" = "{.val {near}} differ{?s/} from a defined id only by case, and matching is exact."
    )
  }
  .artoo_warn(msg, kind = "spec", call = call)
  invisible(NULL)
}


# Match the first sheet whose normalised name is in the alias set. NULL
# when no sheet matches. When several sheets match the same role, inform
# which one was chosen so an ambiguous workbook is not silently resolved.
#' @noRd
.match_p21_sheet <- function(sheets, aliases) {
  norm <- function(x) gsub(" ", "", tolower(trimws(x)), fixed = TRUE)
  idx <- which(norm(sheets) %in% norm(aliases))
  if (!length(idx)) {
    return(NULL)
  }
  used <- sheets[idx[1L]]
  if (length(idx) > 1L) {
    ignored <- sheets[idx[-1L]]
    .artoo_inform(
      c(
        "Several sheets match one Pinnacle 21 role.",
        "i" = "Using {.val {used}}; ignoring {.val {ignored}}."
      ),
      kind = "p21_sheet"
    )
  }
  used
}

# Read one sheet as text and drop all-blank rows. NULL when the sheet is
# absent (sheet_name NULL); a 0-row data frame when present but empty.
# `track_rows = TRUE` records each data row's spreadsheet row number (data
# index + 1 for the header) in a `.artoo_row` column, BEFORE the blank-row
# filter, so a later finding can point at the exact Excel row.
#' @noRd
.read_p21_tab <- function(path, sheet_name, track_rows = FALSE) {
  if (is.null(sheet_name)) {
    return(NULL)
  }
  df <- as.data.frame(
    readxl::read_excel(path, sheet = sheet_name, col_types = "text"),
    stringsAsFactors = FALSE
  )
  if (nrow(df) && ncol(df)) {
    # Vectorise per column (each column is already a vector) and AND the
    # per-column blank masks, rather than rebuilding a 1-row frame per row.
    blank_cols <- lapply(df, function(col) {
      cc <- as.character(col)
      is.na(cc) | !nzchar(trimws(cc))
    })
    blank <- Reduce(`&`, blank_cols)
    if (track_rows) {
      df[[".artoo_row"]] <- seq_len(nrow(df)) + 1L
    }
    df <- df[!blank, , drop = FALSE]
    rownames(df) <- NULL
  } else if (track_rows && !is.null(df)) {
    df[[".artoo_row"]] <- integer(0)
  }
  df
}

#' @noRd
.require_p21_sheet <- function(df, sheet_name, label, sheets, call) {
  if (is.null(sheet_name) || is.null(df) || !nrow(df)) {
    .artoo_abort(
      c(
        "Required sheet {.val {label}} is missing or has no data rows.",
        "i" = "Available sheets: {.val {sheets}}."
      ),
      kind = "spec",
      call = call
    )
  }
  invisible(df)
}

# Rename columns via a P21 -> artoo map, matching header names
# case-insensitively and ignoring spaces. Unmapped columns keep their
# names. (Ported from herald-v0 normalise_p21_cols.)
#' @noRd
.normalise_p21_cols <- function(df, col_map) {
  if (is.null(df)) {
    return(NULL)
  }
  current <- tolower(trimws(names(df)))
  map_from <- tolower(names(col_map))
  map_to <- unname(col_map)

  new_names <- names(df)
  for (i in seq_along(map_from)) {
    idx <- which(current == map_from[i])
    if (length(idx)) {
      new_names[idx[1L]] <- map_to[i]
    }
  }
  current_ns <- gsub(" ", "", current, fixed = TRUE)
  map_from_ns <- gsub(" ", "", map_from, fixed = TRUE)
  for (i in seq_along(map_from_ns)) {
    idx <- which(current_ns == map_from_ns[i])
    if (length(idx) && new_names[idx[1L]] == names(df)[idx[1L]]) {
      new_names[idx[1L]] <- map_to[i]
    }
  }
  names(df) <- new_names
  rownames(df) <- NULL
  df
}

# Forward-fill NA (and blank) cells in one column from the last non-blank
# value above. Recovers merged cells in P21 spreadsheets.
# One row per display, after the merged-cell fill has given every
# continuation row the same id.
#
# A merged ID cell spanning a two-line description reads back as two rows
# naming one display. Emitting both writes two arm:ResultDisplay elements
# with the same OID -- schema-valid, because an OID is odm:oidref rather
# than xs:ID, and invisible to lint_define(). Rows that disagree on a
# non-blank value are refused rather than merged, the same policy the
# analysis-result headers follow.
#' @noRd
.collapse_arm_displays <- function(df, call = rlang::caller_env()) {
  if (is.null(df) || nrow(df) < 2L) {
    return(df)
  }
  ids <- as.character(df$display_id)
  if (!anyDuplicated(ids)) {
    return(df)
  }
  # MAPPED columns only. A foreign column artoo neither models nor emits is
  # no reason to refuse a workbook, and def:DocumentRef is maxOccurs
  # "unbounded" on arm:ResultDisplay -- a display citing two documents is
  # legal, and artoo carrying only the first is artoo's limit, not the
  # author's error.
  modelled <- intersect(unname(.p21_arm_display_map), names(df))
  columns <- setdiff(modelled, c("display_id", "document_id", "pages"))
  keep <- !duplicated(ids)
  out <- df[keep, , drop = FALSE]
  for (id in unique(ids[duplicated(ids)])) {
    rows <- df[ids == id, , drop = FALSE]
    for (column in columns) {
      values <- unique(as.character(rows[[column]]))
      values <- values[!is.na(values) & nzchar(trimws(values))]
      if (length(values) > 1L) {
        .artoo_abort(
          c(
            "Analysis display {.val {id}} is described two ways.",
            "x" = "Its rows disagree on {.field {column}}: {.val {values}}.",
            "i" = "One display is one row; a merged id cell may not span differing values."
          ),
          kind = "p21_sheet",
          call = call
        )
      }
      if (length(values)) {
        out[[column]][as.character(out$display_id) == id] <- values[[1]]
      }
    }
  }
  out
}

# Drop an analysis-result row that carries no analysis dataset of its own.
#
# The key cannot be the test here: `result_id` has just been forward-filled,
# so every row below the first has one. What marks a real row is the payload
# that varies per analysis dataset.
#' @noRd
.drop_blank_arm_result <- function(df, raw) {
  if (is.null(df) || !nrow(df)) {
    return(df)
  }
  # A row that named its OWN result id is not a continuation, whatever else
  # it carries -- its Dataset cell may simply have been merged with the row
  # above. Only rows the fill gave an id to are candidates for dropping, so
  # blankness is judged against the sheet as it was read.
  own_id <- if (is.null(raw) || !("result_id" %in% names(raw))) {
    rep(TRUE, nrow(df))
  } else {
    v <- as.character(raw$result_id)
    !is.na(v) & nzchar(trimws(v))
  }
  payload <- intersect(c("dataset", "variables", "where_clause_id"), names(df))
  if (!length(payload)) {
    return(.drop_blank_key(df, "result_id"))
  }
  filled <- Reduce(
    `|`,
    lapply(payload, function(column) {
      v <- as.character(df[[column]])
      !is.na(v) & nzchar(trimws(v))
    })
  )
  df[own_id | filled, , drop = FALSE]
}

# The document role, as a workbook spells it.
#
# artoo stores the role as the container it came out of (annotated_crf,
# supplemental, archive, other), but a person filling a Role cell writes
# "Annotated CRF". Recognising only the internal token meant a workbook that
# named its annotated CRF got no default, and every Pages cell then aborted
# telling the author to supply the CRF they had supplied.
#' @noRd
.normalise_document_roles <- function(df) {
  if (is.null(df) || !nrow(df) || !("role" %in% names(df))) {
    return(df)
  }
  key <- gsub("[^a-z]", "", tolower(trimws(as.character(df$role))))
  canonical <- c(
    annotatedcrf = "annotated_crf",
    acrf = "annotated_crf",
    crf = "annotated_crf",
    supplementaldoc = "supplemental",
    supplementaldocument = "supplemental",
    supplemental = "supplemental",
    archive = "archive",
    archivelocation = "archive",
    other = "other"
  )
  hit <- unname(canonical[key])
  df$role <- ifelse(is.na(hit), as.character(df$role), hit)
  df
}

# The document role a workbook does not state, from the href it does.
#
# The workbook format has no Role column -- that one is artoo's -- so the
# tooling that owns the format classifies by filename: lowercase the
# basename, and a name ENDING IN "crf" is the annotated CRF, anything else
# is a supplemental document, and a blank href is neither (a leaf that
# belongs to no container). `oncology-crf.pdf` is an annotated CRF;
# `acrf.pdf` is the usual spelling but not the rule.
#
# An explicit Role always wins: it is the only way to say something the
# filename cannot.
#' @noRd
.role_from_href <- function(df) {
  if (is.null(df) || !nrow(df) || !("href" %in% names(df))) {
    return(df)
  }
  if (!("role" %in% names(df))) {
    df$role <- NA_character_
  }
  href <- trimws(as.character(df$href))
  base <- tolower(sub("[.][^.]*$", "", basename(href)))
  derived <- ifelse(
    is.na(href) | !nzchar(href),
    NA_character_,
    ifelse(endsWith(base, "crf"), "annotated_crf", "supplemental")
  )
  blank <- is.na(df$role) | !nzchar(trimws(as.character(df$role)))
  df$role[blank] <- derived[blank]
  df
}

#' @noRd
.fill_down <- function(df, col) {
  if (is.null(df) || !(col %in% names(df)) || !nrow(df)) {
    return(df)
  }
  x <- df[[col]]
  x[!is.na(x) & !nzchar(trimws(x))] <- NA
  for (i in seq_along(x)[-1L]) {
    if (is.na(x[i])) {
      x[i] <- x[i - 1L]
    }
  }
  df[[col]] <- x
  df
}

#' @noRd
.trim_cols <- function(df, cols) {
  if (is.null(df)) {
    return(df)
  }
  for (col in intersect(cols, names(df))) {
    df[[col]] <- trimws(df[[col]])
  }
  df
}

#' @noRd
.check_filled <- function(df, col, label, call) {
  if (is.null(df) || !(col %in% names(df))) {
    return(invisible(df))
  }
  bad <- which(is.na(df[[col]]) | !nzchar(df[[col]]))
  if (length(bad)) {
    .artoo_abort(
      c(
        "Could not resolve {.field {col}} for some {label} rows.",
        "x" = "{cli::qty(bad)}Blank {.field {col}} on row{?s} {.val {bad}}.",
        "i" = "Check {.val {label}} for a blank first row or a broken merge."
      ),
      kind = "spec",
      call = call
    )
  }
  invisible(df)
}

# Finalize the P21 codelists frame: drop list-header rows (an id/name but no
# submission term), then verify every surviving term resolves to a codelist.
# .fill_down leaves row 1 unfilled, so a first-row term with a merged-away id
# would otherwise ride in as an orphan (codelist_id NA); catch it loudly, the
# way a blank dataset is caught for variables.
#' @noRd
.scope_codelists <- function(codelists, call = rlang::caller_env()) {
  codelists <- .drop_blank_key(codelists, "term")
  .check_filled(codelists, "codelist_id", "Codelists", call)
  codelists
}

# Drop rows whose primary key is blank (P21 sheets often have trailing
# rows with only Pages/Notes filled, and codelist list-header rows carry an
# id/name but no submission term).
#' @noRd
.drop_blank_key <- function(df, key) {
  if (is.null(df) || !(key %in% names(df))) {
    return(df)
  }
  keep <- !is.na(df[[key]]) & nzchar(trimws(df[[key]]))
  df[keep, , drop = FALSE]
}

#' @noRd
.nullify_empty <- function(df) {
  if (is.null(df) || !nrow(df)) NULL else df
}

# Pivot a P21 Define (Attribute / Value) sheet into a one-row wide study
# table whose columns are the attribute names.
# Use a "Description" column as the label when no "Label" column supplied one.
#' @noRd
.p21_description_fallback <- function(df) {
  if (is.null(df) || !nrow(df) || !"Description" %in% names(df)) {
    return(df)
  }
  if (!"label" %in% names(df) || all(is.na(df$label))) {
    df$label <- df[["Description"]]
    # CONSUMED, so removed. The two spellings name one fact, and leaving
    # the raw column behind meant the writer emitted it beside the one it
    # derives from `label` -- two columns of the same name, and one more
    # of them on every pass. When `Label` supplied the label, though, the
    # Description column was never consumed: it is the sponsor's own text,
    # possibly saying something different, and it survives as a foreign
    # column the way every unrecognised column does.
    df[["Description"]] <- NULL
  }
  df
}

#' @noRd
.p21_study <- function(df) {
  if (is.null(df) || nrow(df) < 1L || ncol(df) < 2L) {
    return(NULL)
  }
  attr_col <- trimws(as.character(df[[1L]]))
  val_col <- as.character(df[[2L]])
  keep <- !is.na(attr_col) & nzchar(attr_col)
  attr_col <- attr_col[keep]
  val_col <- val_col[keep]
  dup <- duplicated(attr_col)
  attr_col <- attr_col[!dup]
  val_col <- val_col[!dup]
  if (!length(attr_col)) {
    return(NULL)
  }
  out <- as.data.frame(
    as.list(val_col),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(out) <- attr_col
  out
}

# Expand a Selection Criteria cell into one row per analysis dataset, and
# mint the where clauses it names.
#
# The standard sheet is one row per analysis result and packs the datasets
# into that one cell, a bracket group each; artoo holds one row per result x
# dataset because each dataset carries its own condition and variable list.
# Without this the cell stayed opaque text, `dataset` and `where_clause_id`
# stayed NA, and the define write refused the result for naming no analysis
# dataset -- so the whole read-a-workbook-write-a-define path was dead for
# any spec with analysis results.
#
# Rows that already carry a dataset are left alone: those came from artoo's
# own decomposed columns, which say the same thing more precisely.
#' @noRd
.arm_from_criteria <- function(arm_results, where_clauses, call) {
  out <- list(arm_results = arm_results, where_clauses = where_clauses)
  if (
    is.null(arm_results) ||
      !nrow(arm_results) ||
      !"selection_criteria" %in% names(arm_results)
  ) {
    return(out)
  }
  text <- as.character(arm_results$selection_criteria)
  todo <- !is.na(text) & nzchar(trimws(text))
  if ("dataset" %in% names(arm_results)) {
    todo <- todo & .dx_blank(as.character(arm_results$dataset))
  }
  if (!any(todo)) {
    return(out)
  }
  rows <- list()
  pseudo <- list()
  at <- integer(0)
  for (i in seq_len(nrow(arm_results))) {
    if (!todo[[i]]) {
      rows[[length(rows) + 1L]] <- arm_results[i, , drop = FALSE]
      next
    }
    groups <- .arm_split_criteria(text[[i]])
    if (is.null(groups)) {
      .artoo_abort(
        c(
          "Analysis result {.val {arm_results$result_id[[i]]}} has selection criteria artoo cannot read.",
          "x" = "{.val {text[[i]]}}",
          "i" = "Expected one bracket group per analysis dataset, as {.code ADSL[SAFFL EQ Y]}."
        ),
        kind = "spec",
        call = call
      )
    }
    for (g in groups) {
      row <- arm_results[i, , drop = FALSE]
      row$dataset <- g$dataset
      # The variables cell spans every dataset of the result, each name
      # qualified by its own; give each group only its own. Unqualified
      # names belong to the group only when there is just one.
      if ("variables" %in% names(row)) {
        row$variables <- .arm_group_variables(
          arm_results$variables[[i]],
          g$dataset,
          length(groups)
        )
      }
      rows[[length(rows) + 1L]] <- row
      at <- c(at, length(rows))
      pseudo[[length(pseudo) + 1L]] <- data.frame(
        dataset = g$dataset,
        variable = as.character(arm_results$result_id[[i]]),
        where_clause = if (nzchar(g$condition)) g$condition else NA_character_,
        stringsAsFactors = FALSE
      )
    }
  }
  expanded <- do.call(rbind, rows)
  if (!length(pseudo)) {
    out$arm_results <- expanded
    return(out)
  }
  derived <- .wc_from_values(do.call(rbind, pseudo), call)
  # The parser replaces the expression in `where_clause` with the id it
  # minted, which is where the value-level path reads it from too.
  ids <- if ("where_clause" %in% names(derived$values)) {
    as.character(derived$values$where_clause)
  } else {
    rep(NA_character_, length(at))
  }
  if (!"where_clause_id" %in% names(expanded)) {
    expanded$where_clause_id <- NA_character_
  }
  # `at` indexes the expanded rows that produced a bracket group, in the
  # order the pseudo-frame was built, so the ids land back positionally.
  expanded$where_clause_id[at] <- ids
  out$arm_results <- expanded
  out$where_clauses <- if (is.null(where_clauses)) {
    derived$where_clauses
  } else {
    .dx_stack(where_clauses, derived$where_clauses)
  }
  out
}

# The analysis variables belonging to one dataset of a multi-dataset result.
#' @noRd
.arm_group_variables <- function(cell, dataset, n_groups) {
  if (is.null(cell) || is.na(cell) || !nzchar(trimws(cell))) {
    return(NA_character_)
  }
  tokens <- strsplit(trimws(as.character(cell)), "[[:space:],]+")[[1L]]
  tokens <- tokens[nzchar(tokens)]
  qualified <- grepl("[.]", tokens, fixed = FALSE)
  mine <- (qualified & startsWith(tokens, paste0(dataset, "."))) |
    (!qualified & n_groups == 1L)
  kept <- sub("^[^.]+[.]", "", tokens[mine])
  if (!length(kept)) NA_character_ else paste(kept, collapse = " ")
}

# Join the Analysis Criteria sheet onto the analysis results.
#
# The sheet is one row per (display, result, dataset); `arm_results` is one
# row per result x dataset. So the join expands a result into as many rows
# as it has analysis datasets, carrying each one's variables and condition,
# and a result with no criteria row keeps its single row unchanged.
#
# The condition is the same free-text grammar the ValueLevel cell uses, and
# it goes through the same parser -- one grammar, one implementation, so
# the two surfaces cannot drift.
#' @noRd
.arm_join_criteria <- function(arm_results, criteria, call) {
  if (
    is.null(criteria) ||
      !nrow(criteria) ||
      is.null(arm_results) ||
      !nrow(arm_results)
  ) {
    return(arm_results)
  }
  # Three columns are required and two are not, and the split is the
  # reference importer's: it declares Display, Result and Dataset required
  # and Variables and Where Clause optional, so a criteria row that names
  # no variables and no condition is ordinary authored data -- its own
  # control workbook carries exactly that row.
  #
  # Tolerating an absent REQUIRED column is a different thing, and it was
  # silent: without Display or Result the key matched nothing, the whole
  # sheet was discarded without a word, and the failure surfaced three
  # steps later at write time naming `arm_results` rather than the sheet
  # that caused it. Refuse here, where the column can be named.
  absent <- setdiff(c("display_id", "result_id", "dataset"), names(criteria))
  if (length(absent)) {
    headers <- names(.p21_arm_criteria_map)[
      match(absent, unname(.p21_arm_criteria_map))
    ]
    .artoo_abort(
      c(
        "The Analysis Criteria sheet is missing {length(headers)} required column{?s}: {.val {headers}}.",
        "x" = "Each row names the display, the result, and the analysis dataset it belongs to.",
        "i" = "Only {.val Variables} and {.val Where Clause} may be left out; remove the sheet if it carries no criteria."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  criteria <- .fill_down(.fill_down(criteria, "display_id"), "result_id")
  # The older Analysis Results sheet has none of these columns, so make
  # them before filling any in: adding a column to one row and not the
  # others gives rbind() frames of different widths.
  for (column in c("dataset", "variables", "where_clause_id")) {
    if (!(column %in% names(arm_results))) {
      arm_results[[column]] <- NA_character_
    }
    if (!(column %in% names(criteria))) {
      criteria[[column]] <- NA_character_
    }
  }
  key <- function(df) {
    paste(
      trimws(as.character(df$display_id)),
      trimws(as.character(df$result_id)),
      sep = "\r"
    )
  }
  ck <- key(criteria)
  rows <- list()
  overridden <- character(0)
  for (i in seq_len(nrow(arm_results))) {
    mine <- which(ck == key(arm_results[i, , drop = FALSE]))
    if (!length(mine)) {
      rows[[length(rows) + 1L]] <- arm_results[i, , drop = FALSE]
      next
    }
    # Once a criteria row hands this result a dataset, its own Selection
    # Criteria cell goes unread (.arm_from_criteria skips rows that carry
    # one) -- and the two can disagree. artoo's writer clears the cell when
    # it emits the sheet, so both being non-blank is a hand-authored
    # workbook saying the same thing twice; the sheet wins, out loud.
    cell <- if ("selection_criteria" %in% names(arm_results)) {
      as.character(arm_results$selection_criteria[[i]])
    } else {
      NA_character_
    }
    handed <- FALSE
    for (j in mine) {
      row <- arm_results[i, , drop = FALSE]
      for (column in c("dataset", "variables", "where_clause_id")) {
        value <- as.character(criteria[[column]][[j]])
        if (!is.na(value) && nzchar(trimws(value))) {
          row[[column]] <- value
          if (column == "dataset") {
            handed <- TRUE
          }
        }
      }
      rows[[length(rows) + 1L]] <- row
    }
    if (handed && !is.na(cell) && nzchar(trimws(cell))) {
      overridden <- c(overridden, as.character(arm_results$result_id[[i]]))
    }
  }
  if (length(overridden)) {
    .artoo_warn(
      c(
        "The Analysis Criteria sheet overrides the Selection Criteria cell of {length(unique(overridden))} analysis result{?s}: {.val {unique(overridden)}}.",
        "i" = "Both name analysis datasets for the same result; the sheet wins and the cell is ignored."
      ),
      kind = "spec",
      call = call
    )
  }
  do.call(rbind, rows)
}

# An analysis result's where-clause cell may hold the CONDITION rather than
# the id of one, exactly as a value-level cell may. Parse those and put the
# minted id in their place, leaving alone any cell that already names a
# clause the workbook defines.
#
# The same parser the ValueLevel column goes through, so one grammar has one
# implementation and the two surfaces cannot drift.
#' @noRd
.arm_resolve_conditions <- function(arm_results, where_clauses, call) {
  out <- list(arm_results = arm_results, where_clauses = where_clauses)
  if (
    is.null(arm_results) ||
      !nrow(arm_results) ||
      !("where_clause_id" %in% names(arm_results))
  ) {
    return(out)
  }
  known <- if (is.null(where_clauses)) {
    character(0)
  } else {
    unique(as.character(where_clauses$where_clause_id))
  }
  cell <- as.character(arm_results$where_clause_id)
  todo <- !is.na(cell) & nzchar(trimws(cell)) & !(cell %in% known)
  if (!any(todo)) {
    return(out)
  }
  pseudo <- data.frame(
    dataset = as.character(arm_results$dataset)[todo],
    variable = as.character(arm_results$result_id)[todo],
    where_clause = cell[todo],
    stringsAsFactors = FALSE
  )
  derived <- .wc_from_values(pseudo, call)
  out$arm_results$where_clause_id[todo] <- as.character(
    derived$values$where_clause
  )
  out$where_clauses <- if (is.null(where_clauses)) {
    derived$where_clauses
  } else {
    .dx_stack(where_clauses, derived$where_clauses)
  }
  out
}
