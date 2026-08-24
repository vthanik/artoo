# define_oid.R — mint every OID once, before a single node exists.
#
# One symbol table, built up front, consulted by every builder. Nothing
# downstream invents an identifier, which is what makes a dangling reference
# structurally impossible rather than merely unlikely: an ItemRef and its
# ItemDef read the SAME map entry, so they cannot disagree.
#
# Two rules govern the table:
#
#   * A SUPPLIED OID WINS VERBATIM. A spec read from a define.xml already
#     carries the sponsor's identifiers, and rewriting them would break every
#     external reference into that document (a reviewer's bookmark, a P21
#     report, a prior submission). artoo only mints what is absent.
#   * A MINTED OID IS READABLE AND DERIVED FROM CONTENT, never positional.
#     "IT.DM.USUBJID" survives filtering and reordering; "IT.17" does not.
#
# The prefixes match what the common tooling emits (IG. IT. VL. WC. CL. MT.
# COM. STD. LF. MDV.), so a hand-written spec and a generated one produce
# recognisable, comparable documents.

# Lookup that never throws. `[[` on a named vector raises "subscript out of
# bounds" when the name is absent, and every key here comes from user data.
# `match()` turns an unknown key into NA, which is the answer we want.
#' @noRd
.dx_get <- function(map, key) {
  if (!length(map) || !length(key)) {
    return(rep(NA_character_, length(key)))
  }
  unname(map[match(as.character(key), names(map))])
}

# Compose a lookup key from several columns. A carriage return separates
# them -- the same separator .wc_from_values() uses -- because it cannot
# occur in a SAS name, so "AE" + "TERM" cannot collide with "AET" + "ERM".
#' @noRd
.dx_key <- function(...) {
  paste(..., sep = "\r")
}

# Make a fragment safe inside an OID. ODM types an OID as a plain string, but
# a space or a slash in one is a reliable way to break the downstream tooling
# that parses OIDs, so minted fragments are restricted.
#' @noRd
.dx_slug <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  gsub("[^A-Za-z0-9_.-]+", "_", x)
}

# Supplied value, or the minted fallback where the supplied one is absent.
#' @noRd
.dx_fill <- function(supplied, minted) {
  out <- as.character(supplied)
  if (!length(out)) {
    return(character(0))
  }
  blank <- is.na(out) | !nzchar(trimws(out))
  out[blank] <- minted[blank]
  out
}

# A named map from `keys` to `vals`, first occurrence winning. Duplicated
# keys are normal (a codelist repeats its list-level fields on every term
# row), so this is a de-duplicating constructor rather than an error.
#' @noRd
.dx_map <- function(keys, vals) {
  keys <- as.character(keys)
  keep <- !duplicated(keys) & !is.na(keys)
  out <- as.character(vals)[keep]
  names(out) <- keys[keep]
  out
}

