# define_data.R — let the data the define describes inform what it says.
#
# artoo can read the .xpt / .json / .parquet files a define.xml describes,
# which a spec-only tool cannot, so the Define-XML writer optionally consults
# them. Four things the data knows and a spec author usually does not:
#
#   * the real maximum byte width of a character column
#   * the type a value-level row takes when the spec leaves it blank
#   * which values a findings result actually takes, and so what its
#     value-level metadata should say
#   * whether a dataset has any records at all
#
# OPT-IN, and it never contradicts the spec silently. A stated Length is
# widened when the data overflows it, because a Length below the real maximum
# is a conformance finding, and the document
# would be wrong; it is never NARROWED, because a spec that declares 200 for
# a column whose current extract reaches 12 is making a claim about the
# domain, not about this extract, and one snapshot of data is no reason to
# overwrite it. Both directions are reported.

# The value-level shapes worth deriving, and the key each is keyed by.
#
# `prefix` rules pair a key with results sharing its domain prefix, so LBTESTCD
# keys LBORRES and VSTESTCD keys VSORRES without either being named here.
# `exact` rules name both sides, because their key and value share no stem.
#
# Grounded in the SDTM and ADaM implementation guides' own conventions; this
# is the metadata a define author writes out by hand, one row per test code,
# and the reason value-level metadata is the most tedious part of the job.
#' @noRd
.dx_vlm_rules <- list(
  list(
    kind = "prefix",
    key = "TESTCD",
    values = c("ORRES", "ORRESU", "STRESC", "STRESN", "STRESU")
  ),
  list(
    kind = "exact",
    key = "TSPARMCD",
    values = c("TSVAL", "TSVALNF", "TSVALCD")
  ),
  list(kind = "exact", key = "QNAM", values = "QVAL"),
  list(kind = "exact", key = "PARAMCD", values = c("AVAL", "AVALC"))
)

# How many distinct key values artoo will derive value-level metadata for
# before it stops and says so. A findings domain with hundreds of test codes
# would otherwise produce hundreds of def:ValueListDefs nobody asked for.
#' @noRd
.dx_vlm_limit <- 200L

# Validate the `data` argument and reduce it to the datasets the spec names.
#' @noRd
.dx_check_data <- function(data, spec, call = rlang::caller_env()) {
  if (is.null(data)) {
    return(NULL)
  }
  # A data frame is a named list, so it reaches the element check below and
  # is refused there for a column not being a data frame. Catch it here and
  # say what was actually passed.
  if (is.data.frame(data)) {
    .artoo_abort(
      c(
        "{.arg data} must be a named list of data frames.",
        "x" = "You supplied a bare data frame.",
        "i" = "Name it for the dataset it holds, as {.code list(DM = dm)}."
      ),
      kind = "input",
      call = call
    )
  }
  if (!is.list(data) || !length(names(data)) || anyNA(names(data))) {
    .artoo_abort(
      c(
        "{.arg data} must be a named list of data frames.",
        "x" = "You supplied {.obj_type_friendly {data}}.",
        "i" = "Name each element for the dataset it holds, as {.code list(DM = dm, AE = ae)}."
      ),
      kind = "input",
      call = call
    )
  }
  frames <- vapply(data, is.data.frame, logical(1))
  if (!all(frames)) {
    bad <- names(data)[!frames]
    .artoo_abort(
      c(
        "Every element of {.arg data} must be a data frame.",
        "x" = "{.val {bad}} {?is/are} not."
      ),
      kind = "input",
      call = call
    )
  }
  unknown <- setdiff(names(data), as.character(spec@datasets$dataset))
  if (length(unknown)) {
    # Not fatal: a study directory holds datasets a partial spec does not
    # describe. Saying so beats ignoring them, because the likelier cause is
    # a name that does not match.
    .artoo_warn(
      c(
        "{length(unknown)} dataset{?s} in {.arg data} {?is/are} not in the spec.",
        "x" = "{.val {unknown}}.",
        "i" = "Only datasets the spec describes inform the define."
      ),
      kind = "spec",
      call = call
    )
  }
  data[intersect(names(data), as.character(spec@datasets$dataset))]
}

