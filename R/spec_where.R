# spec_where.R — where-clause conditions, from a workbook or from free text.
#
# A where clause selects the rows a value-level definition applies to. In
# Define-XML it is a def:WhereClauseDef holding one or more RangeChecks, and
# the RangeChecks within one clause are combined with AND.
#
# Two source shapes exist in the wild and artoo reads both:
#
#   * TABULAR (the current Pinnacle 21 workbook): a WhereClauses sheet with
#     one row per range check -- ID, Dataset, Variable, Comparator, Value --
#     and rows sharing an ID forming one multi-condition clause. There is no
#     expression to parse; the grouping IS the AND.
#   * FREE TEXT (older workbooks, and the rendered form artoo's own reader
#     produces): "VSTESTCD EQ (HEIGHT) AND COUNTRY IN (CAN, MEX)".
#
# The free-text path is a deliberately RESTRICTED grammar, not a general
# expression parser. It exists to read what tools actually emit, and it
# refuses anything else loudly rather than guessing -- a mis-parsed where
# clause silently changes which rows a definition applies to, which is worse
# than a failed read.

# Split a value cell for a set comparator.
#
# Rules, in order: strip one balanced outer paren pair; split on commas that
# sit OUTSIDE double quotes; trim; strip one surrounding quote pair per value.
# Quoting is what lets a value contain a comma -- the CDISC examples carry
# "LOCAL LAB" -- so a naive strsplit on "," corrupts real data.
#
# Non-set comparators keep the cell verbatim: an EQ against a value that
# happens to contain a comma is one value, not two.
# `strip_parens` is TRUE only on the free-text path, where the rendered form
# parenthesises EVERY value including a scalar -- "VSTESTCD EQ (HEIGHT)". A
# parser that strips parens only for IN, as the prior art did, emits
# "(HEIGHT)" as the check value and corrupts every scalar comparison in the
# document. On the tabular path parens are left alone, because a value there
# may legitimately contain them.
#' @noRd
.wc_split_values <- function(value, comparator, strip_parens = FALSE) {
  value <- if (is.na(value)) "" else as.character(value)
  is_set <- toupper(comparator) %in% .wc_set_comparators
  if (!is_set && !strip_parens) {
    return(value)
  }
  v <- trimws(value)
  if (startsWith(v, "(") && endsWith(v, ")")) {
    v <- substr(v, 2L, nchar(v) - 1L)
  }
  if (!is_set) {
    return(trimws(v))
  }
  parts <- .wc_split_outside_quotes(v)
  parts <- trimws(parts)
  parts <- vapply(
    parts,
    function(x) {
      if (nchar(x) >= 2L && startsWith(x, "\"") && endsWith(x, "\"")) {
        substr(x, 2L, nchar(x) - 1L)
      } else {
        x
      }
    },
    character(1),
    USE.NAMES = FALSE
  )
  parts[nzchar(parts) | length(parts) == 1L]
}

# Split on commas not inside a double-quoted run.
#' @noRd
.wc_split_outside_quotes <- function(x) {
  if (!nzchar(x)) {
    return("")
  }
  chars <- strsplit(x, "", fixed = TRUE)[[1]]
  inq <- FALSE
  out <- character(0)
  buf <- character(0)
  for (ch in chars) {
    if (ch == "\"") {
      inq <- !inq
      buf <- c(buf, ch)
    } else if (ch == "," && !inq) {
      out <- c(out, paste(buf, collapse = ""))
      buf <- character(0)
    } else {
      buf <- c(buf, ch)
    }
  }
  c(out, paste(buf, collapse = ""))
}

