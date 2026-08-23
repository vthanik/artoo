# spec_write.R — write_spec(): serialise a artoo_spec to native JSON.

# The artoo_spec slots serialised to / read from JSON, in canonical order.
# Shared by write_spec() (payload key order) and read_spec() (slot
# extraction) so the two surfaces cannot drift.
#' @noRd
.spec_json_slots <- c(
  "study",
  "datasets",
  "variables",
  "codelists",
  "values",
  "methods",
  "comments",
  "documents",
  "standards",
  "where_clauses",
  "method_expressions",
  "arm_displays",
  "arm_results",
  "dictionaries"
)

# Current native-spec JSON schema version, stamped into every file and
# checked (leniently) on read.
# Bumped to "2" when the five structural slots plus the reserved
# dictionaries table were added. The bump matters in one direction: an OLDER
# artoo reading a v2 file asks only for the keys it knows, so it would drop
# the new slots SILENTLY. .check_spec_json_version() warns on a mismatch,
# which only fires if this number actually moves.
#' @noRd
.spec_json_version <- "2"

#' Write a specification to native JSON or a P21 Excel workbook
#'
#' Serialise a `artoo_spec`, dispatching on the file extension: a `.json`
#' path writes artoo's native, lossless JSON; a `.xlsx` path writes a
#' Pinnacle 21 (P21) style Excel workbook. Both are inverses of
#' [read_spec()] on their format, which makes the spec converters free
#' compositions: `read_spec("define.xml") |> write_spec("spec.xlsx")` is a
#' Define-XML to P21 bridge in one line.
#'
#' @details
#' **Native JSON is the lossless format.** Each slot is written as an array
#' of row objects, with `NA` encoded as JSON `null` and numbers at full
#' precision, so [read_spec()] rebuilds an identical `artoo_spec` through
#' [artoo_spec()]. Object keys are emitted in a fixed order, so writing the
#' same spec twice yields byte-identical output.
#'
#' **P21 xlsx is the interchange format.** Sheets are emitted with the
#' headers the P21 reader recognises (Define, Datasets, Variables,
#' ValueLevel, Codelists, Methods, Comments, Documents; empty optional
#' sheets are omitted), foreign keys repeated on every row (no merged
#' cells), and the spec's [spec_standard()] as the Datasets sheet's
#' `Standard` column. The study row writes back as the Define sheet's
#' Attribute/Value pairs (`StudyName`, `StudyDescription`,
#' `ProtocolName`). The `Data Type` column is written in the Define-XML /
#' ODM vocabulary the workbook expects: a character variable is `text`
#' (not the Dataset-JSON `string`), and `decimal` / `double` collapse to
#' `float`, `boolean` / `URI` to `text`.
#'
#' Columns the P21 vocabulary does not model are not lost: a foreign column
#' carried on a slot is re-emitted verbatim under its own header, so an xlsx
#' round-trip keeps user columns.
#'
#' **Note:** the xlsx writer emits the eight classic P21 sheets, so the
#' `standards`, `where_clauses`, `method_expressions`, `arm_displays`,
#' `arm_results` and `dictionaries` tables are dropped on that path. Reading a
#' Define-XML document and writing it to xlsx therefore loses its
#' `def:Standards` block, its structured where clauses and its formal
#' expressions. Write JSON when you need the spec back whole.
#'
#' Fields with no P21 column (`itemoid`, `target_data_type`,
#' per-variable `key_sequence`) likewise do not survive an xlsx round-trip;
#' persist to JSON when you need the spec back exactly. The `Data Type`
#' re-encoding is also non-injective: `decimal`, `double`, `boolean`, and
#' `URI` fold to `float` or `text` on a read-back. A Define-XML
#' `partialDate` / `partialDatetime` (and the other partial / incomplete
#' subtypes) is read as the base `date` / `datetime` -- CDISC Dataset-JSON
#' v1.1 has no partial dataType -- so it is written back as the base type.
#'
#' @param spec *The specification to serialise.* `<artoo_spec>: required`.
#'   Build one with [artoo_spec()] or [read_spec()].
#' @param path *Destination file.* `<character(1)>: required`. The extension
#'   picks the format: `.json` (native, lossless) or `.xlsx` (P21
#'   interchange; needs the `writexl` package). Any other extension aborts
#'   with `artoo_error_input`.
#'
#' @return *The output `path`, invisibly.* Read it back with [read_spec()].
#'
#' @examples
#' # ---- Example 1: persist a spec to JSON, then read it back ----
#' #
#' # Build a spec from the bundled CDISC-pilot tables, write it to a temp
#' # JSON file, and confirm read_spec() reconstructs it intact.
#' spec <- artoo_spec(
#'   cdisc_adam_datasets, cdisc_adam_variables,
#'   codelists = cdisc_codelists
#' )
#' path <- tempfile(fileext = ".json")
#' write_spec(spec, path)
#' identical(read_spec(path), spec)
#'
#' # ---- Example 2: the same spec as a P21 workbook ----
#' #
#' # The .xlsx path emits P21-shaped sheets; reading the workbook back
#' # recovers the P21-representable surface (here: the dataset names).
#' if (requireNamespace("writexl", quietly = TRUE)) {
#'   xlsx <- tempfile(fileext = ".xlsx")
#'   write_spec(spec, xlsx)
#'   spec_datasets(read_spec(xlsx))
#' }
#'
#' @seealso
#' **Inverse:** [read_spec()] reads native JSON, a P21 Excel workbook, or
#' Define-XML back into a `artoo_spec`.
#'
#' **Build / inspect:** [artoo_spec()], [spec_datasets()],
#' [spec_variables()], [spec_standard()].
#' @export
write_spec <- function(spec, path) {
  call <- rlang::caller_env()
  .check_path(path, call = call)
  # Route through the shared guard rather than a bare predicate: is_artoo_spec()
  # returns TRUE for a spec saved by an older artoo, so a bare check here would
  # let a stale object straight into the writer -- past the whole migration.
  spec <- .check_spec_arg(spec, call = call)
  ext <- tolower(tools::file_ext(path))
  switch(
    ext,
    json = .write_spec_json(spec, path, call),
    xlsx = .write_spec_xlsx(spec, path, call),
    .artoo_abort(
      c(
        "Unsupported spec file type {.val {ext}}.",
        "i" = "write_spec() writes native {.val .json} (lossless) and Pinnacle 21 {.val .xlsx} (interchange)."
      ),
      kind = "input",
      call = call
    )
  )
}

#' @noRd
.write_spec_json <- function(spec, path, call = rlang::caller_env()) {
  # Fixed key order: version, then the scalar standard, then each slot in
  # canonical order. A NULL `values` slot is emitted as JSON null
  # (null = "null"); an NA standard likewise serialises to null.
  payload <- c(
    list(artoo_spec_version = .spec_json_version, standard = spec@standard),
    lapply(.spec_json_slots, function(s) S7::prop(spec, s))
  )
  names(payload) <- c("artoo_spec_version", "standard", .spec_json_slots)

  json <- jsonlite::toJSON(
    payload,
    dataframe = "rows",
    na = "null",
    null = "null",
    auto_unbox = TRUE,
    digits = NA,
    pretty = TRUE
  )

  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  writeLines(json, con)

  invisible(path)
}
