# apply_steps.R — the internal, ordered steps of apply_spec().
#
# Each step takes the working data frame and a pre-extracted `info` list
# (see .apply_info) and returns a new data frame; the original is never
# mutated, so any step aborting leaves the caller's input untouched
# (the transactional guarantee). Steps are NOT exported: they are not
# independently meaningful and inviting mis-composition. The pipeline is
# fixed — coerce, order, sort, stamp; the extra = "drop"
# trim lives in apply_spec() itself, BEFORE the findings are computed,
# so the findings describe the returned columns (it is an output policy,
# not a fifth step).

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

# 1. Coerce each column to its CDISC dataType storage; warn on NA-introduction.
# Lossy numeric coercion (truncated fractions, 32-bit overflow) aborts under
# the default on_coercion_loss = "error" (silent data damage in a submission
# dataset is a data-integrity event); on_coercion_loss = "keep" skips the
# offending column instead, keeping its wider source type for a QC pass.
#' @noRd
.coerce_types <- function(
  x,
  info,
  on_coercion_loss = "error",
  call = rlang::caller_env()
) {
  vars <- info$vars
  # One structured record per (variable, reason). The data frame attached
  # to the condition is the source of truth; the message strings are
  # DERIVED from it below, so message and data can never drift.
  records <- list()
  for (i in seq_len(nrow(vars))) {
    v <- vars$variable[i]
    dt <- vars$data_type[i]
    if (!(v %in% names(x)) || is.na(dt)) {
      next
    }
    old <- attributes(x[[v]])
    # on_coercion_loss = "keep": when an integer dataType would truncate
    # fractional values or overflow the 32-bit range, skip coercion and leave
    # the column at its wider source type, untouched. The mismatch is not
    # silent -- the kept column is still fractional/oversized, so check_spec()'s
    # integer_fraction / integer_overflow rule reports it (an error finding) and
    # conformance = "warn" surfaces it. Probe a de-factored copy so detection
    # reads authored values without mutating x[[v]] (a factor and its attributes
    # survive the skip intact). The "error" default falls through to the abort.
    if (identical(dt, "integer") && on_coercion_loss == "keep") {
      probe <- if (is.factor(x[[v]])) as.character(x[[v]]) else x[[v]]
      if (
        any(.is_integer_fractional(probe)) || any(.is_integer_overflowed(probe))
      ) {
        next
      }
    }
    # Coerce a factor to its labels up front: the 32-bit overflow pre-check
    # and the temporal realiser below both read x[[v]] directly, and
    # as.numeric(<factor>) would see level codes, not the authored values.
    # The label (and any other non-structural attr) survives via `old`,
    # re-attached below; class/levels are intentionally dropped (keep_off).
    if (is.factor(x[[v]])) {
      x[[v]] <- as.character(x[[v]])
    }
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
        n_over <- sum(.is_integer_overflowed(x[[v]]))
        if (n_over > 0L) {
          records[[length(records) + 1L]] <- list(
            variable = v,
            data_type = dt,
            n = n_over,
            reason = "overflowed"
          )
        }
      }
      res <- .coerce_to_type(x[[v]], dt)
      x[[v]] <- res$value
      keep_off <- c("class", "levels", "names")
      n_na <- res$n_na_introduced
      if (res$n_lossy > 0L) {
        records[[length(records) + 1L]] <- list(
          variable = v,
          data_type = dt,
          n = res$n_lossy,
          reason = "truncated"
        )
      }
    }
    for (a in setdiff(names(old), keep_off)) {
      attr(x[[v]], a) <- old[[a]]
    }
    if (n_na > 0L) {
      records[[length(records) + 1L]] <- list(
        variable = v,
        data_type = dt,
        n = n_na,
        reason = "na_introduced"
      )
    }
  }
  rec_frame <- function(reasons) {
    keep <- records[
      vapply(records, function(r) r$reason %in% reasons, logical(1))
    ]
    data.frame(
      variable = vapply(keep, function(r) r$variable, character(1)),
      data_type = vapply(keep, function(r) r$data_type, character(1)),
      n = vapply(keep, function(r) as.integer(r$n), integer(1)),
      reason = vapply(keep, function(r) r$reason, character(1)),
      stringsAsFactors = FALSE
    )
  }
  rec_strings <- function(df) {
    sprintf("%s (%d)", df$variable, df$n)
  }
  # Truncation and overflow damage values (a fractional height losing its
  # decimals is a data-integrity event, not a nuisance); under the default
  # on_coercion_loss = "error" the pipeline aborts BEFORE any value is
  # touched. (on_coercion_loss = "keep" already skipped these columns above,
  # so they never reach lossy_df.) Checked ahead of the NA-introduction
  # warning so an abort is never preceded by a half-report of the same values.
  lossy_df <- rec_frame(c("truncated", "overflowed"))
  if (nrow(lossy_df)) {
    truncated <- rec_strings(lossy_df[lossy_df$reason == "truncated", ])
    overflowed <- rec_strings(lossy_df[lossy_df$reason == "overflowed", ])
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
        "i" = "This gate is separate from {.arg conformance}; {.code conformance = \"off\"} does not bypass it.",
        "i" = "To keep these values in R, set {.code apply_spec(on_coercion_loss = \"keep\")}, or retype the spec with {.fn set_type} (dataType {.val float} or {.val decimal}).",
        "i" = "To see every finding at once, run {.code check_spec(x, spec, dataset)}."
      ),
      kind = "type",
      variables = lossy_df,
      call = call
    )
  }
  na_df <- rec_frame("na_introduced")
  if (nrow(na_df)) {
    introduced <- rec_strings(na_df)
    .artoo_warn(
      c(
        "Coercion introduced NA in {nrow(na_df)} variable{?s}.",
        "i" = "{introduced}"
      ),
      kind = "coercion",
      variables = na_df,
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

# 2. Reorder columns to the spec's variable order. Columns the spec does
# not declare are never dropped; they trail the declared ones.
#' @noRd
.order_cols <- function(x, info, call = rlang::caller_env()) {
  ordered <- info$spec_vars[info$spec_vars %in% names(x)]
  x[c(ordered, setdiff(names(x), ordered))]
}

# 3. Sort rows by the dataset's keys; record the keys used in `artoo.sort`.
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
  # method = "radix" pins C-locale (byte) collation: deterministic across
  # locales (so a byte-stable XPORT snapshot stays stable) and matching SAS
  # PROC SORT for ASCII. Default order() collates character keys by LC_COLLATE.
  ord <- do.call(
    order,
    c(unname(as.list(x[keys])), list(na.last = na_last, method = "radix"))
  )
  x <- x[ord, , drop = FALSE]
  rownames(x) <- NULL
  attr(x, "artoo.sort") <- keys
  x
}

# 4. Build the artoo_meta from the spec, stamp records, attach it. Temporal
# storage forms are resolved here, where the metadata meets the data: a
# numeric-backed date/datetime/time column with no spec targetDataType gets
# targetDataType = "integer" recorded (see .meta_resolve_temporal_targets),
# so every codec and sidecar agrees on the exchange form. A spec variable the
# data lacks gets NO meta entry (apply_spec never fabricates it; it surfaces as
# a missing_variable / missing_permissible finding instead), and a column the
# spec does not declare gets a meta entry inferred from its R class, so the
# meta describes EXACTLY the frame and every codec writes it losslessly
# without per-codec fallbacks.
#' @noRd
.stamp_meta <- function(x, info, spec, dataset, call = rlang::caller_env()) {
  meta <- .meta_from_spec(spec, dataset, records = nrow(x), call = call)
  # The spec declares every variable; the frame may lack some (apply_spec no
  # longer scaffolds). Drop those phantom meta entries so the meta never
  # describes a column the frame does not carry.
  present <- intersect(names(meta@columns), names(x))
  if (length(present) != length(meta@columns)) {
    meta <- .meta_select_columns(meta, present)
  }
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