# Build where_clauses rows from a tabular WhereClauses sheet.
#
# Rows sharing an ID become one clause. `check_order` is assigned in sheet
# order, which is the only ordering information the source carries.
#' @noRd
.wc_from_sheet <- function(df, call = rlang::caller_env()) {
  if (is.null(df) || !nrow(df)) {
    return(NULL)
  }
  need <- c("where_clause_id", "dataset", "variable", "comparator")
  miss <- setdiff(need, names(df))
  if (length(miss)) {
    .artoo_abort(
      c(
        "The WhereClauses sheet is missing required column{?s}: {.val {miss}}.",
        "i" = "Expected {.val {c('ID', 'Dataset', 'Variable', 'Comparator', 'Value')}}."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  if (!"value" %in% names(df)) {
    df$value <- NA_character_
  }
  if (!"comment_id" %in% names(df)) {
    df$comment_id <- NA_character_
  }

  rows <- list()
  # An environment, not a named vector: `seen[[id]]` on a name that is not
  # present throws rather than returning NULL, and the ids here come straight
  # from the sheet. This is the same trap that once crashed define_lint().
  seen <- new.env(parent = emptyenv())
  for (i in seq_len(nrow(df))) {
    id <- as.character(df$where_clause_id[[i]])
    cmp <- .wc_check_comparator(df$comparator[[i]], id, call)
    n <- (seen[[id]] %||% 0L) + 1L
    assign(id, n, envir = seen)
    vals <- .wc_split_values(df$value[[i]], cmp)
    rows[[length(rows) + 1L]] <- data.frame(
      where_clause_id = id,
      check_order = n,
      dataset = as.character(df$dataset[[i]]),
      variable = as.character(df$variable[[i]]),
      itemoid = NA_character_,
      comparator = cmp,
      # Define-XML constrains a value-level where clause to SoftHard="Soft";
      # the sheet has no column for it, so it is supplied rather than guessed.
      soft_hard = "Soft",
      value = vals,
      value_order = seq_along(vals),
      comment_id = as.character(df$comment_id[[i]]),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

#' @noRd
.wc_check_comparator <- function(x, id, call = rlang::caller_env()) {
  cmp <- toupper(trimws(as.character(x)))
  if (is.na(cmp) || !nzchar(cmp)) {
    # Bind to a local first: cli parses `{.val {.wc_comparators}}` as an
    # inline style named ".wc_comparators", because the interpolated
    # expression starts with a dot.
    known <- .wc_comparators
    .artoo_abort(
      c(
        "Where clause {.val {id}} has no comparator.",
        "i" = "Use one of {.val {known}}."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  if (!cmp %in% .wc_comparators) {
    known <- .wc_comparators
    .artoo_abort(
      c(
        "Where clause {.val {id}} uses an unknown comparator {.val {cmp}}.",
        "i" = "Define-XML allows {.val {known}}."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  cmp
}

# Parse a free-text where clause into rows.
#
# Accepted grammar, and nothing else:
#
#   clause    := condition ( "AND" condition )*
#   condition := VARIABLE COMPARATOR value
#   value     := "(" item ("," item)* ")" | bareword
#
# OR is deliberately NOT accepted as a conjunction. Define-XML combines the
# RangeChecks in a clause with AND and offers no disjunction, so an OR has to
# be rewritten or refused:
#
#   * SAME variable on both sides -- "SEX EQ (F) OR SEX EQ (M)" -- is exactly
#     what IN means, and is rewritten to "SEX IN (F, M)".
#   * DIFFERENT variables cannot be expressed at all, and is refused rather
#     than silently narrowed to an AND, which would change which rows the
#     definition applies to.
#' @noRd
.wc_parse_text <- function(text, id, call = rlang::caller_env()) {
  if (is.na(text) || !nzchar(trimws(text))) {
    return(NULL)
  }
  parts <- .wc_split_conjunctions(text)
  conditions <- lapply(
    parts$conditions,
    .wc_parse_condition,
    id = id,
    call = call
  )
  conditions <- Filter(Negate(is.null), conditions)
  if (!length(conditions)) {
    return(NULL)
  }
  if (parts$has_or) {
    conditions <- .wc_fold_or(conditions, id, call)
  }
  rows <- list()
  for (k in seq_along(conditions)) {
    cond <- conditions[[k]]
    rows[[length(rows) + 1L]] <- data.frame(
      where_clause_id = id,
      check_order = k,
      dataset = NA_character_,
      variable = cond$variable,
      itemoid = NA_character_,
      comparator = cond$comparator,
      soft_hard = "Soft",
      value = cond$values,
      value_order = seq_along(cond$values),
      comment_id = NA_character_,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

# Split on AND / OR at the top level, reporting whether any OR was present.
#' @noRd
.wc_split_conjunctions <- function(text) {
  pieces <- strsplit(text, "\\s+(?i:AND|OR)\\s+", perl = TRUE)[[1]]
  has_or <- grepl("\\s+(?i:OR)\\s+", text, perl = TRUE)
  list(conditions = trimws(pieces), has_or = has_or)
}

#' @noRd
.wc_parse_condition <- function(txt, id, call = rlang::caller_env()) {
  txt <- trimws(txt)
  if (!nzchar(txt)) {
    return(NULL)
  }
  m <- regmatches(
    txt,
    regexec("^(\\S+)\\s+(\\S+)\\s+(.*)$", txt, perl = TRUE)
  )[[1]]
  if (length(m) != 4L) {
    .artoo_abort(
      c(
        "Cannot read the where clause {.val {id}}.",
        "x" = "{.val {txt}} is not {.code VARIABLE COMPARATOR value}.",
        "i" = "Supply a WhereClauses sheet instead, which needs no parsing."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  cmp <- .wc_check_comparator(m[[3]], id, call)
  list(
    variable = m[[2]],
    comparator = cmp,
    values = .wc_split_values(m[[4]], cmp, strip_parens = TRUE)
  )
}

# Rewrite a disjunction, or refuse it.
#' @noRd
.wc_fold_or <- function(conditions, id, call = rlang::caller_env()) {
  vars <- vapply(conditions, function(c) c$variable, character(1))
  if (length(unique(vars)) > 1L) {
    .artoo_abort(
      c(
        "Where clause {.val {id}} combines different variables with OR.",
        "x" = "Define-XML combines the checks in a where clause with AND, so a disjunction across {.val {unique(vars)}} cannot be expressed.",
        "i" = "Split it into separate value-level rows, one per condition."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  # One variable on both sides: that is what IN means.
  list(list(
    variable = vars[[1]],
    comparator = "IN",
    values = unique(unlist(lapply(conditions, function(c) c$values)))
  ))
}
