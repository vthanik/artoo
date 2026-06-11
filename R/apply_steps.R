# apply_steps.R — the internal, ordered steps of apply_spec().
#
# Each step takes the working data frame and a pre-extracted `info` list
# (see .apply_info) and returns a new data frame; the original is never
# mutated, so any step aborting leaves the caller's input untouched
# (the transactional guarantee). Steps are NOT exported: they are not
# independently meaningful and inviting mis-composition. The pipeline is
# fixed — scaffold, coerce, order, sort, stamp — with no subsetting knob.

# Pre-extract the per-dataset spec slices every step shares: the
# order-sorted variable rows, the spec variable names, and the parsed sort
# keys. Mirrors v0's spec_for_dataset(), adapted to the artoo spec shape.
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
      .artoo_warn(
        c(
          "{n_missing} variable{?s} in dataset {.val {dataset}} {?has/have} no {.field order}.",
          "i" = "Ordering the numbered variables first; unnumbered ones trail in spec order."
        ),
        kind = "order",
        call = call
      )
      vars <- vars[order(ord, na.last = TRUE), , drop = FALSE]
    } else if (!anyNA(ord)) {
      vars <- vars[order(ord), , drop = FALSE]
    }
  }
  rownames(vars) <- NULL

  # Duplicate (dataset, variable) rows are rejected at artoo_spec()
  # construction (with row locations), so the slices here are unambiguous.
  list(
    vars = vars,
    spec_vars = vars$variable,
    keys = spec_keys(spec, dataset)
  )
}

# 1. Add spec variables missing from x, as the type-correct NA. A temporal
# variable with no numeric targetDataType is ISO 8601 text by CDISC
# definition (the --DTC convention), so it scaffolds as character NA.
#' @noRd
.scaffold_vars <- function(x, info, call = rlang::caller_env()) {
  missing <- setdiff(info$spec_vars, names(x))
  if (!length(missing)) {
    return(x)
  }
  rows <- match(missing, info$vars$variable)
  types <- info$vars$data_type[rows]
  tdts <- if ("target_data_type" %in% names(info$vars)) {
    info$vars$target_data_type[rows]
  } else {
    rep(NA_character_, length(rows))
  }
  n <- nrow(x)
  for (i in seq_along(missing)) {
    iso_text <- !is.na(types[i]) &&
      types[i] %in% c("date", "datetime", "time") &&
      is.na(tdts[i])
    x[[missing[i]]] <- if (iso_text) {
      rep(NA_character_, n)
    } else {
      .na_for_type(types[i], n)
    }
  }
  .artoo_inform(
    "Scaffolded {length(missing)} variable{?s}: {.var {missing}}",
    kind = "apply"
  )
  x
}

# 2. Coerce each column to its CDISC dataType storage; warn on NA-introduction.
# Lossy numeric coercion (truncated fractions, 32-bit overflow) always
# aborts: silent data damage in a submission dataset is a data-integrity
# event, and the cure is fixing the spec's dataType, not accepting the loss.
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
      # Realize to the R presentation class (Date/POSIXct/hms) using
      # the spec displayFormat (default by dataType when absent). dataType
      # drives the class. Character ISO text realizes ONLY when the spec's
      # targetDataType demands numeric storage; without one, ISO text is
      # already the CDISC exchange form (--DTC) and stays character.
      tdt <- if ("target_data_type" %in% names(vars)) {
        vars$target_data_type[i]
      } else {
        NA_character_
      }
      before_na <- sum(is.na(x[[v]]))
      x[[v]] <- .realize_temporal(
        x[[v]],
        dt,
        vars$display_format[i],
        from_text = !is.na(tdt) && tdt %in% c("integer", "decimal")
      )
      # Re-attach label etc., but keep the realized class and its tzone.
      keep_off <- c("class", "levels", "names", "tzone")
      n_na <- sum(is.na(x[[v]])) - before_na
    } else {
      # Name 32-bit overflow precisely BEFORE coercion turns the values NA —
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
  # Truncation and overflow damage values (a fractional height losing its
  # decimals is a data-integrity event, not a nuisance); the pipeline aborts
  # BEFORE any value is touched — there is no opt-out. Checked ahead of the
  # NA-introduction warning so an abort is never preceded by a half-report
  # of the same values.
  if (length(truncated) || length(overflowed)) {
    lossy <- c(
      if (length(truncated)) {
        sprintf(
          "Integer coercion would truncate fractional values in: %s.",
          paste(truncated, collapse = ", ")
        )
      },
      if (length(overflowed)) {
        sprintf(
          "Integer coercion would overflow R's 32-bit range (values become NA) in: %s.",
          paste(overflowed, collapse = ", ")
        )
      }
    )
    .artoo_abort(
      c(
        "Coercion to the spec dataTypes would lose data.",
        stats::setNames(lossy, rep("x", length(lossy))),
        "i" = "Fix the spec: dataType {.val float} or {.val decimal} keeps fractions; a wider type avoids overflow."
      ),
      kind = "type",
      call = call
    )
  }
  if (length(introduced)) {
    .artoo_warn(
      c(
        "Coercion introduced NA in {length(introduced)} variable{?s}.",
        "i" = "{introduced}"
      ),
      kind = "coercion",
      call = call
    )
  }
  x
}

