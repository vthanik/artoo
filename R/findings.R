# findings.R — the one findings model, shared by both checkers.
#
# A "finding" is one concept with one shape: a 6-column data frame
# (check, dimension, severity, dataset, variable, message). The open rule
# catalog (inst/spec_rules.json) is the single source of truth for every
# rule's dimension and severity, and which engine runs it:
#   engine == "spec"  -> validate_spec() (spec integrity)
#   engine == "data"  -> check_spec()    (data conformance)
# Both checkers build findings through .finding(), so severity/dimension
# can never drift from the catalog. artoo uses its own behavioral check ids
# only, never another tool's rule numbering.

# ---- Catalog loader (cached) --------------------------------------------

.spec_rules_env <- new.env(parent = emptyenv())

# The known dimensions/severities/engines a catalog entry may use.
.spec_dimensions <- c(
  "study",
  "dataset",
  "variable",
  "value",
  "codelist",
  "method",
  "comment",
  "document",
  "ct",
  "arm"
)
.spec_severities <- c("error", "warning", "note")
.spec_engines <- c("spec", "data")

#' @noRd
.spec_rules <- function() {
  if (is.null(.spec_rules_env$rules)) {
    path <- system.file("spec_rules.json", package = "artoo")
    if (!nzchar(path)) {
      .artoo_abort(
        "Rule catalog {.file spec_rules.json} is missing from the install.",
        kind = "validation"
      )
    }
    r <- jsonlite::fromJSON(path, simplifyDataFrame = TRUE)
    .check_rules_df(r)
    .spec_rules_env$rules <- r
  }
  .spec_rules_env$rules
}

# Validate the catalog shape (H20). Aborts on a malformed catalog.
#' @noRd
.check_rules_df <- function(r) {
  need <- c(
    "id",
    "dimension",
    "severity",
    "requires_data",
    "scope",
    "status",
    "engine"
  )
  miss <- setdiff(need, names(r))
  if (length(miss)) {
    .artoo_abort(
      "Rule catalog is missing column{?s}: {.val {miss}}.",
      kind = "validation"
    )
  }
  bad_sev <- unique(r$severity[!r$severity %in% .spec_severities])
  if (length(bad_sev)) {
    .artoo_abort(
      "Rule catalog has unknown severit{?y/ies}: {.val {bad_sev}}.",
      kind = "validation"
    )
  }
  bad_dim <- unique(r$dimension[!r$dimension %in% .spec_dimensions])
  if (length(bad_dim)) {
    .artoo_abort(
      "Rule catalog has unknown dimension{?s}: {.val {bad_dim}}.",
      kind = "validation"
    )
  }
  bad_eng <- unique(r$engine[!r$engine %in% .spec_engines])
  if (length(bad_eng)) {
    .artoo_abort(
      "Rule catalog has unknown engine{?s}: {.val {bad_eng}}.",
      kind = "validation"
    )
  }
  # A data-engine rule cannot run without data.
  no_data <- unique(r$id[r$engine == "data" & !r$requires_data])
  if (length(no_data)) {
    .artoo_abort(
      "Rule catalog data-engine rule{?s} {.val {no_data}} must require data.",
      kind = "validation"
    )
  }
  dup_id <- unique(r$id[duplicated(r$id)])
  if (length(dup_id)) {
    .artoo_abort(
      "Rule catalog has duplicate id{?s}: {.val {dup_id}}.",
      kind = "validation"
    )
  }
  invisible(r)
}

#' @noRd
.spec_rule <- function(id) {
  r <- .spec_rules()
  row <- r[r$id == id, , drop = FALSE]
  if (nrow(row) != 1L) {
    .artoo_abort(
      "Unknown check id {.val {id}} (not in the rule catalog).",
      kind = "validation"
    )
  }
  row
}

# ---- Findings primitives ------------------------------------------------

#' @noRd
.empty_findings <- function() {
  data.frame(
    check = character(0),
    dimension = character(0),
    severity = character(0),
    dataset = character(0),
    variable = character(0),
    message = character(0),
    stringsAsFactors = FALSE
  )
}

# Build a findings frame for one check; dimension/severity come from the
# catalog by check_id. `message` drives the row count; dataset/variable
# recycle. Zero messages -> zero rows.
#' @noRd
.finding <- function(check_id, dataset, variable, message) {
  if (!length(message)) {
    return(.empty_findings())
  }
  meta <- .spec_rule(check_id)
  data.frame(
    check = check_id,
    dimension = meta$dimension,
    severity = meta$severity,
    dataset = dataset,
    variable = variable,
    message = message,
    stringsAsFactors = FALSE
  )
}

#' @noRd
.bind_findings <- function(parts) {
  parts <- Filter(function(x) !is.null(x) && nrow(x), parts)
  if (!length(parts)) {
    return(.empty_findings())
  }
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}

# ---- Shared text helpers ------------------------------------------------

# TRUE where x is NA or empty/whitespace.
#' @noRd
.blank <- function(x) {
  is.na(x) | !nzchar(trimws(as.character(x)))
}

# Non-blank values of one column, or character(0) when absent.
#' @noRd
.refs <- function(df, col) {
  if (is.null(df) || !is.data.frame(df) || !(col %in% names(df))) {
    return(character(0))
  }
  v <- df[[col]]
  unique(trimws(as.character(v[!.blank(v)])))
}

# ---- One codelist-membership implementation -----------------------------

# Data values outside a codelist's allowed terms. A mandatory variable's NA
# is a violation; otherwise NA/"" pass. Returns the offending (bad) values.
# The single membership rule shared by check_spec()'s codelist_membership and
# validate_spec(data=)'s .chk_ct.
#' @noRd
.codelist_violations <- function(values, terms, mandatory = FALSE) {
  allow <- trimws(as.character(terms))
  if (!isTRUE(mandatory)) {
    allow <- c(allow, NA_character_, "")
  }
  v <- trimws(as.character(values))
  v_na <- is.na(values)
  ok <- (v %in% allow) | (v_na & !isTRUE(mandatory))
  unique(values[!ok])
}

# ---- Mandatory / permissible classification ------------------------------

# Whether each spec variable is mandatory. The spec stores `mandatory` as a
# logical, but a raw frame may carry character flags ("Y"/"N"); both are
# accepted, vectorized. NA or an unrecognized value is treated as MANDATORY
# (conservative: an unknown obligation is never silently downgraded to
# permissible, so a missing such variable stays an error, not a warning).
#' @noRd
.is_mandatory <- function(x) {
  if (is.logical(x)) {
    return(ifelse(is.na(x), TRUE, x))
  }
  s <- toupper(trimws(as.character(x)))
  permissible <- s %in% c("N", "NO", "FALSE", "0")
  !permissible
}
