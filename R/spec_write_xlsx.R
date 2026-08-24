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
# target_data_type, per-variable key_sequence, codelist `extended`) are not
# emitted and do not survive an xlsx round-trip -- except on the ValueLevel
# sheet, whose canonical columns ARE its mapped ones, so everything else it
# carries rides out as a foreign column under its own snake_case name.
# .p21_warn_dropped() names the losses for the spec in hand rather than
# leaving this paragraph to be read as the whole story. The data_type column is
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
# "Yes"/"No" convention. Returns NULL when no MAPPED column carries a value,
# so a slot holding only foreign columns does not conjure a sheet. The test is
# on CONTENT, not presence: every slot is coerced to its full schema now, so
# the mapped columns are always there and an all-NA set means the slot has
# nothing this workbook can express.
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
  if (all(vapply(df[mapped], function(col) all(is.na(col)), logical(1)))) {
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
  protocol_name = "ProtocolName",
  # The document identifiers a Define-XML read carries. Without spellings
  # of their own they went onto the sheet under artoo's INTERNAL column
  # names -- a Define sheet reading `metadata_version_oid`, `odm_context`,
  # `study_oid` -- which is artoo's private vocabulary leaking onto a
  # surface a person reads and another tool imports.
  define_version = "DefineVersion",
  study_oid = "StudyOID",
  file_oid = "FileOID",
  odm_context = "Context",
  metadata_version_oid = "MetaDataVersionOID",
  metadata_version_name = "MetaDataVersionName",
  metadata_version_description = "MetaDataVersionDescription",
  originator = "Originator",
  source_system = "SourceSystem",
  source_system_version = "SourceSystemVersion",
  language = "Language",
  standard_name = "StandardName",
  standard_version = "StandardVersion"
)