# Build the whole symbol table for one spec.
#
# `values` is grouped by its owning (dataset, variable): that pair, not a
# column on the value-level table, is what identifies a def:ValueListDef,
# because the Define-XML reader records the parent's ValueListOID on the
# PARENT variable and the P21 reader records no OID at all.
#' @noRd
.dx_oids <- function(spec, call = rlang::caller_env()) {
  ds <- spec@datasets
  var <- spec@variables
  val <- spec@values

  study_name <- .dx_study_field(spec, "study_name")
  # The document's own Study/@OID wins, as every supplied identifier does.
  study_oid <- .dx_study_field(spec, "study_oid")
  if (is.na(study_oid)) {
    study_oid <- if (is.na(study_name)) {
      "STDY.1"
    } else {
      paste0("STDY.", .dx_slug(study_name))
    }
  }

  dataset_oid <- .dx_map(
    ds$dataset,
    .dx_fill(ds$itemgroupoid, paste0("IG.", .dx_slug(ds$dataset)))
  )

  variable_oid <- .dx_map(
    .dx_key(var$dataset, var$variable),
    .dx_fill(
      var$itemoid,
      paste0("IT.", .dx_slug(var$dataset), ".", .dx_slug(var$variable))
    )
  )

  # Value-level metadata is keyed by the PARENT ItemDef's OID, not by
  # (dataset, variable). Define-XML hangs def:ValueListRef off the ItemDef,
  # and two ItemGroupDefs may share one ItemDef -- the CDISC 2.0 SDTM example
  # gives IT.QS.QSORRES to three QS datasets. Keying by dataset would mint
  # three different value lists for the one ItemDef that can only carry one,
  # and the ItemDef pool would then see three conflicting definitions.
  value_parent <- character(0)
  value_list <- character(0)
  value_item <- character(0)
  if (!is.null(val) && nrow(val)) {
    value_parent <- .dx_get(
      variable_oid,
      .dx_key(val$dataset, val$variable)
    )
    orphan <- is.na(value_parent)
    if (any(orphan)) {
      where <- unique(paste0(val$dataset[orphan], ".", val$variable[orphan]))
      .artoo_abort(
        c(
          "{length(where)} value-level row{?s} qualif{?ies/y} a variable the spec does not carry.",
          "x" = "{.val {where}}.",
          "i" = "A def:ValueListDef hangs off its parent ItemDef, so the variable must be in the spec."
        ),
        kind = "define",
        call = call
      )
    }
    value_list <- .dx_map(
      value_parent,
      .dx_fill(
        .dx_get(
          .dx_map(variable_oid, var$value_list_id),
          value_parent
        ),
        paste0("VL.", sub("^IT[.]", "", value_parent))
      )
    )
    # A minted value-level OID is content-addressed on the where clause that
    # selects the row, because that is what distinguishes one value-level
    # item from another. An ordinal is the fallback, and only the fallback:
    # it renumbers the moment rows are filtered or reordered, which is the
    # positional-identifier failure this file exists to avoid.
    ordinal <- integer(nrow(val))
    for (k in unique(value_parent)) {
      hit <- which(value_parent == k)
      ordinal[hit] <- seq_along(hit)
    }
    fallback <- sprintf("%s.%d", value_parent, ordinal)
    wc <- .dx_value_where_key(val)
    minted <- ifelse(
      is.na(wc),
      fallback,
      sprintf("%s.%s", value_parent, .dx_slug(wc))
    )
    # A collision drops the WHOLE parent back to ordinals, not just the
    # colliding rows. Substituting row by row is not a fixed point: an
    # ordinal put in to break one clash can land on a content mint that
    # survived, and the second collision goes unnoticed until the ItemDef
    # pool refuses the document with a message about identifiers the user
    # never supplied.
    value_item <- .dx_fill(val$itemoid, minted)
    # Every OID the spec supplies anywhere, not just on the value-level
    # rows: a VARIABLE itemoid shaped like "<parent>.1" occupies the same
    # namespace a minted ordinal draws from.
    supplied <- c(as.character(val$itemoid), as.character(var$itemoid))
    supplied <- supplied[!is.na(supplied) & nzchar(trimws(supplied))]
    for (k in unique(value_parent)) {
      hit <- which(value_parent == k)
      minted_here <- hit[.dx_blank(val$itemoid[hit])]
      # Two ways a mint goes wrong: it repeats another mint, or it lands on
      # an OID the spec supplied elsewhere. Both end at the ItemDef pool
      # blaming the user for an identifier artoo chose.
      clash <- anyDuplicated(value_item[hit]) > 0L ||
        any(value_item[minted_here] %in% supplied)
      if (!clash) {
        next
      }
      # Reset the whole parent to ordinals, then step ordinals that a
      # SUPPLIED OID already occupies. Without that second step the reset
      # itself can collide -- a row minted "...1" against a sibling whose
      # spec-given itemoid is "...1" -- and the ItemDef pool then refuses the
      # document, blaming identifiers the user never chose.
      n <- 0L
      for (i in hit) {
        if (!.dx_blank(val$itemoid[[i]])) {
          next
        }
        repeat {
          n <- n + 1L
          candidate <- sprintf("%s.%d", k, n)
          if (!(candidate %in% supplied)) {
            break
          }
        }
        value_item[[i]] <- candidate
      }
    }
  }

  list(
    study = study_oid,
    mdv = .dx_mdv_oid(spec, study_name),
    dataset = dataset_oid,
    variable = variable_oid,
    value_parent = value_parent,
    value_list = value_list,
    value_item = value_item
  )
}

# The where-clause identifier a value-level row names, from either column the
# readers fill. Unlike .dx_where_key() this does not check the clause is
# defined and never aborts: it is only a naming hint, and the real check runs
# when the def:WhereClauseRef is built.
#' @noRd
.dx_value_where_key <- function(val) {
  id <- .dx_chr(val, "where_clause_id")
  txt <- .dx_chr(val, "where_clause")
  out <- trimws(ifelse(is.na(id) | !nzchar(trimws(id)), txt, id))
  # Free text is not an identifier; only an OID-shaped value is a useful
  # fragment, and anything else falls through to the ordinal.
  out[is.na(out) | !grepl("^[A-Za-z0-9_.-]+$", out)] <- NA_character_
  out
}

# A scalar field off the single-row study frame, NA when absent.
#' @noRd
.dx_study_field <- function(spec, name) {
  study <- spec@study
  if (!nrow(study) || !(name %in% names(study))) {
    return(NA_character_)
  }
  v <- as.character(study[[name]][[1]])
  if (is.na(v) || !nzchar(trimws(v))) NA_character_ else v
}

# MetaDataVersion OID. One per document, so it only has to be unique within
# the file; naming it after the study keeps two studies' documents
# distinguishable when a reviewer opens both.
#' @noRd
.dx_mdv_oid <- function(spec, study_name) {
  supplied <- .dx_study_field(spec, "metadata_version_oid")
  if (!is.na(supplied)) {
    return(supplied)
  }
  if (is.na(study_name)) "MDV.1" else paste0("MDV.", .dx_slug(study_name))
}
