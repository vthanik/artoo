# sas_missing.R -- special-missing (.A-.Z, ._) carriage across codecs.
#
# In-session canonical form: the row-aligned `sas_missing` character attribute
# on a column (NA where untagged; values ".", "._", ".A"-".Z"), exactly what
# the xpt layer produces (.ibm_to_ieee) and consumes (.ieee_to_ibm). On disk,
# json and parquet carry the tags in the namespaced `_vport.specialMissings`
# block of the metadata payload; the data values stay plain nulls, so a
# foreign reader degrades gracefully to ordinary missings.
#
# Invariants:
# - Tags ride the container only at codec ENCODE time: row indices are
#   computed fresh against the frame being written. They are deliberately NOT
#   part of the metadata_json string set_meta() stamps -- a stored row-index
#   map would desync under user subsetting. Only codecs pass `special=` to
#   .meta_payload().
# - "." is the default meaning of an on-disk null, so it is never carried;
#   a plain missing reads back untagged (an xpt leg re-tags it "." on read).
# - rds needs no carrier: saveRDS round-trips the attribute natively.

# Gather the non-"." tags of every column into the on-disk shape: a named
# list of list(rows = <integer, 1-based>, tags = <character>), or NULL when
# the frame carries none. Only tags sitting on an NA cell count -- a tag on a
# non-NA cell is stale and is dropped, not carried.
#' @noRd
.collect_special_missings <- function(x) {
  out <- list()
  for (nm in names(x)) {
    tags <- attr(x[[nm]], "sas_missing", exact = TRUE)
    if (is.null(tags)) {
      next
    }
    keep <- !is.na(tags) & tags != "." & is.na(x[[nm]])
    if (!any(keep)) {
      next
    }
    out[[nm]] <- list(rows = which(keep), tags = unname(tags[keep]))
  }
  if (length(out)) out else NULL
}

# Reattach collected tags onto a decoded frame. Unknown columns and
# out-of-range rows are ignored (a defensive guard for hand-edited files);
# a column gains the attribute only when at least one tag lands.
#' @noRd
.apply_special_missings <- function(df, sm) {
  for (nm in intersect(names(sm), names(df))) {
    e <- sm[[nm]]
    ok <- e$rows >= 1L & e$rows <= nrow(df)
    if (!any(ok)) {
      next
    }
    tags <- rep(NA_character_, nrow(df))
    tags[e$rows[ok]] <- e$tags[ok]
    attr(df[[nm]], "sas_missing") <- tags
  }
  df
}

# Align a tag vector to a row subset (the partial-read path: row-subsetting a
# data frame drops column attributes, so .apply_partial_read re-attaches the
# subsetted tags). NULL passes through.
#' @noRd
.subset_special_missings <- function(tags, i) {
  if (is.null(tags)) {
    return(NULL)
  }
  tags[i]
}
