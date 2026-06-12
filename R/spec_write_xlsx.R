# spec_write_xlsx.R — .write_spec_xlsx(): artoo_spec -> Pinnacle 21 Excel.
#
# The symmetric inverse of the P21 reader (spec_read.R). Every header and
# sheet name is DERIVED from the reader's authoritative .p21_*_map /
# .p21_sheet_aliases constants, so the two surfaces cannot drift: a column
# the reader recognises is exactly a column the writer emits. Foreign keys
# are repeated on every row (no merged cells), so the reader's .fill_down
# pass is a no-op on our own output.
#
# Honest contract: native JSON is the lossless format; P21 xlsx is the
# interchange format. Spec fields with no P21 column (itemoid,
# target_data_type, per-variable key_sequence, codelist `extended`) are
# not emitted and do not survive an xlsx round-trip. The data_type column is
# re-encoded into the Define-XML / ODM vocabulary (.to_define_datatype): a
# character variable becomes "text" (ODM has no "string"), and decimal/double
# collapse to "float", boolean/URI to "text" -- a non-injective map, so those
# four canonical spellings do not survive an xlsx round-trip (they fold to
# string/float on read). The lossless native JSON keeps the canonical spelling.

# Reverse a reader map (P21 header -> artoo column) into a writer map
# (artoo column -> P21 header), preserving the reader's column order.
#' @noRd
.p21_rev <- function(map) {
  stats::setNames(names(map), unname(map))
}

# Project one spec slot onto its P21 sheet: the mapped columns that exist
# (in P21 header order, renamed to the P21 headers), then any foreign columns
# the source carried that artoo does not model, emitted verbatim under their
# own names. The reader already retains those foreign columns, so re-emitting
# them keeps the xlsx round-trip from silently dropping user columns. Canonical
# columns that have no P21 header (`itemoid`, `target_data_type`,
# `key_sequence`, ...) are listed in `canonical` and stay unemitted -- they
# survive only through the lossless native JSON. Logical columns become the P21
# "Yes"/"No" convention. Returns NULL when no MAPPED column is present, so a
# slot carrying only foreign columns does not conjure a sheet.
#' @noRd
.p21_sheet_frame <- function(df, map, canonical = unname(map)) {
  if (is.null(df) || !is.data.frame(df) || !nrow(df)) {
    return(NULL)
  }
  rev_map <- .p21_rev(map)
  mapped <- intersect(names(rev_map), names(df))
  if (!length(mapped)) {
    return(NULL)
  }
  foreign <- setdiff(names(df), c(canonical, names(rev_map), ".artoo_row"))
  out <- df[c(mapped, foreign)]
  for (nm in foreign) {
    out[[nm]] <- as.character(out[[nm]])
  }
  for (nm in mapped) {
    if (is.logical(out[[nm]])) {
      out[[nm]] <- ifelse(is.na(out[[nm]]), NA, ifelse(out[[nm]], "Yes", "No"))
    }
  }
  names(out) <- c(unname(rev_map[mapped]), foreign)
  out
}

# The study row as the P21 Define sheet (Attribute/Value, one attribute
# per row). Canonical fields write back under their P21 spellings; the
# round-trip closes because the reader's .p21_study pivot feeds the
# constructor, whose .study_field_aliases recognise exactly these names.
# Unknown study fields are emitted verbatim (losslessness). NULL when the
# study row is empty or all-blank, so the sheet is omitted entirely.
#' @noRd
.p21_study_attr <- c(
  study_name = "StudyName",
  study_description = "StudyDescription",
  protocol_name = "ProtocolName"
)

#' @noRd
.p21_study_sheet <- function(study) {
  if (is.null(study) || !is.data.frame(study) || !nrow(study)) {
    return(NULL)
  }
  attrs <- ifelse(
    names(study) %in% names(.p21_study_attr),
    .p21_study_attr[names(study)],
    names(study)
  )
  vals <- vapply(study, function(v) as.character(v)[1L], character(1))
  keep <- !is.na(vals) & nzchar(trimws(vals))
  if (!any(keep)) {
    return(NULL)
  }
  data.frame(
    Attribute = unname(attrs[keep]),
    Value = unname(vals[keep]),
    stringsAsFactors = FALSE
  )
}

#' @noRd
.write_spec_xlsx <- function(spec, path, call = rlang::caller_env()) {
  rlang::check_installed(
    "writexl",
    reason = "to write a Pinnacle 21 Excel spec."
  )

  datasets <- spec@datasets
  # The spec's one standard is interchange-encoded as the P21 Datasets
  # sheet's repeated Standard column (the shape the reader's resolver
  # consumes), not a bespoke study sheet.
  if (!is.na(spec@standard) && nrow(datasets)) {
    datasets$standard <- spec@standard
  }

  # Re-encode the canonical dataType into the Define-XML / ODM vocabulary the
  # P21 "Data Type" column expects ("text", not "string"). Variables and
  # ValueLevel are the only slots with a data_type column.
  variables <- spec@variables
  if ("data_type" %in% names(variables) && nrow(variables)) {
    variables$data_type <- .to_define_datatype(variables$data_type)
  }
  values <- spec@values
  if ("data_type" %in% names(values) && nrow(values)) {
    values$data_type <- .to_define_datatype(values$data_type)
  }

  sheets <- list(
    Define = .p21_study_sheet(spec@study),
    Datasets = .p21_sheet_frame(
      datasets,
      .p21_ds_map,
      names(.spec_cols_datasets)
    ),
    Variables = .p21_sheet_frame(
      variables,
      .p21_var_map,
      names(.spec_cols_variables)
    ),
    # The value-level slot has no fixed schema; its canonical columns are
    # exactly the P21-mapped ones, so the default `canonical` applies.
    ValueLevel = .p21_sheet_frame(values, .p21_value_map),
    # The P21 Codelists "Comment" column is free text, not a Comment-ID
    # reference; .p21_codelist_map deliberately has no comment_id entry, so
    # the projection can never emit one (mirroring the reader). Listing
    # comment_id as canonical keeps it out of the foreign-column passthrough.
    Codelists = .p21_sheet_frame(
      spec@codelists,
      .p21_codelist_map,
      names(.spec_cols_codelists)
    ),
    Methods = .p21_sheet_frame(
      spec@methods,
      .p21_method_map,
      names(.spec_cols_methods)
    ),
    Comments = .p21_sheet_frame(
      spec@comments,
      .p21_comment_map,
      names(.spec_cols_comments)
    ),
    Documents = .p21_sheet_frame(
      spec@documents,
      .p21_document_map,
      names(.spec_cols_documents)
    )
  )
  # Datasets and Variables are the sheets the reader requires; the optional
  # ones are omitted when empty.
  required <- c("Datasets", "Variables")
  missing <- required[vapply(sheets[required], is.null, logical(1))]
  if (length(missing)) {
    .artoo_abort(
      c(
        "Cannot write a Pinnacle 21 workbook from an empty spec.",
        "x" = "The {.val {missing}} sheet{?s} {?has/have} no rows."
      ),
      kind = "spec",
      call = call
    )
  }
  sheets <- sheets[!vapply(sheets, is.null, logical(1))]

  # Build in a sibling tempfile, then move into place atomically (the same
  # crash-safety contract as every artoo codec).
  tmp <- tempfile(fileext = ".xlsx", tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writexl::write_xlsx(sheets, tmp)
  .move_into_place(tmp, path, call = call)

  invisible(path)
}