# The whole data-aware pass, in order. Each step returns a spec, so the
# writer downstream cannot tell a data-informed spec from a hand-written one.
#' @noRd
.dx_apply_data <- function(spec, data, p, call = rlang::caller_env()) {
  data <- .dx_check_data(data, spec, call)
  if (is.null(data) || !length(data)) {
    return(spec)
  }
  spec <- .dx_data_lengths(spec, data, call)
  spec <- .dx_derive_vlm(spec, data, call)
  spec <- .dx_data_values(spec, data, call)
  spec <- .dx_data_no_data(spec, data, p, call)
  spec
}

# ---- derived value-level metadata -----------------------------------------

# The (key, value) variable pairs a dataset's own columns imply.
#
# Derived from the names rather than from a table of domains: a variable
# ending in TESTCD keys the results sharing its prefix, so LB and VS and a
# sponsor's custom findings domain all work without being enumerated.
#' @noRd
.dx_vlm_pairs <- function(columns) {
  pairs <- list()
  for (rule in .dx_vlm_rules) {
    keys <- if (identical(rule$kind, "prefix")) {
      grep(paste0(rule$key, "$"), columns, value = TRUE)
    } else {
      intersect(rule$key, columns)
    }
    for (key in keys) {
      stem <- if (identical(rule$kind, "prefix")) {
        sub(paste0(rule$key, "$"), "", key)
      } else {
        ""
      }
      for (value in intersect(paste0(stem, rule$values), columns)) {
        if (identical(value, key)) {
          next
        }
        pairs[[length(pairs) + 1L]] <- c(key = key, value = value)
      }
    }
  }
  pairs
}

