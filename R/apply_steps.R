# apply_steps.R -- the internal, ordered steps of apply_spec().
#
# Each step takes the working data frame and a pre-extracted `info` list
# (see .apply_info) and returns a new data frame; the original is never
# mutated, so any step aborting leaves the caller's input untouched
# (the transactional guarantee). Steps are NOT exported: they are not
# independently meaningful and inviting mis-composition. apply_spec()'s
# `steps =` arg selects a subset of the pipeline for surgical use.

# Pre-extract the per-dataset spec slices every step shares: the
# order-sorted variable rows, the spec variable names, and the parsed sort
# keys. Mirrors v0's spec_for_dataset(), adapted to the vport spec shape.
#' @noRd
.apply_info <- function(spec, dataset, call = rlang::caller_env()) {
  vars <- spec_variables(spec, dataset)
  if ("order" %in% names(vars) && nrow(vars)) {
    ord <- suppressWarnings(as.integer(vars$order))
    # A partial order (some but not all rows numbered) still sorts: the
    # numbered rows take their positions and the unnumbered ones trail,
    # rather than silently abandoning the spec's ordering intent.
    if (anyNA(ord) && !all(is.na(ord))) {
      n_missing <- sum(is.na(ord))
      cli::cli_warn(
        c(
          "{n_missing} variable{?s} in dataset {.val {dataset}} {?has/have} no {.field order}.",
          "i" = "Ordering the numbered variables first; unnumbered ones trail in spec order."
        ),
        class = "vport_warning_order",
        call = call
      )
      vars <- vars[order(ord, na.last = TRUE), , drop = FALSE]
    } else if (!anyNA(ord)) {
      vars <- vars[order(ord), , drop = FALSE]
    }
  }
  rownames(vars) <- NULL

  dupes <- unique(vars$variable[duplicated(vars$variable)])
  if (length(dupes)) {
    cli::cli_abort(
      c(
        "Duplicate variable{?s} in the spec for dataset {.val {dataset}}.",
        "x" = "Duplicated: {.val {dupes}}."
      ),
      class = "vport_error_spec",
      call = call
    )
  }

  list(
    vars = vars,
    spec_vars = vars$variable,
    keys = spec_keys(spec, dataset)
  )
}

# 1. Add spec variables missing from x, as the type-correct NA.
#' @noRd
.scaffold_vars <- function(x, info, call = rlang::caller_env()) {
  missing <- setdiff(info$spec_vars, names(x))
  if (!length(missing)) {
    return(x)
  }
  types <- info$vars$data_type[match(missing, info$vars$variable)]
  n <- nrow(x)
  for (i in seq_along(missing)) {
    x[[missing[i]]] <- .na_for_type(types[i], n)
  }
  cli::cli_inform(
    "Scaffolded {length(missing)} variable{?s}: {.var {missing}}",
    class = "vport_message_apply"
  )
  x
}

# 2. Drop columns the spec does not declare.
#' @noRd
.drop_unspec <- function(x, info, call = rlang::caller_env()) {
  to_drop <- setdiff(names(x), info$spec_vars)
  if (length(to_drop)) {
    cli::cli_inform(
      "Dropped {length(to_drop)} variable{?s}: {.var {to_drop}}",
      class = "vport_message_apply"
    )
  }
  keep <- info$spec_vars[info$spec_vars %in% names(x)]
  x[keep]
}

# 3. Coerce each column to its CDISC dataType storage; warn on NA-introduction
# and on fractional values an integer coercion truncated.
#' @noRd
.coerce_types <- function(x, info, call = rlang::caller_env()) {
  vars <- info$vars
  introduced <- character(0)
  truncated <- character(0)
  overflowed <- character(0)
  for (i in seq_len(nrow(vars))) {
    v <- vars$variable[i]
    dt <- vars$data_type[i]
    if (!(v %in% names(x)) || is.na(dt)) {
      next
    }
    old <- attributes(x[[v]])
    if (dt %in% c("date", "datetime", "time")) {
      # Realize to the R presentation class (Date/POSIXct/vport_time) using
      # the spec displayFormat (default by dataType when absent). dataType
      # drives the class; an unrecognized format leaves the column numeric.
      before_na <- sum(is.na(x[[v]]))
      x[[v]] <- .realize_temporal(x[[v]], dt, vars$display_format[i])
      # Re-attach label etc., but keep the realized class and its tzone.
      keep_off <- c("class", "levels", "names", "tzone")
      n_na <- sum(is.na(x[[v]])) - before_na
    } else {
      # Name 32-bit overflow precisely BEFORE coercion turns the values NA --
      # the generic NA-introduction warning would bury the cause.
      if (identical(dt, "integer")) {
        nv <- suppressWarnings(as.numeric(x[[v]]))
        n_over <- sum(!is.na(nv) & abs(nv) > .Machine$integer.max)
        if (n_over > 0L) {
          overflowed <- c(overflowed, sprintf("%s (%d)", v, n_over))
        }
      }
      res <- .coerce_to_type(x[[v]], dt)
      x[[v]] <- res$value
      keep_off <- c("class", "levels", "names")
      n_na <- res$n_na_introduced
      if (res$n_lossy > 0L) {
        truncated <- c(truncated, sprintf("%s (%d)", v, res$n_lossy))
      }
    }
    for (a in setdiff(names(old), keep_off)) {
      attr(x[[v]], a) <- old[[a]]
    }
    if (n_na > 0L) {
      introduced <- c(introduced, sprintf("%s (%d)", v, n_na))
    }
  }
  if (length(introduced)) {
    cli::cli_warn(
      c(
        "Coercion introduced NA in {length(introduced)} variable{?s}.",
        "i" = "{introduced}"
      ),
      class = "vport_warning_coercion",
      call = call
    )
  }
  if (length(truncated)) {
    cli::cli_warn(
      c(
        "Integer coercion truncated fractional values in {length(truncated)} variable{?s}.",
        "i" = "{truncated}",
        "i" = "Use dataType {.val float} or {.val decimal} to keep fractions."
      ),
      class = "vport_warning_coercion",
      call = call
    )
  }
  if (length(overflowed)) {
    cli::cli_warn(
      c(
        "Integer coercion overflowed R's 32-bit range in {length(overflowed)} variable{?s}; those values are now NA.",
        "i" = "{overflowed}",
        "i" = "Use dataType {.val float}, {.val double}, or {.val decimal} for values beyond +/-2147483647."
      ),
      class = "vport_warning_coercion",
      call = call
    )
  }
  x
}

