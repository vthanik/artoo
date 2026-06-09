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
  if ("order" %in% names(vars)) {
    ord <- suppressWarnings(as.integer(vars$order))
    if (!anyNA(ord)) {
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
  cli::cli_inform("Scaffolded {length(missing)} variable{?s}: {.var {missing}}")
  x
}

# 2. Drop columns the spec does not declare.
#' @noRd
.drop_unspec <- function(x, info, call = rlang::caller_env()) {
  to_drop <- setdiff(names(x), info$spec_vars)
  if (length(to_drop)) {
    cli::cli_inform("Dropped {length(to_drop)} variable{?s}: {.var {to_drop}}")
  }
  keep <- info$spec_vars[info$spec_vars %in% names(x)]
  x[keep]
}

# 3. Coerce each column to its CDISC dataType storage; warn on NA-introduction.
#' @noRd
.coerce_types <- function(x, info, call = rlang::caller_env()) {
  vars <- info$vars
  introduced <- character(0)
  for (i in seq_len(nrow(vars))) {
    v <- vars$variable[i]
    dt <- vars$data_type[i]
    if (!(v %in% names(x)) || is.na(dt)) {
      next
    }
    res <- .coerce_to_type(x[[v]], dt)
    old <- attributes(x[[v]])
    x[[v]] <- res$value
    for (a in setdiff(names(old), c("class", "levels", "names"))) {
      attr(x[[v]], a) <- old[[a]]
    }
    if (res$n_na_introduced > 0L) {
      introduced <- c(
        introduced,
        sprintf("%s (%d)", v, res$n_na_introduced)
      )
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
    cl <- spec_codelist(spec, clid)
    if (!nrow(cl)) {
      next
    }
    from <- if (decode == "to_decode") cl$term else cl$decode
    to <- if (decode == "to_decode") cl$decode else cl$term
    col <- as.character(x[[v]])
    idx <- match(col, from)
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
#' @noRd
.sort_keys <- function(x, info, call = rlang::caller_env()) {
  keys <- info$keys[info$keys %in% names(x)]
  if (!length(keys)) {
    return(x)
  }
  ord <- do.call(order, unname(as.list(x[keys])))
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
