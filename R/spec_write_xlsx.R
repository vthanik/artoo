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
  # Each dataset's OWN standard, as the display string the reader's linker
  # resolves back into `standard_id`. Stamping the scalar over every row
  # mislabelled the rows that name another standard -- CDISC's own 2.1 SDTM
  # example names three across its datasets. A row linked to nothing falls
  # back to the scalar, which keeps the resolver fed on the classic
  # one-standard shape.
  if (nrow(datasets)) {
    per_row <- .p21_dataset_standard(datasets, spec@standards)
    per_row[is.na(per_row)] <- spec@standard
    if (any(!is.na(per_row))) {
      datasets$standard <- per_row
    }
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
  # The ValueLevel "Where Clause" cell holds the clause's ID, and the
  # WhereClauses sheet below defines it. The importer treats the cell as a
  # foreign key -- it looks the id up and raises a per-row reference error
  # when it does not resolve -- so a rendered condition there is not a
  # condition to it, it is a name for a clause that does not exist.
  clauses <- spec@where_clauses
  has_rows <- function(x) !is.null(x) && is.data.frame(x) && nrow(x) > 0L
  if (
    has_rows(values) &&
      has_rows(clauses) &&
      "where_clause_id" %in% names(values)
  ) {
    # Render each clause as the ROW that references it would read it back:
    # an unqualified name in the cell belongs to that row's dataset.
    owner <- stats::setNames(
      as.character(values$dataset),
      as.character(values$where_clause_id)
    )
    owner <- owner[!duplicated(names(owner))]
    known <- values$where_clause_id %in% clauses$where_clause_id
    values$where_clause[known] <- values$where_clause_id[known]
  }

  sheets <- list(
    # `Study`, not `Define`. The importer that the open-source edition ships
    # makes this sheet its initialising one and therefore REQUIRED, so a
    # workbook naming it `Define` does not import at all -- the whole file
    # is refused before a row is read. The other edition reads both names.
    # One shape both editions accept beats two shapes that each work once.
    Study = .p21_study_sheet(spec@study, spec@standard),
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
    # `Description` beside `Label`: the older reader looks for the first and
    # the newer for the second, and an unknown column is ignored by both, so
    # one sheet satisfies each.
    ValueLevel = .p21_dual_label(
      .p21_sheet_frame(values, .p21_value_map, names(.spec_cols_values))
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
    # The WhereClauses sheet, and the ValueLevel cell holding an ID that
    # points into it. Measured against the importer's source: it treats
    # that cell as a foreign key and raises a reference error per row when
    # the sheet is absent, so writing the condition inline lost every
    # value-level row. artoo reads both shapes; it writes this one.
    WhereClauses = .p21_where_sheet(spec@where_clauses),
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
    `Analysis Results` = .p21_arm_result_sheet(spec@arm_results, clauses),
    `Analysis Criteria` = .p21_arm_criteria_sheet(spec@arm_results)
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


# Every slot that HAS a sheet, paired with the reader map that defines what
# that sheet can carry. One list, used by both the writer and the drop
# warning, so a map gaining a header teaches both at once.
#' @noRd
.p21_slot_maps <- list(
  datasets = list(.spec_cols_datasets, .p21_ds_map),
  variables = list(.spec_cols_variables, .p21_var_map),
  where_clauses = list(.spec_cols_where_clauses, .p21_where_map),
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
#
# `standard_id` survives through the Standard column's display strings: the
# writer emits each linked row's "name version" and the reader's
# .link_dataset_standards() resolves it against the round-tripped Standards
# sheet. That recovery holds only while every id in use resolves to a row
# whose display parses back unambiguously -- a blank name or version, a
# version containing a space (the parser takes the last token), or two
# standards sharing one display would each break it.
#' @noRd
.p21_recovered <- list(
  datasets = list(
    standard_id = function(df, spec) {
      std <- spec@standards
      ids <- trimws(as.character(df$standard_id))
      ids <- unique(ids[!is.na(ids) & nzchar(ids)])
      if (!length(ids)) {
        return(TRUE)
      }
      if (is.null(std) || !nrow(std)) {
        return(FALSE)
      }
      name <- trimws(as.character(std$name))
      version <- trimws(as.character(std$version))
      display <- paste(name, version)
      at <- match(ids, trimws(as.character(std$standard_id)))
      if (anyNA(at)) {
        return(FALSE)
      }
      all(
        !is.na(name[at]) &
          nzchar(name[at]) &
          !is.na(version[at]) &
          nzchar(version[at]) &
          !grepl("[[:space:]]", version[at]) &
          vapply(
            at,
            function(i) sum(display == display[[i]], na.rm = TRUE) == 1L,
            logical(1)
          )
      )
    }
  ),
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
  key <- paste(ar$display_id, ar$result_id, sep = "\r")
  first <- ar[!duplicated(key), , drop = FALSE]
  parts <- split(seq_len(nrow(ar)), factor(key, levels = unique(key)))
  # The per-dataset facts belong on the Analysis Criteria sheet, one row
  # each, so they are cleared here rather than collapsed onto the result.
  # Collapsing them wrote one result's variables qualified by another
  # dataset's name, and the reference then pointed at a variable that
  # dataset does not have.
  first$selection_criteria <- NA_character_
  first$dataset <- NA_character_
  first$variables <- NA_character_
  first$where_clause_id <- NA_character_
  .p21_sheet_frame(
    first,
    .p21_arm_result_map,
    c(names(.spec_cols_arm_results), "selection_criteria")
  )
}

# The Analysis Criteria sheet: one row per analysis dataset of a result.
#
# The result's datasets ride on their own sheet, keyed back by Display and
# Result, each naming its dataset, its variables and its where clause BY ID
# -- the same foreign key the ValueLevel cell uses. Packing them into one
# rendered cell instead loses every dataset after the first to a reader that
# has no such column.
#' @noRd
.p21_arm_criteria_sheet <- function(ar) {
  if (is.null(ar) || !nrow(ar) || !("dataset" %in% names(ar))) {
    return(NULL)
  }
  rows <- ar[!.dx_blank(as.character(ar$dataset)), , drop = FALSE]
  if (!nrow(rows)) {
    return(NULL)
  }
  out <- data.frame(
    display_id = as.character(rows$display_id),
    result_id = as.character(rows$result_id),
    dataset = as.character(rows$dataset),
    variables = .dx_chr(rows, "variables"),
    where_clause_id = .dx_chr(rows, "where_clause_id"),
    stringsAsFactors = FALSE
  )
  .p21_sheet_frame(out, .p21_arm_criteria_map, names(out))
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

# The WhereClauses sheet, as the TRUE INVERSE of .wc_from_sheet().
#
# The slot is one row per CheckValue; the sheet is one row per RangeCheck,
# with a set comparator's values in one cell. Projecting the slot row for row
# -- which is what the generic sheet builder does -- makes the reader see
# each value as its own RangeCheck, so `PARAMCD IN (ACITM01, ..., ACITM14)`
# came back as fourteen ANDed one-value checks and selected nothing.
#
# Values are joined the way .wc_split_values() parses them: comma-separated,
# and quoted when the value itself contains a comma, which is the whole
# reason that splitter is quote-aware.
#' @noRd
.p21_where_sheet <- function(wc, call = rlang::caller_env()) {
  if (is.null(wc) || !nrow(wc)) {
    return(NULL)
  }
  key <- paste(wc$where_clause_id, wc$check_order, sep = "\r")
  first <- !duplicated(key)
  # Quoting is COMPARATOR-AWARE. A quote only means anything in a set,
  # where a comma separates members; on a scalar the reader takes the cell
  # verbatim, so quoting an EQ value whose text happens to contain a comma
  # put the quote characters INTO the value. Silently, and on artoo's own
  # round trip.
  collapse <- function(values, comparator) {
    values <- as.character(values)
    values <- values[!is.na(values)]
    if (!length(values)) {
      return(NA_character_)
    }
    if (!(toupper(comparator) %in% .wc_set_comparators)) {
      return(values[[1L]])
    }
    if (any(grepl('"', values, fixed = TRUE))) {
      .artoo_abort(
        c(
          "A where-clause value contains a quote character.",
          "x" = "{.val {values[grepl('\"', values, fixed = TRUE)][[1]]}}.",
          "i" = "A set's values are comma separated and quote delimited, so a value cannot carry one. Write the clause to {.val .json} instead."
        ),
        kind = "spec",
        call = call
      )
    }
    quoted <- ifelse(
      grepl(",", values, fixed = TRUE),
      paste0('"', values, '"'),
      values
    )
    if (length(quoted) == 1L) {
      quoted
    } else {
      paste0("(", paste(quoted, collapse = ", "), ")")
    }
  }
  # Ordered NUMERICALLY on both counters, not by the composite string key:
  # a clause with ten or more range checks sorts "10" before "2" as text, and
  # the sheet's row order is the only place the reader can recover
  # check_order from.
  ordered <- order(
    wc$where_clause_id,
    suppressWarnings(as.integer(wc$check_order)),
    suppressWarnings(as.integer(wc$value_order))
  )
  wc <- wc[ordered, , drop = FALSE]
  key <- key[ordered]
  first <- !duplicated(key)
  out <- wc[first, , drop = FALSE]
  comparators <- split(
    as.character(wc$comparator),
    factor(key, levels = unique(key))
  )
  out$value <- vapply(
    seq_along(comparators),
    function(k) {
      group <- split(wc$value, factor(key, levels = unique(key)))[[k]]
      collapse(group, comparators[[k]][[1L]])
    },
    character(1)
  )
  .p21_sheet_frame(out, .p21_where_map, names(.spec_cols_where_clauses))
}

# Carry a label under both spellings.
#
# The two workbook generations disagree on the header: the older sheet says
# `Description`, the newer says `Label`. Both readers ignore a column they
# do not know, so emitting both is what makes one file readable by each --
# and it costs a duplicated column rather than a choice between them.
#' @noRd
.p21_dual_label <- function(df) {
  if (is.null(df) || !nrow(df) || !("Label" %in% names(df))) {
    return(df)
  }
  # Only when the sheet does not already carry one: a `Description` here is
  # a user's own foreign column that rode through the read, and clobbering
  # it with the label destroys the one copy of their text.
  if (!("Description" %in% names(df))) {
    df$Description <- df[["Label"]]
  }
  df
}

# The Standard cell for each dataset row: the display string ("SDTMIG 3.2")
# of the standards row its `standard_id` names, or NA when the id is blank,
# unresolvable, or the row it names has no name/version to display. The
# reader's .link_dataset_standards() parses exactly this shape back.
#' @noRd
.p21_dataset_standard <- function(datasets, standards) {
  blank <- rep(NA_character_, nrow(datasets))
  if (
    !("standard_id" %in% names(datasets)) ||
      is.null(standards) ||
      !nrow(standards)
  ) {
    return(blank)
  }
  at <- match(
    trimws(as.character(datasets$standard_id)),
    trimws(as.character(standards$standard_id))
  )
  name <- trimws(as.character(standards$name))[at]
  version <- trimws(as.character(standards$version))[at]
  ok <- !is.na(at) &
    !is.na(name) &
    nzchar(name) &
    !is.na(version) &
    nzchar(version)
  out <- blank
  out[ok] <- paste(name[ok], version[ok])
  out
}
