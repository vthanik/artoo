# spec_read.R -- read_spec(): native JSON + Pinnacle 21 Excel -> vport_spec.
#
# The P21 Excel parser is ported from the herald-v0 archive
# (R/spec-read.R) and hardened: vport-targeted column maps, alias-set
# sheet matching, merged-cell forward fill on every foreign-key column,
# and fail-loud on an unresolvable key. Every path funnels through
# vport_spec(), which is the single validation surface.

# ---- P21 -> vport column maps (spreadsheet header -> vport slot column) ---
# Headers not listed ride along as extra character columns (no silent
# drop); vport columns absent from P21 are filled with typed NA by the
# vport_spec() constructor.

#' @noRd
.p21_ds_map <- c(
  "Dataset" = "dataset",
  "Label" = "label",
  "Class" = "class",
  "SubClass" = "subclass",
  "Structure" = "structure",
  "Key Variables" = "keys",
  "Standard" = "standard",
  "Comment" = "comment_id"
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
  "Pages" = "pages",
  "Method" = "method_id",
  "Predecessor" = "predecessor",
  "Role" = "role",
  "Comment" = "comment_id"
)

#' @noRd
# Note: the P21 Codelists "Comment" column is conventionally inline free
# text (a description of the codelist), NOT a Comment-ID reference like the
# Variables/Datasets "Comment" columns -- so it is deliberately NOT mapped
# to `comment_id` (which would yield false "unresolved comment" findings).
.p21_codelist_map <- c(
  "ID" = "codelist_id",
  "Order" = "order",
  "Term" = "term",
  "Decoded Value" = "decode"
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
  "Comment" = "comment_id"
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
  "Href" = "href"
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
  study = c("define", "study", "metadata")
)

