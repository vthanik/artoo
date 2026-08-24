# spec_template.R — write_template(): a blank, correctly-shaped P21 workbook.
#
# Every sheet name and every header is DERIVED from the reader's own maps
# (.p21_sheet_aliases, .p21_*_map in spec_read.R), so a template can only
# offer columns read_spec() understands. Adding a column to the reader adds
# it to the template; there is no second list to keep in step.
#
# The gap this closes: a spec author starting from scratch has to guess what
# a workbook should look like, and every guess that is wrong is a column
# silently ignored on read. A template is the reader's own answer to that
# question, in the shape it wants.

# The canonical sheet name for each slot, and the order a spec author works
# in: study first, then the structure, then the metadata it references.
#' @noRd
.p21_template_sheets <- c(
  study = "Define",
  datasets = "Datasets",
  variables = "Variables",
  valuelevel = "ValueLevel",
  whereclauses = "WhereClauses",
  codelists = "Codelists",
  dictionaries = "Dictionaries",
  methods = "Methods",
  comments = "Comments",
  documents = "Documents",
  standards = "Standards",
  arm_displays = "Analysis Displays",
  arm_results = "Analysis Results"
)

# Headers Define-XML 2.1 introduced. A 2.0 template omits them, because a
# column no 2.0 document can carry is a column an author fills for nothing.
#
# Each traces to something the version profiles already derive from the
# bundled XSDs: def:SubClass and def:HasNoData exist only in 2.1's attribute
# tables, and def:Origin/@Source only in 2.1's local-attribute table. A test
# pins that correspondence, so a CDISC revision cannot move one without
# failing here.
#' @noRd
.p21_template_since <- list(
  Datasets = c("SubClass", "Has No Data"),
  Variables = c("Source", "Has No Data")
)

# The Define sheet is Attribute/Value rather than one column per field, so
# it is seeded with the three attributes the reader canonicalises.
#' @noRd
.p21_template_define <- function() {
  data.frame(
    Attribute = unname(.p21_study_attr),
    Value = rep(NA_character_, length(.p21_study_attr)),
    stringsAsFactors = FALSE
  )
}

# One blank sheet: the reader's headers for a slot, in the reader's order,
# minus anything the target version has no use for.
#' @noRd
.p21_template_frame <- function(map, sheet, version) {
  headers <- names(map)
  if (version == "2.0") {
    headers <- setdiff(headers, .p21_template_since[[sheet]])
  }
  out <- rep(list(character(0)), length(headers))
  names(out) <- headers
  as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Write a blank Pinnacle 21 workbook to fill in
#'
#' Emit an empty Excel workbook with the sheets and column headers
#' [read_spec()] recognises, so a specification can be authored from the
#' shape the reader wants rather than guessed at. Fill it in, read it back
#' with [read_spec()], and write a define.xml with [write_spec()].
#'
#' @details
#' **The headers are the reader's own.** Every sheet name and every column
#' comes from the same maps [read_spec()] matches against, so a template
#' cannot offer a column that would be silently ignored, and a column added
#' to the reader appears here without a second list to maintain.
#'
#' **A 2.0 template is narrower.** Columns Define-XML 2.1 introduced
#' (`SubClass` and `Has No Data` on Datasets, `Source` and `Has No Data` on
#' Variables) are omitted from a 2.0 template, because a column no 2.0
#' document can carry is one an author fills for nothing.
#'
#' **Only Datasets and Variables are required.** Every other sheet may be
#' left empty; [read_spec()] omits what it finds nothing in. The
#' `WhereClauses`, `Standards`, `Dictionaries` and analysis-results sheets
#' belong to newer workbook generations, and an older workbook simply carries
#' its value-level conditions as free text in `ValueLevel`.
#'
#' @param path *Destination workbook.* `<character(1)>: required`. An
#'   `.xlsx` path. Needs the `writexl` package.
#' @param version *Define-XML version the workbook is for.*
#'   `<character(1)>: default "2.1"`.
#'
#'   * `"2.1"` (default)
#'   * `"2.0"` -- omits the columns 2.1 introduced.
#'
#' @return *The output `path`, invisibly.* Fill it in, then read it with
#'   [read_spec()].
#'
#' @examples
#' # ---- Example 1: a blank workbook, and what it offers ----
#' #
#' # The template carries every sheet read_spec() recognises. Datasets and
#' # Variables are the two it requires; the rest may be left empty.
#' path <- tempfile(fileext = ".xlsx")
#' write_template(path)
#' if (requireNamespace("readxl", quietly = TRUE)) {
#'   readxl::excel_sheets(path)
#' }
#'
#' # ---- Example 2: the 2.0 template omits what 2.0 cannot carry ----
#' #
#' # `Source` records who collected a value, which Define-XML 2.1 added. A
#' # 2.0 workbook has no column for it, so the template does not offer one.
#' old <- tempfile(fileext = ".xlsx")
#' write_template(old, version = "2.0")
#' if (requireNamespace("readxl", quietly = TRUE)) {
#'   setdiff(
#'     names(readxl::read_excel(path, sheet = "Variables")),
#'     names(readxl::read_excel(old, sheet = "Variables"))
#'   )
#' }
#'
#' @seealso
#' **Fill it in:** [read_spec()] reads the completed workbook.
#'
#' **Then write:** [write_spec()] turns the spec into a define.xml,
#' [validate_define()] and [lint_define()] check the result.
#' @export
write_template <- function(path, version = "2.1") {
  # current_env(), not caller_env(): this IS the user's call, so naming the
  # caller leaves a bare "Error:" with no function attached, unlike every
  # other entry point.
  call <- rlang::current_env()
  .check_path(path, call = call)
  rlang::check_installed(
    "writexl",
    reason = "to write a Pinnacle 21 workbook."
  )
  ext <- tolower(tools::file_ext(path))
  if (!identical(ext, "xlsx")) {
    .artoo_abort(
      c(
        "A workbook template is written as {.val .xlsx}.",
        "x" = "You gave {.path {path}}."
      ),
      kind = "input",
      call = call
    )
  }
  # Reuse the version profile so "2.0" and "2.1" mean here exactly what they
  # mean to the Define-XML writer, and an unknown one is refused once.
  target <- .define_profile(version, call)$version

  maps <- list(
    datasets = .p21_ds_map,
    variables = .p21_var_map,
    valuelevel = .p21_value_map,
    whereclauses = .p21_where_map,
    codelists = .p21_codelist_map,
    dictionaries = .p21_dictionary_map,
    methods = .p21_method_map,
    comments = .p21_comment_map,
    documents = .p21_document_map,
    standards = .p21_standard_map,
    arm_displays = .p21_arm_display_map,
    arm_results = .p21_arm_result_map
  )
  sheets <- list(Define = .p21_template_define())
  for (slot in names(maps)) {
    sheet <- unname(.p21_template_sheets[[slot]])
    sheets[[sheet]] <- .p21_template_frame(maps[[slot]], sheet, target)
  }
  sheets <- sheets[unname(.p21_template_sheets)]

  .with_atomic_write(
    path,
    ".xlsx",
    function(tmp) writexl::write_xlsx(sheets, tmp),
    call = call
  )
  invisible(path)
}