#' @noRd
.p21_study_sheet <- function(study, standard = NA_character_) {
  study <- .p21_study_standard_rows(study, standard)
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

  # One slot still has no sheet -- a workbook has no column for a method's
  # formal expressions -- so writing xlsx drops it. Silence would be exactly
  # the silent truncation this project forbids.
  .p21_warn_dropped(spec, call)

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
  # The ValueLevel "Where Clause" cell holds the RENDERED EXPRESSION, and
  # there is no separate where-clause sheet. That sheet belongs to a retired
  # workbook generation whose ValueLevel named its label column differently,
  # so emitting it beside current-generation headers produced a workbook of
  # no generation at all; emitting the expression beside it left every
  # value-level row naming a clause the same workbook did not define.
  clauses <- spec@where_clauses
  has_rows <- function(x) !is.null(x) && is.data.frame(x) && nrow(x) > 0L
  if (
    has_rows(values) &&
      has_rows(clauses) &&
      "where_clause_id" %in% names(values)
  ) {
    rendered <- .wc_render(clauses)
    at <- match(values$where_clause_id, names(rendered))
    values$where_clause[!is.na(at)] <- unname(rendered[at[!is.na(at)]])
  }

  sheets <- list(
    Define = .p21_study_sheet(spec@study, spec@standard),
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
    # Named canonical explicitly: the default treats every unmapped schema
    # column as foreign, so the sheet carried fourteen empty snake_case
    # ghost headers, and after reading a workbook it carried both `Source`
    # and `source`.
    ValueLevel = .p21_sheet_frame(
      values,
      .p21_value_map,
      names(.spec_cols_values)
    ),
    Codelists = .p21_sheet_frame(
      spec@codelists,
      .p21_codelist_map,
      names(.spec_cols_codelists)
    ),
    Methods = .p21_sheet_frame(
      .p21_inline_expressions(spec@methods, spec@method_expressions),
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
    ),
    # No WhereClauses sheet: the current generation dropped it and carries
    # the condition as an expression in the ValueLevel cell above. artoo
    # still READS the retired two-sheet shape.
    Dictionaries = .p21_sheet_frame(
      spec@dictionaries,
      .p21_dictionary_map,
      names(.spec_cols_dictionaries)
    ),
    Standards = .p21_sheet_frame(
      spec@standards,
      .p21_standard_map,
      names(.spec_cols_standards)
    ),
    `Analysis Displays` = .p21_sheet_frame(
      spec@arm_displays,
      .p21_arm_display_map,
      names(.spec_cols_arm_displays)
    ),
    `Analysis Results` = .p21_arm_result_sheet(spec@arm_results, clauses)
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


# What a rendered where-clause expression carries. Shaped like a reader map
# (header -> column) so the drop warning treats it the same way; the names
# are the parts of the expression rather than sheet headers.
#' @noRd
.p21_where_expression <- c(
  "id" = "where_clause_id",
  "order" = "check_order",
  "dataset" = "dataset",
  "variable" = "variable",
  "comparator" = "comparator",
  "value" = "value",
  "value order" = "value_order"
)

# Every slot that HAS a sheet, paired with the reader map that defines what
# that sheet can carry. One list, used by both the writer and the drop
# warning, so a map gaining a header teaches both at once.
#' @noRd
.p21_slot_maps <- list(
  datasets = list(.spec_cols_datasets, .p21_ds_map),
  variables = list(.spec_cols_variables, .p21_var_map),
  # A where clause has no sheet: it rides in the ValueLevel expression, which
  # carries the variable, the comparator and the values (in order) and
  # nothing else. So the pairing is against what the EXPRESSION expresses,
  # not against a sheet's headers.
  where_clauses = list(.spec_cols_where_clauses, .p21_where_expression),
  codelists = list(.spec_cols_codelists, .p21_codelist_map),
  dictionaries = list(.spec_cols_dictionaries, .p21_dictionary_map),
  methods = list(.spec_cols_methods, .p21_method_map),
  comments = list(.spec_cols_comments, .p21_comment_map),
  documents = list(.spec_cols_documents, .p21_document_map),
  standards = list(.spec_cols_standards, .p21_standard_map),
  arm_displays = list(.spec_cols_arm_displays, .p21_arm_display_map),
  arm_results = list(.spec_cols_arm_results, .p21_arm_result_map)
)

# The two columns no sheet has a header for and none needs one: the
# WhereClauses sheet encodes them in its SHAPE -- one row per range check,
# a set comparator's values collapsed into one cell -- and the reader
# rebuilds both on read. Excluded from the warning because nothing is lost.
#
# `order` is deliberately NOT here. Four slots have no Order column, and a
# populated `order` on any of them really is dropped.
#' @noRd
.p21_structural <- c("check_order", "value_order")


# Columns with no header of their own that the workbook can nonetheless
# rebuild, so nothing is lost. Each entry is a predicate on (slot, spec),
# TRUE only when THIS spec's values really do survive -- a blanket "always
# recovered" would put a silent truncation inside the very mechanism built
# to prevent one.
#
# `key_sequence` is rebuilt by .derive_key_sequence() from the Datasets
# sheet's Key Variables, which recovers it only when that string agrees with
# the column: with no keys string the column is lost outright, and with a
# keys string in a different order the read-back is silently RE-SORTED, which
# changes the define's sort keys downstream. So the predicate runs the
# rebuild and compares.
#
# `soft_hard` survives only while every value is the "Soft" the reader
# assumes for a workbook clause.
#' @noRd
.p21_recovered <- list(
  variables = list(
    key_sequence = function(df, spec) {
      blank <- df
      blank$key_sequence <- NA_integer_
      rebuilt <- .derive_key_sequence(spec@datasets, blank)
      identical(rebuilt$key_sequence, df$key_sequence)
    }
  ),
  where_clauses = list(
    soft_hard = function(df, spec) {
      all(is.na(df$soft_hard) | df$soft_hard == "Soft")
    }
  )
)

# The Analysis Results sheet, one row per RESULT.
#
# artoo holds one row per result x analysis dataset, because each dataset
# carries its own where clause and its own variable list. The sheet holds
# one row per result and packs the datasets into `Selection Criteria`, a
# bracket group each, with the variables comma-separated and prefixed by
# their dataset. Projecting artoo's grain row for row wrote a result twice
# and dropped the criteria entirely, so a define written from the result
# had no `arm:AnalysisDataset` to hang a where clause on.
#' @noRd
.p21_arm_result_sheet <- function(ar, clauses) {
  if (is.null(ar) || !nrow(ar)) {
    return(NULL)
  }
  rendered <- .wc_render(clauses)
  key <- paste(ar$display_id, ar$result_id, sep = "\r")
  first <- ar[!duplicated(key), , drop = FALSE]
  parts <- split(seq_len(nrow(ar)), factor(key, levels = unique(key)))
  first$selection_criteria <- vapply(
    parts,
    function(rows) .arm_render_criteria(ar[rows, , drop = FALSE], rendered),
    character(1)
  )
  # Variables are dataset-qualified so one cell can span several datasets.
  first$variables <- vapply(
    parts,
    function(rows) {
      qualified <- unlist(lapply(rows, function(i) {
        vars <- .arm_variable_names(ar$variables[[i]])
        if (!length(vars)) {
          return(NULL)
        }
        paste0(ar$dataset[[i]], ".", vars)
      }))
      if (!length(qualified)) {
        NA_character_
      } else {
        paste(qualified, collapse = ", ")
      }
    },
    character(1)
  )
  # Where the criteria say it all, the decomposition must go: it describes
  # only the FIRST analysis dataset of the result, and a reader that trusts
  # it silently drops every other group. One statement per fact.
  said <- !is.na(first$selection_criteria)
  first$dataset[said] <- NA_character_
  first$where_clause_id[said] <- NA_character_
  .p21_sheet_frame(
    first,
    .p21_arm_result_map,
    c(names(.spec_cols_arm_results), "selection_criteria")
  )
}

# Name what a Pinnacle 21 workbook cannot carry: the one slot with no sheet
# at all, and the populated COLUMNS whose slot has a sheet with no header
# for them. Both lists are derived -- the slot from the sheet builders, the
# columns from the reader maps -- so neither can drift out of step with the
# workbook actually written.
#
# The column half exists because the five sheets the Define-XML work added
# closed the slot-level gaps and opened column-level ones: `standards` gets
# a sheet, but P21 has no column for which standard is primary, and silence
# there is the same silent truncation the slot warning was written against.
#' @noRd
.p21_dropped_cols <- function(spec) {
  out <- lapply(names(.p21_slot_maps), function(nm) {
    df <- S7::prop(spec, nm)
    if (is.null(df) || !nrow(df)) {
      return(character(0))
    }
    pair <- .p21_slot_maps[[nm]]
    unmapped <- setdiff(names(pair[[1]]), c(unname(pair[[2]]), .p21_structural))
    held <- intersect(unmapped, names(df))
    held <- held[!vapply(df[held], function(col) all(is.na(col)), logical(1))]
    recovered <- .p21_recovered[[nm]]
    keep <- vapply(
      held,
      function(cl) is.null(recovered[[cl]]) || !recovered[[cl]](df, spec),
      logical(1)
    )
    held[keep]
  })
  names(out) <- names(.p21_slot_maps)
  out[lengths(out) > 0L]
}

#' @noRd
.p21_warn_dropped <- function(spec, call = rlang::caller_env()) {
  msg <- character(0)
  # The Methods sheet carries ONE formal expression per method, in its
  # context and code columns. A method with more than one keeps the first.
  expressions <- spec@method_expressions
  if (!is.null(expressions) && nrow(expressions)) {
    extra <- unique(expressions$method_id[duplicated(expressions$method_id)])
    if (length(extra)) {
      msg <- c(
        msg,
        "x" = cli::format_inline(
          "{.field methods}: only the first formal expression of {.val {extra}}."
        )
      )
    }
  }
  cols <- .p21_dropped_cols(spec)
  for (nm in names(cols)) {
    lost <- cols[[nm]]
    # Formatted NOW, not left for cli to interpolate: the condition is built
    # once after the loop, by which time `nm` and `lost` hold the last slot.
    msg <- c(msg, "x" = cli::format_inline("{.field {nm}}: {.val {lost}}"))
  }
  if (!length(msg)) {
    return(invisible(NULL))
  }
  .artoo_warn(
    c(
      "A Pinnacle 21 workbook cannot carry all of this spec.",
      msg,
      "i" = "That is dropped here; write {.val .json} to keep the spec whole."
    ),
    kind = "spec",
    call = call
  )
  invisible(NULL)
}

# Put each method's first formal expression back in the two columns the
# Methods sheet carries it in.
#' @noRd
.p21_inline_expressions <- function(methods, expressions) {
  if (
    is.null(methods) ||
      !nrow(methods) ||
      is.null(expressions) ||
      !nrow(expressions)
  ) {
    return(methods)
  }
  first <- expressions[!duplicated(expressions$method_id), , drop = FALSE]
  at <- match(as.character(methods$method_id), as.character(first$method_id))
  found <- !is.na(at)
  methods$expression_context[found] <- as.character(first$context)[at[found]]
  methods$expression_code[found] <- as.character(first$code)[at[found]]
  methods
}

# State the standard on the study sheet, the way the format does.
#
# The sheet carries a standard as two attributes, a name and a version, and
# artoo reads that pair into `@standard`. It never wrote it back, so a
# workbook artoo produced could not say which standard it described -- the
# fact survived only in the Datasets sheet's repeated column, and a reader
# looking where the format puts it found nothing.
#' @noRd
.p21_study_standard_rows <- function(study, standard) {
  if (is.na(standard) || !nzchar(standard)) {
    return(study)
  }
  parts <- strsplit(trimws(standard), "[[:space:]]+")[[1L]]
  if (length(parts) < 2L) {
    return(study)
  }
  name <- paste(utils::head(parts, -1L), collapse = " ")
  # Written in the spelling the format uses, which is the hyphenated one
  # the reader already renames on the way in.
  back <- .dx_standard_renames
  hit <- match(name, unname(back))
  if (!is.na(hit)) {
    name <- names(back)[[hit]]
  }
  if (is.null(study) || !is.data.frame(study) || !nrow(study)) {
    study <- data.frame(row.names = 1L)
  }
  study$standard_name <- name
  study$standard_version <- utils::tail(parts, 1L)
  study
}