#' Read a specification from JSON, Excel, or Define-XML
#'
#' Read a clinical-dataset specification into a validated `vport_spec`,
#' dispatching on the file extension: vport's native JSON (the inverse of
#' [write_spec()]), a Pinnacle 21 (P21) Excel workbook, or a native
#' Define-XML 2.0/2.1 document. The returned spec is the lingua franca the
#' rest of vport applies and serialises.
#'
#' @details
#' **Three formats, one validator.** A `.json` file is read as vport native
#' JSON; a `.xlsx` / `.xls` file is read as a P21 workbook; a `.xml` file is
#' read as Define-XML 2.x. Either way the result is built through
#' [vport_spec()], so type canonicalisation and cross-slot integrity checks
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
#'   **Note:** an `ExternalCodeList` (MedDRA, ISO-3166) names a dictionary,
#'   not an enumerable membership list; it is dropped, and variables that
#'   referenced it carry no codelist. Define-XML v1.0 (the 2005 model) is
#'   refused with guidance.
#'
#' **P21 ingestion.** Sheets are located by a tolerant alias match
#' (case-, space-, and spelling-variant insensitive). Datasets and
#' Variables are required; Codelists and ValueLevel are optional (the
#' latter becomes the spec's value-level slot). Every cell is read as
#' text, then the dataset and codelist foreign keys are forward-filled to
#' recover merged cells (which the Excel reader returns as `NA` on
#' continuation rows). A key that cannot be resolved aborts with
#' `vport_error_spec` rather than being silently dropped.
#'
#' @param path *The specification file to read.* `<character(1)>:
#'   required`. A `.json` (native) or `.xlsx` / `.xls` (P21) file.
#'
#'   **Requirement:** reading a P21 workbook needs the `readxl` package.
#'
#' @return *A validated `vport_spec`.* Inspect it with [spec_datasets()] /
#'   [spec_variables()], check it with [validate_spec()], or persist it
#'   with [write_spec()].
#'
#' @examples
#' # ---- Example 1: round-trip a spec through native JSON ----
#' #
#' # write_spec() and read_spec() are inverses on the JSON path: the spec
#' # that comes back is identical to the one written.
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' path <- tempfile(fileext = ".json")
#' write_spec(spec, path)
#' back <- read_spec(path)
#' identical(back, spec)
#'
#' # ---- Example 2: read back, then inspect a dataset's variables ----
#' #
#' # A spec read from disk behaves exactly like one built in memory -- the
#' # accessors work unchanged.
#' head(spec_variables(back, "DM")[, c("variable", "label", "data_type")])
#'
#' @seealso
#' **Inverse:** [write_spec()] serialises a spec to native JSON.
#'
#' **Build / inspect:** [vport_spec()], [spec_datasets()],
#' [spec_variables()], [validate_spec()].
#' @export
read_spec <- function(path) {
  call <- rlang::caller_env()
  .check_path(path, call = call)
  if (!file.exists(path)) {
    cli::cli_abort(
      c(
        "Spec file {.path {path}} does not exist.",
        "i" = "Pass a path to a {.val .json} or {.val .xlsx} spec."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  ext <- tolower(tools::file_ext(path))
  switch(
    ext,
    json = .read_spec_json(path, call),
    xlsx = ,
    xls = .read_spec_xlsx(path, call),
    xml = .read_spec_define(path, call),
    cli::cli_abort(
      c(
        "Unsupported spec file type {.val {ext}}.",
        "i" = "read_spec() reads {.val .json}, Pinnacle 21 {.val .xlsx}, and Define-XML 2.x {.val .xml}."
      ),
      class = "vport_error_input",
      call = call
    )
  )
}

# ---- Native JSON --------------------------------------------------------

#' @noRd
.read_spec_json <- function(path, call = rlang::caller_env()) {
  raw <- jsonlite::fromJSON(path, simplifyDataFrame = TRUE)
  .check_spec_json_version(raw[["vport_spec_version"]], call)

  # An empty array [] simplifies to an empty list; a JSON null to NULL.
  # Both mean "no rows" -> NULL, which vport_spec() rebuilds as the typed
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

  vport_spec(
    datasets = pick("datasets"),
    variables = pick("variables"),
    codelists = pick("codelists"),
    study = pick("study"),
    values = pick("values"),
    methods = pick("methods"),
    comments = pick("comments"),
    documents = pick("documents")
  )
}

#' @noRd
.check_spec_json_version <- function(v, call) {
  if (is.null(v)) {
    return(invisible())
  }
  v <- as.character(v)[1L]
  supported <- .spec_json_version
  if (!identical(v, supported)) {
    cli::cli_warn(
      c(
        "Spec JSON version {.val {v}} is not the supported version {.val {supported}}.",
        "i" = "Reading anyway; some fields may not be recognised."
      ),
      class = "vport_warning_spec",
      call = call
    )
  }
  invisible()
}

# ---- Pinnacle 21 Excel --------------------------------------------------

#' @noRd
.read_spec_xlsx <- function(path, call = rlang::caller_env()) {
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

  datasets <- .read_p21_tab(path, ds_sheet)
  variables <- .read_p21_tab(path, var_sheet)
  codelists <- .read_p21_tab(path, cl_sheet)
  values <- .read_p21_tab(path, vl_sheet)
  methods <- .read_p21_tab(path, mt_sheet)
  comments <- .read_p21_tab(path, cm_sheet)
  documents <- .read_p21_tab(path, doc_sheet)
  study_raw <- .read_p21_tab(path, st_sheet)

  # Required sheets must be present AND carry rows (H7).
  .require_p21_sheet(datasets, ds_sheet, "Datasets", sheets, call)
  .require_p21_sheet(variables, var_sheet, "Variables", sheets, call)

  datasets <- .normalise_p21_cols(datasets, .p21_ds_map)
  variables <- .normalise_p21_cols(variables, .p21_var_map)
  codelists <- .normalise_p21_cols(codelists, .p21_codelist_map)
  values <- .normalise_p21_cols(values, .p21_value_map)
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

  # Drop P21 codelist header rows (an id/name but no submission term) and
  # trailing blank-key rows in the supporting-metadata sheets.
  codelists <- .drop_termless(codelists)
  methods <- .drop_blank_key(methods, "method_id")
  comments <- .drop_blank_key(comments, "comment_id")
  documents <- .drop_blank_key(documents, "document_id")

  vport_spec(
    datasets = datasets,
    variables = variables,
    codelists = .nullify_empty(codelists),
    study = .p21_study(.nullify_empty(study_raw)),
    values = .nullify_empty(values),
    methods = .nullify_empty(methods),
    comments = .nullify_empty(comments),
    documents = .nullify_empty(documents)
  )
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
    cli::cli_inform(
      c(
        "Several sheets match one Pinnacle 21 role.",
        "i" = "Using {.val {used}}; ignoring {.val {ignored}}."
      ),
      class = "vport_message_p21_sheet"
    )
  }
  used
}

# Read one sheet as text and drop all-blank rows. NULL when the sheet is
# absent (sheet_name NULL); a 0-row data frame when present but empty.
#' @noRd
.read_p21_tab <- function(path, sheet_name) {
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
    df <- df[!blank, , drop = FALSE]
    rownames(df) <- NULL
  }
  df
}

#' @noRd
.require_p21_sheet <- function(df, sheet_name, label, sheets, call) {
  if (is.null(sheet_name) || is.null(df) || !nrow(df)) {
    cli::cli_abort(
      c(
        "Required sheet {.val {label}} is missing or has no data rows.",
        "i" = "Available sheets: {.val {sheets}}."
      ),
      class = "vport_error_spec",
      call = call
    )
  }
  invisible(df)
}

# Rename columns via a P21 -> vport map, matching header names
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
    cli::cli_abort(
      c(
        "Could not resolve {.field {col}} for some {label} rows.",
        "x" = "{cli::qty(bad)}Blank {.field {col}} on row{?s} {.val {bad}}.",
        "i" = "Check {.val {label}} for a blank first row or a broken merge."
      ),
      class = "vport_error_spec",
      call = call
    )
  }
  invisible(df)
}

# Drop codelist rows that carry no submission term (P21 list-header rows).
#' @noRd
.drop_termless <- function(df) {
  if (is.null(df) || !("term" %in% names(df))) {
    return(df)
  }
  keep <- !is.na(df$term) & nzchar(trimws(df$term))
  df[keep, , drop = FALSE]
}

# Drop rows whose primary key is blank (P21 sheets often have trailing
# rows with only Pages/Notes filled).
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