# 4. Optionally translate coded values via the spec codelists. Default
# `decode = "none"` is a no-op: apply_spec() keeps submission-coded values
# and leaves membership to check_spec(). "to_decode" maps code -> decode,
# "to_code" maps decode -> code, with an explicit no-match policy.
#' @noRd
.decode_codelists <- function(
  x,
  info,
  spec,
  decode = "none",
  no_match = "error",
  trim = TRUE,
  ignore_case = FALSE,
  call = rlang::caller_env()
) {
  if (decode == "none") {
    return(x)
  }
  vars <- info$vars
  for (i in which(!is.na(vars$codelist_id))) {
    v <- vars$variable[i]
    clid <- vars$codelist_id[i]
    if (!(v %in% names(x))) {
      next
    }
    # spec_codelists() aborts on an unresolved id (and construction already
    # guarantees resolution), so the rows are always non-empty here.
    cl <- spec_codelists(spec, clid)
    from <- if (decode == "to_decode") cl$term else cl$decode
    to <- if (decode == "to_decode") cl$decode else cl$term
    col <- as.character(x[[v]])
    idx <- match(col, from)
    # Real data carries trailing whitespace (trim = TRUE, the default) and
    # sometimes case variants (ignore_case, opt-in). A value that matches
    # only after normalization decodes, but the variants are reported
    # (vport_warning_codelist) -- a normalized match is still a CT finding
    # for check_spec(), which always compares exactly.
    norm <- function(s) {
      if (trim) {
        s <- trimws(s)
      }
      if (ignore_case) {
        s <- toupper(s)
      }
      s
    }
    soft <- is.na(idx) & !is.na(col)
    if ((trim || ignore_case) && any(soft)) {
      idx2 <- match(norm(col), norm(from))
      gained <- soft & !is.na(idx2)
      if (any(gained)) {
        idx[gained] <- idx2[gained]
        variants <- unique(col[gained])
        cli::cli_warn(
          c(
            "Decoded {sum(gained)} value{?s} in {.var {v}} after trim/case normalization.",
            "i" = "Variant{?s}: {.val {variants}}.",
            "i" = "check_spec() still compares exactly; clean the source values for submission."
          ),
          class = "vport_warning_codelist",
          call = call
        )
      }
    }
    out <- to[idx]
    unmatched <- !is.na(col) & is.na(idx)
    if (any(unmatched)) {
      if (no_match == "error") {
        bad <- unique(col[unmatched])
        cli::cli_abort(
          c(
            "Values in {.var {v}} are not in codelist {.val {clid}}.",
            "x" = "Unmatched: {.val {bad[seq_len(min(5L, length(bad)))]}}.",
            "i" = "Set {.code no_match = \"keep\"} or {.code \"na\"} to allow them."
          ),
          class = "vport_error_codelist",
          call = call
        )
      } else if (no_match == "keep") {
        out[unmatched] <- col[unmatched]
      }
      # no_match == "na": leave `out` NA at unmatched positions.
    }
    out[is.na(col)] <- NA
    # Preserve non-class attributes (e.g. label); only the values change.
    old <- attributes(x[[v]])
    x[[v]] <- out
    for (a in setdiff(names(old), c("class", "levels", "names"))) {
      attr(x[[v]], a) <- old[[a]]
    }
  }
  x
}

# 5. Reorder columns to the spec's variable order.
#' @noRd
.order_cols <- function(x, info, call = rlang::caller_env()) {
  ordered <- info$spec_vars[info$spec_vars %in% names(x)]
  x[c(ordered, setdiff(names(x), ordered))]
}

# 6. Sort rows by the dataset's keys; record the keys used in `vport.sort`.
# `na_position` controls where missing key values land: "first" (SAS PROC
# SORT / FDA convention, the default) or "last" (R / pandas / Polars).
#' @noRd
.sort_keys <- function(
  x,
  info,
  na_position = "first",
  call = rlang::caller_env()
) {
  keys <- info$keys[info$keys %in% names(x)]
  if (!length(keys)) {
    return(x)
  }
  na_last <- identical(na_position, "last")
  ord <- do.call(order, c(unname(as.list(x[keys])), list(na.last = na_last)))
  x <- x[ord, , drop = FALSE]
  rownames(x) <- NULL
  attr(x, "vport.sort") <- keys
  x
}

# 7. Build the vport_meta from the spec, stamp records, attach it.
#' @noRd
.stamp_meta <- function(x, info, spec, dataset, call = rlang::caller_env()) {
  meta <- .meta_from_spec(spec, dataset, records = nrow(x), call = call)
  set_meta(x, meta)
}
