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
# document. On the tabular path a SCALAR value keeps its parentheses, since a
# value there may legitimately contain them; a set value is still unwrapped,
# because "(A, B)" is how workbooks write a list.
# Strip one balanced pair of double quotes. The pair delimits a value that
# contains a space or a comma; the value itself never carries them.
#' @noRd
.wc_unquote <- function(x) {
  if (nchar(x) >= 2L && startsWith(x, "\"") && endsWith(x, "\"")) {
    substr(x, 2L, nchar(x) - 1L)
  } else {
    x
  }
}

#' @noRd
.wc_split_values <- function(
  value,
  comparator,
  strip_parens = FALSE,
  id = NA_character_,
  call = rlang::caller_env()
) {
  value <- if (is.na(value)) "" else as.character(value)
  is_set <- toupper(comparator) %in% .wc_set_comparators
  if (!is_set && !strip_parens) {
    return(value)
  }
  v <- trimws(value)
  # Strip only a BALANCED outer pair. "(1), (2)" opens and closes without the
  # first paren matching the last, and blindly trimming both ends yields the
  # values "1)" and "(2" -- a silent corruption rather than a refusal.
  if (.wc_balanced_parens(v)) {
    v <- trimws(substr(v, 2L, nchar(v) - 1L))
  }
  if (!is_set) {
    # A quote pair DELIMITS a value containing spaces, it is not part of the
    # value: the workbook format documents `AVISIT EQ "Week 24"`. The set
    # path has always stripped these; the scalar path kept them, so the
    # CheckValue read "\"Week 24\"" and the slice matched no record.
    return(.wc_unquote(v))
  }
  if (.wc_unbalanced_quotes(v)) {
    .artoo_abort(
      c(
        "Where clause {.val {id}} has an unbalanced quote in its value list.",
        "x" = "{.val {value}}",
        "i" = "Quote a value only to protect a comma inside it."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  parts <- .wc_split_outside_quotes(v)
  parts <- trimws(parts)
  parts <- vapply(parts, .wc_unquote, character(1), USE.NAMES = FALSE)
  kept <- parts[nzchar(parts)]
  if (anyDuplicated(kept)) {
    dup <- unique(kept[duplicated(kept)])
    .artoo_warn(
      c(
        "Where clause {.val {id}} lists {.val {dup}} more than once.",
        "i" = "Repeated values are kept once; check the source for a typo."
      ),
      kind = "spec",
      call = call
    )
    kept <- unique(kept)
  }
  if (!length(kept)) {
    # An empty list is not "matches nothing" in Define-XML, it is a malformed
    # RangeCheck. Every comparator in the closed enumeration takes an operand.
    .artoo_abort(
      c(
        "Where clause {.val {id}} has an empty value list.",
        "x" = "{.val {value}}",
        "i" = "Every Define-XML comparator takes at least one value."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  kept
}

# TRUE when the string opens with "(" and that very paren is closed by the
# final character, rather than merely starting and ending with parens.
#' @noRd
.wc_balanced_parens <- function(x) {
  if (nchar(x) < 2L || !startsWith(x, "(") || !endsWith(x, ")")) {
    return(FALSE)
  }
  chars <- strsplit(x, "", fixed = TRUE)[[1]]
  depth <- 0L
  for (i in seq_along(chars)) {
    if (chars[[i]] == "(") {
      depth <- depth + 1L
    } else if (chars[[i]] == ")") {
      depth <- depth - 1L
      if (depth == 0L) {
        return(i == length(chars))
      }
    }
  }
  FALSE
}

#' @noRd
.wc_unbalanced_quotes <- function(x) {
  sum(strsplit(x, "", fixed = TRUE)[[1]] == "\"") %% 2L != 0L
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
  # from the sheet. This is the same trap that once crashed lint_define().
  seen <- new.env(parent = emptyenv())
  for (i in seq_len(nrow(df))) {
    id <- as.character(df$where_clause_id[[i]])
    if (is.na(id) || !nzchar(trimws(id))) {
      # Rows with no id would all group under one key and weld unrelated
      # conditions into a single AND clause.
      .artoo_abort(
        c(
          "The WhereClauses sheet has a row with no ID (row {i}).",
          "i" = "Every range check must name the where clause it belongs to."
        ),
        kind = "p21_sheet",
        call = call
      )
    }
    cmp <- .wc_check_comparator(df$comparator[[i]], id, call)
    n <- (seen[[id]] %||% 0L) + 1L
    assign(id, n, envir = seen)
    vals <- .wc_split_values(df$value[[i]], cmp, id = id, call = call)
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
    conditions <- .wc_fold_or(conditions, id, parts$has_and, call)
  }
  rows <- list()
  for (k in seq_along(conditions)) {
    cond <- conditions[[k]]
    # A check on a variable in ANOTHER dataset qualifies it -- a VS value
    # conditioned on DM.COUNTRY. Unqualified names belong to the dataset
    # that owns the clause, and the caller fills that in.
    qualified <- regmatches(
      cond$variable,
      regexec("^([A-Za-z_][A-Za-z0-9_]*)[.](.+)$", cond$variable)
    )[[1L]]
    owner <- if (length(qualified) == 3L) qualified[[2L]] else NA_character_
    name <- if (length(qualified) == 3L) qualified[[3L]] else cond$variable
    rows[[length(rows) + 1L]] <- data.frame(
      where_clause_id = id,
      check_order = k,
      dataset = owner,
      variable = name,
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

# Split on AND / OR at the top level, reporting which conjunctions appeared.
# Both are needed: a clause mixing them is ambiguous without precedence rules
# Define-XML does not define, so it is refused rather than guessed at.
#' @noRd
.wc_split_conjunctions <- function(text) {
  pieces <- strsplit(text, "\\s+(?i:AND|OR)\\s+", perl = TRUE)[[1]]
  list(
    conditions = trimws(pieces),
    has_or = grepl("\\s+(?i:OR)\\s+", text, perl = TRUE),
    has_and = grepl("\\s+(?i:AND)\\s+", text, perl = TRUE)
  )
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
    values = .wc_split_values(
      m[[4]],
      cmp,
      strip_parens = TRUE,
      id = id,
      call = call
    )
  )
}

# Rewrite a disjunction, or refuse it.
#
# Only ONE rewrite is sound: several equality tests on the same variable are
# exactly what IN means. Everything else changes the meaning, so it is
# refused:
#
#   SEX EQ (F) OR SEX NE (M)        would become SEX IN (F, M) -- wrong, the
#                                   second leg admits every value but M.
#   AGE LT (5) OR AGE GT (10)       would become AGE IN (5, 10) -- wrong, an
#                                   interval complement is not a membership.
#   SEX NOTIN (F) OR SEX NOTIN (M)  would become SEX IN (F, M) -- close to
#                                   the negation of what was written.
#
# A clause mixing AND and OR is refused outright: Define-XML gives no
# precedence rules, so "A AND B OR C" has no single defensible reading.
#' @noRd
.wc_fold_or <- function(
  conditions,
  id,
  has_and = FALSE,
  call = rlang::caller_env()
) {
  if (has_and) {
    .artoo_abort(
      c(
        "Where clause {.val {id}} mixes AND with OR.",
        "x" = "Define-XML defines no precedence between them, so the intended grouping is ambiguous.",
        "i" = "Split it into separate value-level rows, one per condition."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  vars <- vapply(conditions, function(c) c$variable, character(1))
  cmps <- vapply(conditions, function(c) c$comparator, character(1))

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
  # Only equality-shaped operands survive the rewrite. Anything else means
  # something IN cannot say.
  if (!all(cmps %in% c("EQ", "IN"))) {
    bad <- setdiff(cmps, c("EQ", "IN"))
    .artoo_abort(
      c(
        "Where clause {.val {id}} joins {.val {bad}} with OR.",
        "x" = "Only EQ and IN can be combined into a single IN; rewriting {.val {bad}} would change which rows the clause selects.",
        "i" = "Split it into separate value-level rows, one per condition."
      ),
      kind = "p21_sheet",
      call = call
    )
  }
  values <- unlist(lapply(conditions, function(c) c$values))
  if (anyDuplicated(values)) {
    dup <- unique(values[duplicated(values)])
    .artoo_warn(
      c(
        "Where clause {.val {id}} repeats {.val {dup}}.",
        "i" = "Duplicates are kept once."
      ),
      kind = "spec",
      call = call
    )
  }
  list(list(
    variable = vars[[1]],
    comparator = "IN",
    values = unique(values)
  ))
}

# Render a where clause back into the single-cell expression the current
# workbook generation carries on the ValueLevel sheet.
#
# The exact inverse of .wc_from_values(): scalar operands bare, a set in
# parentheses comma-separated, conditions joined by lowercase " and ", and a
# value quoted only when it contains a space or a comma -- because that is
# the one thing the reader needs the quotes for.
#
# artoo used to emit a where-clause ID here and a separate WhereClauses
# sheet beside it. That sheet belongs to the RETIRED workbook generation,
# whose ValueLevel sheet named its label column differently; pairing it with
# current-generation headers produced a workbook of no generation at all.
#' @noRd
.wc_render <- function(wc) {
  if (is.null(wc) || !nrow(wc)) {
    return(character(0))
  }
  quote_if_needed <- function(x) {
    ifelse(grepl("[ ,]", x), paste0('"', x, '"'), x)
  }
  # Which dataset owns each clause: the one its first check names. A check
  # on any other dataset is qualified below, because the cell has no other
  # way to say so and dropping the qualifier changes what the clause
  # selects.
  owners <- vapply(
    split(as.character(wc$dataset), factor(wc$where_clause_id)),
    function(x) {
      x <- x[!is.na(x)]
      if (length(x)) x[[1L]] else NA_character_
    },
    character(1)
  )
  check <- paste(wc$where_clause_id, wc$check_order, sep = "\r")
  by_check <- vapply(
    split(seq_len(nrow(wc)), factor(check, levels = unique(check))),
    function(rows) {
      row <- wc[rows[[1L]], , drop = FALSE]
      values <- quote_if_needed(as.character(wc$value[rows]))
      values <- values[!is.na(values) & nzchar(values)]
      operand <- if (length(values) > 1L) {
        paste0("(", paste(values, collapse = ", "), ")")
      } else if (length(values)) {
        values
      } else {
        ""
      }
      trimws(paste(.wc_qualify(row, owners), row$comparator, operand))
    },
    character(1)
  )
  ids <- vapply(
    strsplit(names(by_check), "\r", fixed = TRUE),
    function(x) x[[1L]],
    character(1)
  )
  vapply(
    split(unname(by_check), factor(ids, levels = unique(ids))),
    paste,
    character(1),
    collapse = " and "
  )
}

# ---- Analysis-results selection criteria ---------------------------------
#
# The Analysis Results sheet packs, into one cell, what artoo holds as one
# row per result x analysis dataset: a bracket group per dataset,
# `ADQSADAS[EFFFL EQ Y and PARAMCD EQ ACTOT]`, with `ADXX[]` meaning every
# record. Groups for one result sit side by side in the same cell.
#
# Reading it is how a workbook's analysis results reach `arm:AnalysisDataset`
# at all: without it a vendor-authored workbook has no `@ItemGroupOID` and
# the define write refuses the result outright.

# Render one result's rows back into a single cell.
#' @noRd
.arm_render_criteria <- function(rows, rendered) {
  groups <- vapply(
    seq_len(nrow(rows)),
    function(i) {
      ds <- as.character(rows$dataset[[i]])
      if (is.na(ds) || !nzchar(ds)) {
        return(NA_character_)
      }
      id <- as.character(rows$where_clause_id[[i]])
      cond <- if (!is.na(id) && id %in% names(rendered)) rendered[[id]] else ""
      paste0(ds, "[", cond, "]")
    },
    character(1)
  )
  groups <- groups[!is.na(groups)]
  if (!length(groups)) {
    return(NA_character_)
  }
  paste(groups, collapse = " ")
}

# Split a cell into its bracket groups: dataset name, then the condition.
# Bracket-aware rather than a split on "]", so a condition is never cut.
#' @noRd
.arm_split_criteria <- function(text) {
  if (is.na(text) || !nzchar(trimws(text))) {
    return(NULL)
  }
  chars <- strsplit(text, "", fixed = TRUE)[[1L]]
  out <- list()
  name <- character(0)
  cond <- character(0)
  depth <- 0L
  for (ch in chars) {
    if (identical(ch, "[") && depth == 0L) {
      depth <- 1L
      next
    }
    if (identical(ch, "]") && depth == 1L) {
      out[[length(out) + 1L]] <- list(
        dataset = trimws(paste(name, collapse = "")),
        condition = trimws(paste(cond, collapse = ""))
      )
      name <- character(0)
      cond <- character(0)
      depth <- 0L
      next
    }
    if (depth == 1L) {
      cond <- c(cond, ch)
    } else {
      name <- c(name, ch)
    }
  }
  leftover <- trimws(paste(name, collapse = ""))
  if (depth == 1L || nzchar(leftover)) {
    return(NULL)
  }
  out
}

# Variable names from an analysis-variable cell: comma- or space-separated,
# each optionally qualified by its dataset, which is dropped because the row
# already names it.
#' @noRd
.arm_variable_names <- function(x, dataset = NULL) {
  if (is.null(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x))) {
    return(character(0))
  }
  v <- strsplit(trimws(x), "[[:space:],]+")[[1L]]
  v <- v[nzchar(v)]
  # Strip a qualifier only when it names THIS row's dataset. Stripping any
  # leading dot-segment would eat the first component of an ItemOID given
  # verbatim, which is a legal way to name an analysis variable.
  if (!is.null(dataset) && !is.na(dataset) && nzchar(dataset)) {
    at <- startsWith(v, paste0(dataset, "."))
    v[at] <- substring(v[at], nchar(dataset) + 2L)
  }
  v
}

# A variable name for the cell: qualified when the check leaves the dataset
# that owns its clause.
#' @noRd
.wc_qualify <- function(row, owners) {
  ds <- as.character(row$dataset)
  own <- owners[[as.character(row$where_clause_id)]]
  if (is.na(ds) || is.na(own) || identical(ds, own)) {
    as.character(row$variable)
  } else {
    paste0(ds, ".", row$variable)
  }
}
