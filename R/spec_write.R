# spec_write.R -- write_spec(): serialise a vport_spec to native JSON.

# The vport_spec slots serialised to / read from JSON, in canonical order.
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
  "documents"
)

# Current native-spec JSON schema version, stamped into every file and
# checked (leniently) on read.
#' @noRd
.spec_json_version <- "1"

#' Write a specification to native vport JSON
#'
#' Serialise a `vport_spec` to vport's native JSON format: one lossless,
#' UTF-8 document carrying every slot (study, datasets, variables,
#' codelists, value-level) verbatim. It is the inverse of [read_spec()]
#' on the JSON path, and the canonical way to persist a spec or move it
#' between sessions. vport never writes a spec to xlsx.
#'
#' @details
#' **Lossless by reconstruction.** Each slot is written as an array of row
#' objects, with `NA` encoded as JSON `null` and numbers at full precision,
#' so [read_spec()] rebuilds an identical `vport_spec` through
#' [vport_spec()]. Object keys are emitted in a fixed order, so writing the
#' same spec twice yields byte-identical output.
#'
#' @param spec *The specification to serialise.* `<vport_spec>: required`.
#'   Build one with [vport_spec()] or [read_spec()].
#' @param path *Destination file.* `<character(1)>: required`. Written as
#'   UTF-8; conventionally ends in `.json`.
#'
#' @return *The output `path`, invisibly.* Read it back with [read_spec()].
#'
#' @examples
#' # ---- Example 1: persist a spec, then read it back ----
#' #
#' # Build a spec from the bundled CDISC-pilot tables, write it to a temp
#' # JSON file, and confirm read_spec() reconstructs it intact.
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' path <- tempfile(fileext = ".json")
#' write_spec(spec, path)
#' identical(read_spec(path), spec)
#'
#' # ---- Example 2: round-trip a single-dataset spec ----
#' #
#' # Slice the bundled tables to DM, write, and read back -- the datasets
#' # accessor reports the same dataset.
#' dm <- vport_spec(
#'   cdisc_datasets[cdisc_datasets$dataset == "DM", ],
#'   cdisc_variables[cdisc_variables$dataset == "DM", ],
#'   codelists = cdisc_codelists
#' )
#' dm_path <- tempfile(fileext = ".json")
#' write_spec(dm, dm_path)
#' spec_datasets(read_spec(dm_path))
#'
#' @seealso
#' **Inverse:** [read_spec()] reads native JSON or a P21 Excel spec back
#' into a `vport_spec`.
#'
#' **Build / inspect:** [vport_spec()], [spec_datasets()],
#' [spec_variables()].
#' @export
write_spec <- function(spec, path) {
  call <- rlang::caller_env()
  .check_path(path, call = call)
  if (!is_vport_spec(spec)) {
    cli::cli_abort(
      c(
        "{.arg spec} must be a {.cls vport_spec}.",
        "x" = "You supplied {.obj_type_friendly {spec}}.",
        "i" = "Build one with {.fn vport_spec}."
      ),
      class = "vport_error_input",
      call = call
    )
  }

  # Fixed key order: version first, then each slot in canonical order. A
  # NULL `values` slot is emitted as JSON null (null = "null").
  payload <- c(
    list(vport_spec_version = .spec_json_version),
    lapply(.spec_json_slots, function(s) S7::prop(spec, s))
  )
  names(payload) <- c("vport_spec_version", .spec_json_slots)

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
