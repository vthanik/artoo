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

#' Write a specification to JSON, an Excel workbook, or Define-XML
#'
#' Serialise a `artoo_spec`, dispatching on the file extension: a `.json`
#' path writes artoo's native, lossless JSON; a `.xlsx` path writes a
#' Pinnacle 21 (P21) style Excel workbook; a `.xml` path writes a
#' submission-grade Define-XML 2.1 or 2.0 document. Each is the inverse of
#' [read_spec()] on its format, which makes the spec converters free
#' compositions: `read_spec("spec.xlsx") |> write_spec("define.xml")` turns
#' a workbook into a define.xml in one line.
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
#' **Note:** the xlsx writer emits every sheet the spec has content for, so
#' `standards`, `where_clauses`, `arm_displays`, `arm_results` and
#' `dictionaries` survive a round trip. `method_expressions` does not
#' survive whole: a workbook gives each method one row with one code cell,
#' so a method carrying several formal expressions keeps only the first and
#' the write says which methods it truncated. Write JSON when a spec has
#' multi-expression methods, or when you need back the OIDs a Define-XML
#' document chose.
#'
#' **Define-XML is the submission format.** The `.xml` path emits
#' Define-XML 2.1 or 2.0 (needs the `xml2` package) and SCHEMA-VALIDATES what it
#' built before the file reaches its destination, so an invalid document
#' never overwrites a good one. Value-level metadata is emitted whole: the
#' parent variable's `def:ValueListRef`, the `def:ValueListDef`, a real
#' `ItemDef` per value-level row, and the `def:WhereClauseRef` and
#' `def:WhereClauseDef` that say which rows it applies to.
#'
#' Identifiers already on the spec are reused verbatim, so a document read
#' and written back keeps every OID a reviewer may have bookmarked; the rest
#' are minted readably (`IG.DM`, `IT.DM.USUBJID`, `VL.VS.VSORRES`). Two
#' schema-required attributes are derived rather than demanded:
#' `def:Structure` falls back to the dataset keys, and `Purpose` follows the
#' CDISC standard. A dataset with neither a structure nor keys aborts with
#' `artoo_error_define` rather than being given an invented one.
#'
#' **HTML.** A define.xml renders through an XSLT stylesheet, and the written
#' document names one in a processing instruction and gets a copy of it
#' alongside (a reference to a stylesheet that is not there is itself a
#' conformance finding). An existing stylesheet beside the output is never
#' overwritten, so a customised rendering survives. Pass `html = TRUE` to also
#' materialise the rendered HTML: browsers are removing XSLT support, and a
#' reviewer working from a submission archive should not need one.
#'
#' **What a folder measures.** A named list describes the frames in memory; a
#' folder describes the bytes on disk. Where the two differ the folder is
#' right about what will be submitted -- a transport file pads to fixed width,
#' so a value's trailing blanks are part of it there and not in R. A gzipped
#' `.json` or `.ndjson` is matched like any other file; `.xpt.gz` is not,
#' because [read_dataset()] does not read one either.
#'
#' **A folder instead of a list.** `data` also takes one path to the folder
#' holding the datasets. Each dataset the spec names is matched to a file
#' whose basename is that name, ignoring case: `DM` to `dm.xpt`, `dm.json`,
#' `dm.parquet`. The folder is inventoried, not descended. A dataset with no
#' file is normal and reported, not an error, and a file the spec does not
#' name is left alone. A dataset matching MORE than one file aborts rather
#' than choosing: two formats can disagree about byte width, so picking one
#' silently would change the document. Name the format with `data_format` to
#' resolve it. A file that cannot be read aborts too, naming every unreadable
#' file at once rather than stopping at the first.
#'
#' **Data-aware writing.** Pass `data` and artoo reads the datasets the
#' define describes, which a spec-only tool cannot. A blank `length` is
#' filled from the real maximum byte width; a stated one shorter than the
#' data is widened, because a length below the real maximum is a conformance
#' finding, and the write says which variables it widened. A stated length
#' LONGER than the data is left alone: a length is a claim about the domain,
#' not about one extract. Value-level metadata is derived for the standard
#' findings shapes -- a result keyed by its test code, `TSVAL` by `TSPARMCD`,
#' `QVAL` by `QNAM`, `AVAL` and `AVALC` by `PARAMCD` -- with each derived row
#' carrying the type and width of the rows it covers. A variable the spec
#' already gives value-level rows to is never touched. A dataset with no
#' records is flagged `def:HasNoData` when it also carries a comment
#' explaining the absence, and left unflagged with a warning when it does
#' not.
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
#'   picks the format: `.json` (native, lossless), `.xlsx` (P21
#'   interchange; needs the `writexl` package), or `.xml` (Define-XML;
#'   needs the `xml2` package). Any other extension aborts with
#'   `artoo_error_input`.
#' @param ... *Format-specific options.* Ignored by the JSON and xlsx paths.
#'   Define-XML accepts:
#'
#'   * `version` -- `<character(1)> | NULL`. `"2.1"` (default) or `"2.0"`,
#'     resolved from the spec's own `define_version` when unset. Writing 2.0
#'     from a 2.1-shaped spec warns about each construct 2.0 cannot carry.
#'   * `created` -- the `CreationDateTime` stamp, formatted as UTC. Freeze it
#'     for a reproducible submission build; the default is the current time.
#'   * `stylesheet` -- `<logical(1)> | <character(1)>: default TRUE`. `TRUE`
#'     writes the `xml-stylesheet` processing instruction and copies the
#'     bundled CDISC stylesheet beside the output; a string names a
#'     stylesheet without copying one; `FALSE` writes neither.
#'   * `data` -- `<list of <data.frame>> | <character(1)> | NULL`. The
#'     datasets the define describes: a list named for each dataset, or one
#'     path to the folder holding them. artoo reads them and fills what the
#'     spec leaves blank; see **Data-aware writing**.
#'   * `data_format` -- `<character> | NULL`. When `data` is a folder,
#'     restrict it to these formats, named as [artoo_formats()] lists them.
#'     Use it when a folder holds one dataset in two formats.
#'   * `html` -- `<logical(1)> | <character(1)>: default FALSE`. `TRUE` also
#'     renders the document through its stylesheet into a sibling `.html`; a
#'     string renders it to that path. Needs the `xslt` and `callr` packages.
#'   * `validate` -- `<logical(1)>: default TRUE`. Schema-validate before the
#'     file is put in place.
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
#' # ---- Example 3: the same spec as a submission-grade define.xml ----
#' #
#' # Read the bundled minimal Define-XML, write it back with a frozen
#' # timestamp, and confirm the result is schema-valid. The write itself
#' # validates, so reaching this line already proves it.
#' if (requireNamespace("xml2", quietly = TRUE)) {
#'   dm <- read_spec(
#'     system.file("extdata", "define-minimal.xml", package = "artoo")
#'   )
#'   xml <- file.path(tempdir(), "define.xml")
#'   write_spec(dm, xml, created = "2020-01-01 00:00:00")
#'   validate_define(xml)
#' }
#'
#' # ---- Example 4: let a folder of datasets fill the blanks ----
#' #
#' # A spec states a variable's length or leaves it blank. Point `data` at
#' # the folder holding the datasets and artoo matches each one the spec
#' # names to a file called after it, then fills the blanks from the real
#' # maximum byte width. It reports which files it used, because a define is
#' # a submission document and that is what a reader cannot recover from it.
#' if (requireNamespace("xml2", quietly = TRUE)) {
#'   folder <- file.path(tempdir(), "datasets")
#'   dir.create(folder, showWarnings = FALSE)
#'   write_json(
#'     apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off"),
#'     file.path(folder, "adsl.json")
#'   )
#'   from_folder <- file.path(tempdir(), "from-folder.xml")
#'   write_spec(adam_spec, from_folder, data = folder)
#'   lint_define(from_folder)
#' }
#'
#' @seealso
#' **Inverse:** [read_spec()] reads native JSON, a P21 Excel workbook, or
#' Define-XML back into a `artoo_spec`.
#'
#' **Check the Define-XML written:** [validate_define()] schema-validates it,
#' [lint_define()] checks its reference integrity.
#'
#' **Build / inspect:** [artoo_spec()], [spec_datasets()],
#' [spec_variables()], [spec_standard()].
#' @export
write_spec <- function(spec, path, ...) {
  call <- rlang::caller_env()
  .check_path(path, call = call)
  # Route through the shared guard rather than a bare predicate: is_artoo_spec()
  # returns TRUE for a spec saved by an older artoo, so a bare check here would
  # let a stale object straight into the writer -- past the whole migration.
  spec <- .check_spec_arg(spec, call = call)
  ext <- tolower(tools::file_ext(path))
  switch(
    ext,
    json = {
      # Silently ignoring `data =` or `version =` on a .json path makes a
      # mistyped extension look like it worked.
      rlang::check_dots_empty0(..., call = call)
      .write_spec_json(spec, path, call)
    },
    xlsx = {
      rlang::check_dots_empty0(..., call = call)
      .write_spec_xlsx(spec, path, call)
    },
    xml = .write_spec_define(spec, path, ..., call = call),
    .artoo_abort(
      c(
        "Unsupported spec file type {.val {ext}}.",
        "i" = "write_spec() writes native {.val .json} (lossless), Pinnacle 21 {.val .xlsx} (interchange), and Define-XML {.val .xml} (submission)."
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