# The ONE codelist value-mapper. decode_column() is its only caller in the
# pipeline (apply_spec never mutates values); it lives here beside the other
# per-column machinery. Maps a column's values through a codelist's
# term/decode pairs in either direction, with the trim/case soft-match
# (reported, never silent) and the explicit no-match policy. Returns the
# mapped character vector; attribute handling stays with the callers.
#' @noRd
.map_codelist_values <- function(
  col,
  cl,
  direction,
  no_match,
  trim,
  ignore_case,
  var,
  clid,
  call = rlang::caller_env()
) {
  from <- if (direction == "to_decode") cl$term else cl$decode
  to <- if (direction == "to_decode") cl$decode else cl$term
  chr <- as.character(col)
  idx <- match(chr, from)
  # Real data carries trailing whitespace (trim = TRUE, the default) and
  # sometimes case variants (ignore_case, opt-in). A value that matches
  # only after normalization maps, but the variants are reported
  # (artoo_warning_codelist) — a normalized match is still a CT finding
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
  soft <- is.na(idx) & !is.na(chr)
  if ((trim || ignore_case) && any(soft)) {
    idx2 <- match(norm(chr), norm(from))
    gained <- soft & !is.na(idx2)
    if (any(gained)) {
      idx[gained] <- idx2[gained]
      variants <- unique(chr[gained])
      .artoo_warn(
        c(
          "Mapped {sum(gained)} value{?s} in {.var {var}} after trim/case normalization.",
          "i" = "Variant{?s}: {.val {variants}}.",
          "i" = "check_spec() still compares exactly; clean the source values for submission."
        ),
        kind = "codelist",
        call = call
      )
    }
  }
  out <- to[idx]
  unmatched <- !is.na(chr) & is.na(idx)
  if (any(unmatched)) {
    if (no_match == "error") {
      bad <- unique(chr[unmatched])
      .artoo_abort(
        c(
          "Values in {.var {var}} are not in codelist {.val {clid}}.",
          "x" = "Unmatched: {.val {bad[seq_len(min(5L, length(bad)))]}}.",
          "i" = "Set {.code no_match = \"keep\"} or {.code \"na\"} to allow them."
        ),
        kind = "codelist",
        call = call
      )
    } else if (no_match == "keep") {
      out[unmatched] <- chr[unmatched]
    }
    # no_match == "na": leave `out` NA at unmatched positions.
  }
  out[is.na(chr)] <- NA
  out
}

# 3. Reorder columns to the spec's variable order. Columns the spec does
# not declare are never dropped; they trail the declared ones.
#' @noRd
.order_cols <- function(x, info, call = rlang::caller_env()) {
  ordered <- info$spec_vars[info$spec_vars %in% names(x)]
  x[c(ordered, setdiff(names(x), ordered))]
}

# 4. Sort rows by the dataset's keys; record the keys used in `artoo.sort`.
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
  attr(x, "artoo.sort") <- keys
  x
}

# 5. Build the artoo_meta from the spec, stamp records, attach it. Temporal
# storage forms are resolved here, where the metadata meets the data: a
# numeric-backed date/datetime/time column with no spec targetDataType gets
# targetDataType = "integer" recorded (see .meta_resolve_temporal_targets),
# so every codec and sidecar agrees on the exchange form. Columns the spec
# does not declare (apply_spec never drops them) get a meta entry inferred
# from their R class, so the meta describes the WHOLE frame and every codec
# writes it losslessly without per-codec fallbacks.
#' @noRd
.stamp_meta <- function(x, info, spec, dataset, call = rlang::caller_env()) {
  meta <- .meta_from_spec(spec, dataset, records = nrow(x), call = call)
  meta <- .meta_resolve_temporal_targets(meta, x)
  extra <- setdiff(names(x), names(meta@columns))
  if (length(extra)) {
    cols <- meta@columns
    for (nm in extra) {
      cols[[nm]] <- .col_from_frame_col(nm, x[[nm]], meta@dataset$name)
    }
    # Meta entries follow the frame's column order (extras trail).
    cols <- cols[intersect(names(x), names(cols))]
    meta <- artoo_meta_class(dataset = meta@dataset, columns = cols)
  }
  set_meta(x, meta)
}