# Derive value-level metadata from what the data actually contains.
#
# This is the most tedious part of authoring a define by hand -- one row per
# test code, per result variable -- and the part the prior art got wrong. Two
# rules keep it honest:
#
#   * NEVER overwrite. A variable the spec already gives value-level rows to
#     is left exactly as the author wrote it.
#   * Refuse to guess at scale. A findings domain with hundreds of test codes
#     would otherwise produce hundreds of def:ValueListDefs nobody asked for,
#     so past a limit artoo stops and says which variable it stopped on.
#' @noRd
.dx_derive_vlm <- function(spec, data, call = rlang::caller_env()) {
  var <- spec@variables
  existing <- spec@values
  described <- if (is.null(existing) || !nrow(existing)) {
    character(0)
  } else {
    .dx_key(existing$dataset, existing$variable)
  }
  value_rows <- list()
  clause_rows <- list()
  crowded <- character(0)

  for (dataset in names(data)) {
    frame <- data[[dataset]]
    own <- as.character(var$variable[as.character(var$dataset) == dataset])
    columns <- intersect(own, names(frame))
    for (pair in .dx_vlm_pairs(columns)) {
      key <- unname(pair[["key"]])
      value <- unname(pair[["value"]])
      if (.dx_key(dataset, value) %in% described) {
        next
      }
      levels <- unique(as.character(frame[[key]]))
      levels <- levels[!is.na(levels) & nzchar(trimws(levels))]
      if (!length(levels)) {
        next
      }
      if (length(levels) > .dx_vlm_limit) {
        crowded <- c(crowded, paste0(dataset, ".", value))
        next
      }
      for (level in levels) {
        rows <- which(as.character(frame[[key]]) == level)
        id <- sprintf("WC.%s.%s.%s", dataset, value, .dx_slug(level))
        value_rows[[length(value_rows) + 1L]] <- data.frame(
          dataset = dataset,
          variable = value,
          where_clause_id = id,
          data_type = .dx_infer_type(frame[[value]][rows]),
          length = .dx_data_width(frame[[value]][rows]),
          order = length(value_rows) + 1L,
          stringsAsFactors = FALSE
        )
        clause_rows[[length(clause_rows) + 1L]] <- data.frame(
          where_clause_id = id,
          check_order = 1L,
          dataset = dataset,
          variable = key,
          comparator = "EQ",
          soft_hard = "Soft",
          value = level,
          value_order = 1L,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(crowded)) {
    limit <- .dx_vlm_limit
    .artoo_warn(
      c(
        "{length(crowded)} variable{?s} take{?s/} more than {limit} distinct values.",
        "x" = "{.val {crowded}}: no value-level metadata derived.",
        "i" = "Write the rows you want by hand, or narrow the data first."
      ),
      kind = "spec",
      call = call
    )
  }
  if (!length(value_rows)) {
    return(spec)
  }
  # Through the slot schemas: set_props() re-runs the S7 validator but not the
  # constructor's coercion, so a frame built from only the columns this
  # function fills would reach the writer missing the rest.
  derived <- .coerce_slot(
    do.call(rbind, value_rows),
    .spec_cols_values,
    .spec_req_values,
    "values",
    call
  )
  clauses <- .coerce_slot(
    do.call(rbind, clause_rows),
    .spec_cols_where_clauses,
    .spec_req_where_clauses,
    "where_clauses",
    call
  )
  S7::set_props(
    spec,
    values = .dx_stack(existing, derived),
    where_clauses = .dx_stack(spec@where_clauses, clauses)
  )
}

# Stack two frames that need not share columns.
#
# The constructor deliberately preserves columns artoo does not model, so a
# spec read from a workbook with an extra header reaches here with one --
# and indexing the derived rows by the existing names then failed with a bare
# "undefined columns selected" in the middle of a write.
#' @noRd
.dx_stack <- function(existing, derived) {
  if (is.null(existing) || !nrow(existing)) {
    return(derived)
  }
  for (column in setdiff(names(existing), names(derived))) {
    derived[[column]] <- existing[[column]][NA_integer_]
  }
  for (column in setdiff(names(derived), names(existing))) {
    existing[[column]] <- derived[[column]][NA_integer_]
  }
  rbind(existing, derived[names(existing)])
}

# ---- lengths --------------------------------------------------------------

# The types a Define-XML Length does not apply to.
.dx_untimed_types <- c("date", "datetime", "time")

# The real maximum byte width of a character column, or NA for anything else.
# Bytes, not characters: a Define-XML Length is a byte width, and counting
# characters undercounts a multi-byte value into a truncating declaration.
#' @noRd
.dx_data_width <- function(col) {
  if (!is.character(col) && !is.factor(col)) {
    return(NA_integer_)
  }
  values <- as.character(col)
  values <- values[!is.na(values)]
  if (!length(values)) {
    return(NA_integer_)
  }
  as.integer(max(nchar(values, type = "bytes")))
}

# Carry a widened length across every row that shares its ItemDef OID.
#
# Define-XML allows one ItemDef per OID, and artoo pools them -- the bundled
# SDTM spec gives STUDYID a single `IT.STUDYID` across four datasets. Widening
# is measured per dataset, so supplying data for SOME of them (the natural
# call: you pass what is on disk) left one OID defined two ways and aborted,
# blaming the author for a state this pass had just created. The widest
# measurement wins for the whole group, which is what a shared definition
# means.
#
# Only groups this pass actually touched are pooled. Two rows that shared an
# OID and disagreed BEFORE any data arrived are the author's conflict to
# resolve, and still abort with their own message.
#' @noRd
.dx_pool_lengths <- function(
  spec,
  lengths,
  touched,
  call = rlang::caller_env()
) {
  if (!any(touched)) {
    return(lengths)
  }
  oids <- .dx_oids(spec, call)$variable
  if (length(oids) != length(lengths)) {
    return(lengths)
  }
  for (oid in unique(oids[touched])) {
    rows <- which(oids == oid)
    if (length(rows) < 2L) {
      next
    }
    widest <- suppressWarnings(max(lengths[rows], na.rm = TRUE))
    if (is.finite(widest)) {
      lengths[rows] <- as.integer(widest)
    }
  }
  lengths
}

#' @noRd
.dx_data_lengths <- function(spec, data, call = rlang::caller_env()) {
  var <- spec@variables
  if (!nrow(var)) {
    return(spec)
  }
  lengths <- as.integer(.dx_chr(var, "length"))
  touched <- rep(FALSE, nrow(var))
  filled <- character(0)
  widened <- character(0)
  narrower <- character(0)
  for (i in seq_len(nrow(var))) {
    frame <- data[[as.character(var$dataset[[i]])]]
    if (is.null(frame)) {
      next
    }
    column <- as.character(var$variable[[i]])
    if (!(column %in% names(frame))) {
      next
    }
    if (.dx_chr(var, "data_type")[[i]] %in% .dx_untimed_types) {
      # A Define-XML Length applies to text, integer and float. The official
      # examples carry none on a date-typed item, and P21 flags one.
      next
    }
    width <- .dx_data_width(frame[[column]])
    if (is.na(width)) {
      next
    }
    where <- paste0(var$dataset[[i]], ".", column)
    if (is.na(lengths[[i]])) {
      lengths[[i]] <- width
      touched[[i]] <- TRUE
      filled <- c(filled, where)
    } else if (width > lengths[[i]]) {
      lengths[[i]] <- width
      touched[[i]] <- TRUE
      widened <- c(widened, where)
    } else if (width < lengths[[i]]) {
      narrower <- c(narrower, where)
    }
  }
  if (length(widened)) {
    .artoo_warn(
      c(
        "{length(widened)} declared length{?s} {?is/are} shorter than the data.",
        "x" = "{.val {widened}}: widened to the real maximum.",
        "i" = "A length below the real maximum is a conformance finding, so the data wins."
      ),
      kind = "spec",
      call = call
    )
  }
  if (length(narrower)) {
    .artoo_inform(
      c(
        "{length(narrower)} declared length{?s} {?is/are} longer than this data.",
        "i" = "Left as declared: a length is a claim about the domain, not about one extract."
      ),
      kind = "spec"
    )
  }
  if (!length(filled) && !length(widened)) {
    return(spec)
  }
  var$length <- .dx_pool_lengths(spec, lengths, touched, call)
  S7::set_props(spec, variables = var)
}

# ---- value-level types ----------------------------------------------------

# Fill a value-level row's type from the data when the spec leaves it blank
# AND the row's where clause pins it to one key value. A variable-level type
# is never touched: artoo_spec() already refuses a blank one.
#' @noRd
.dx_data_values <- function(spec, data, call = rlang::caller_env()) {
  val <- spec@values
  if (
    is.null(val) || !nrow(val) || !any(.dx_blank(.dx_chr(val, "data_type")))
  ) {
    return(spec)
  }
  types <- .dx_chr(val, "data_type")
  clauses <- spec@where_clauses
  for (i in which(.dx_blank(types))) {
    frame <- data[[as.character(val$dataset[[i]])]]
    column <- as.character(val$variable[[i]])
    if (is.null(frame) || !(column %in% names(frame))) {
      next
    }
    subset <- .dx_data_subset(
      frame,
      clauses,
      .dx_chr(val, "where_clause_id")[[i]]
    )
    if (is.null(subset) || !length(subset)) {
      next
    }
    types[[i]] <- .dx_infer_type(frame[[column]][subset])
  }
  if (identical(types, .dx_chr(val, "data_type"))) {
    return(spec)
  }
  val$data_type <- types
  S7::set_props(spec, values = val)
}

# The rows a single-condition equality where clause selects. NULL for
# anything more involved: guessing which rows a compound condition covers is
# how a derived type ends up describing the wrong values.
#' @noRd
.dx_data_subset <- function(frame, clauses, where_clause_id) {
  if (.dx_blank(where_clause_id) || !nrow(clauses)) {
    return(NULL)
  }
  rows <- clauses[
    as.character(clauses$where_clause_id) == trimws(where_clause_id),
    ,
    drop = FALSE
  ]
  if (
    nrow(rows) != 1L || !identical(.dx_one(.dx_chr(rows, "comparator")), "EQ")
  ) {
    return(NULL)
  }
  key <- .dx_one(.dx_chr(rows, "variable"))
  value <- .dx_one(.dx_chr(rows, "value"))
  if (.dx_blank(key) || !(key %in% names(frame))) {
    return(NULL)
  }
  which(as.character(frame[[key]]) == value)
}

# The CDISC dataType a column of real values takes.
#' @noRd
.dx_infer_type <- function(col) {
  values <- col[!is.na(col)]
  if (!length(values)) {
    return(NA_character_)
  }
  if (is.numeric(values)) {
    return(if (all(values == trunc(values))) "integer" else "float")
  }
  # From the LEXICAL form, not the parse. "1.0" parses to a whole number but
  # xs:integer has no decimal point in its lexical space, so typing it
  # integer makes the data disagree with the define it describes.
  text <- trimws(as.character(values))
  if (all(grepl("^[+-]?[0-9]+$", text))) {
    return("integer")
  }
  if (
    all(grepl("^[+-]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?$", text))
  ) {
    return("float")
  }
  "text"
}

# ---- empty datasets -------------------------------------------------------

# def:HasNoData on an ItemGroupDef whose dataset has no records.
#
# 2.1 only, and a conformance check requires a def:CommentOID alongside it --
# a dataset that is empty needs an explanation, and artoo will not write one.
# A dataset with no comment is therefore left unflagged, and said so.
#' @noRd
.dx_data_no_data <- function(spec, data, p, call = rlang::caller_env()) {
  if (!("def:HasNoData" %in% p$def_attrs$ItemGroupDef)) {
    return(spec)
  }
  ds <- spec@datasets
  if (!nrow(ds)) {
    return(spec)
  }
  flags <- .dx_lgl(ds, "has_no_data")
  comments <- .dx_chr(ds, "comment_id")
  flagged <- character(0)
  uncommented <- character(0)
  contradicted <- character(0)
  for (i in seq_len(nrow(ds))) {
    frame <- data[[as.character(ds$dataset[[i]])]]
    if (is.null(frame)) {
      next
    }
    if (nrow(frame) > 0L) {
      if (isTRUE(flags[[i]])) {
        contradicted <- c(contradicted, as.character(ds$dataset[[i]]))
      }
      next
    }
    if (.dx_blank(comments[[i]])) {
      uncommented <- c(uncommented, as.character(ds$dataset[[i]]))
      next
    }
    flags[[i]] <- TRUE
    flagged <- c(flagged, as.character(ds$dataset[[i]]))
  }
  if (length(contradicted)) {
    .artoo_warn(
      c(
        "{length(contradicted)} dataset{?s} {?is/are} flagged as having no data, but the data has rows.",
        "x" = "{.val {contradicted}}.",
        "i" = "The flag is left as the spec set it; a conformance run cross-checks it against the data."
      ),
      kind = "spec",
      call = call
    )
  }
  if (length(uncommented)) {
    .artoo_warn(
      c(
        "{length(uncommented)} dataset{?s} {?has/have} no records and no comment.",
        "x" = "{.val {uncommented}}: left unflagged.",
        "i" = "{.code def:HasNoData} needs a {.code def:CommentOID} explaining the absence; set {.code comment_id}."
      ),
      kind = "spec",
      call = call
    )
  }
  if (!length(flagged)) {
    return(spec)
  }
  ds$has_no_data <- flags
  S7::set_props(spec, datasets = ds)
}
