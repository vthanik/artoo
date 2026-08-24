# define_build_vlm.R — value-level metadata, where clauses, and the ItemDef
# pool shared by both.
#
# A value-level definition is five artefacts, and a writer that emits four of
# them produces a document that validates and means nothing:
#
#   1. def:ValueListRef on the PARENT variable's ItemDef
#   2. the def:ValueListDef itself
#   3. a real ItemDef per value-level row (its own DataType, Length, codelist)
#   4. def:WhereClauseRef inside each of that list's ItemRefs
#   5. the def:WhereClauseDef the ref names
#
# All five come off one symbol-table entry, so they cannot disagree about an
# identifier.
#
# ItemDefs are POOLED. Define-XML lets two ItemGroupDefs reference one
# ItemDef, and the bundled CDISC 2.1 SDTM example does exactly that (179
# ItemDefs for 199 ItemRefs), so the writer emits one ItemDef per distinct
# OID and refuses to emit two conflicting definitions under the same OID.

# The columns that DEFINE an item, as opposed to the ones that belong to a
# reference (order, key sequence, role, mandatory, method).
.dx_itemdef_fields <- c(
  "oid",
  "name",
  "label",
  "data_type",
  "length",
  "significant_digits",
  "display_format",
  "sas_field_name",
  "codelist_id",
  "comment_id",
  "origin",
  "source",
  "origin_description",
  "origin_document_id",
  "pages",
  "page_type",
  "page_title",
  "alias_context",
  "alias_name",
  "value_list_id"
)

# Assemble one frame of ItemDef definitions from the variables and the
# value-level rows, resolve DataType, then pool by OID.
#' @noRd
.dx_itemdefs <- function(spec, oids, call = rlang::caller_env()) {
  var <- spec@variables
  val <- spec@values
  types <- .dx_resolve_datatypes(spec, oids)

  parent <- data.frame(
    oid = .dx_get(oids$variable, .dx_key(var$dataset, var$variable)),
    name = as.character(var$variable),
    label = .dx_chr(var, "label"),
    data_type = types$variables,
    length = .dx_chr(var, "length"),
    significant_digits = .dx_chr(var, "significant_digits"),
    display_format = .dx_chr(var, "display_format"),
    sas_field_name = .dx_chr(var, "sas_field_name"),
    codelist_id = .dx_chr(var, "codelist_id"),
    comment_id = .dx_chr(var, "comment_id"),
    origin = .dx_chr(var, "origin"),
    source = .dx_chr(var, "source"),
    origin_description = .dx_chr(var, "origin_description"),
    origin_document_id = .dx_chr(var, "origin_document_id"),
    pages = .dx_chr(var, "pages"),
    page_type = .dx_chr(var, "page_type"),
    page_title = .dx_chr(var, "page_title"),
    alias_context = .dx_chr(var, "alias_context"),
    alias_name = .dx_chr(var, "alias_name"),
    # The variable's OWN def:ValueListRef wins; the derived map fills in for
    # a spec that never carried one. Deriving it first breaks a POOLED
    # ItemDef: two ItemGroupDefs referencing one ItemDef produce one row with
    # the OID and one without, and the pool then sees two definitions of the
    # same OID. The lookup is by the variable's OID, not its name, for the
    # same reason.
    value_list_id = .dx_fill(
      .dx_chr(var, "value_list_id"),
      .dx_get(
        oids$value_list,
        .dx_get(oids$variable, .dx_key(var$dataset, var$variable))
      )
    ),
    stringsAsFactors = FALSE
  )

  child <- if (is.null(val) || !nrow(val)) {
    parent[0, , drop = FALSE]
  } else {
    data.frame(
      oid = oids$value_item,
      # The value-level ItemDef is named for the variable it qualifies. A
      # source document may name it for the value instead; artoo's reader
      # does not carry that name, so it is not re-emitted.
      name = as.character(val$variable),
      label = .dx_chr(val, "label"),
      data_type = types$values,
      length = .dx_chr(val, "length"),
      significant_digits = .dx_chr(val, "significant_digits"),
      display_format = .dx_chr(val, "display_format"),
      sas_field_name = .dx_chr(val, "sas_field_name"),
      codelist_id = .dx_chr(val, "codelist_id"),
      comment_id = .dx_chr(val, "comment_id"),
      origin = .dx_chr(val, "origin"),
      source = .dx_chr(val, "source"),
      origin_description = .dx_chr(val, "origin_description"),
      origin_document_id = .dx_chr(val, "origin_document_id"),
      pages = .dx_chr(val, "pages"),
      page_type = .dx_chr(val, "page_type"),
      page_title = .dx_chr(val, "page_title"),
      alias_context = rep(NA_character_, nrow(val)),
      alias_name = rep(NA_character_, nrow(val)),
      value_list_id = rep(NA_character_, nrow(val)),
      stringsAsFactors = FALSE
    )
  }

  # A def:ValueListRef naming no def:ValueListDef is a dangling reference, and
  # the schema gate cannot see it: OIDs are odm:oidref, not xs:IDREF, so
  # libxml2 never resolves them. It reaches a reviewer as a Pinnacle 21
  # finding instead, which is exactly what minting every identifier up front
  # is supposed to make impossible.
  emitted <- unname(oids$value_list)
  orphan <- !.dx_blank(parent$value_list_id) &
    !(parent$value_list_id %in% emitted)
  if (any(orphan)) {
    where <- unique(paste0(var$dataset[orphan], ".", var$variable[orphan]))
    .artoo_abort(
      c(
        "{length(where)} variable{?s} point{?s/} at a value list the spec does not define.",
        "x" = "{.val {where}}.",
        "i" = "Add value-level rows, or clear {.code value_list_id}."
      ),
      kind = "define",
      call = call
    )
  }

  pool <- rbind(parent, child)
  .dx_pool_itemdefs(pool, call)
}

# One ItemDef per distinct OID. Two rows may share an OID only when they say
# the same thing; otherwise the document would silently describe one of them
# and misdescribe the other.
#' @noRd
.dx_pool_itemdefs <- function(pool, call = rlang::caller_env()) {
  if (!nrow(pool)) {
    return(pool)
  }
  key <- pool$oid
  dup <- key %in% key[duplicated(key)]
  if (any(dup)) {
    sig <- do.call(paste, c(pool[.dx_itemdef_fields], list(sep = "\r")))
    shared <- unique(key[duplicated(key)])
    conflicting <- shared[vapply(
      shared,
      function(k) length(unique(sig[key == k])) > 1L,
      logical(1)
    )]
    if (length(conflicting)) {
      .artoo_abort(
        c(
          "{length(conflicting)} ItemDef OID{?s} {?is/are} defined more than one way.",
          "x" = "{.val {conflicting}}.",
          "i" = "Define-XML allows one ItemDef per OID; give the rows distinct {.code itemoid} values, or make their definitions agree."
        ),
        kind = "define",
        call = call
      )
    }
  }
  pool[!duplicated(key), , drop = FALSE]
}

# Resolve ItemDef/@DataType for the value-level rows.
#
# Only one direction is live. artoo_spec() runs every variables$data_type
# through .parse_type(), which refuses a blank, and .dx_oids() has already
# refused a value-level row whose parent variable is absent -- so a parent
# always exists and always has a type. A value-level row that states none
# takes its parent's, which is what a workbook means when it leaves the cell
# empty on a row that only narrows the parent's codelist.
#' @noRd
.dx_resolve_datatypes <- function(spec, oids) {
  var <- spec@variables
  val <- spec@values
  vt <- .to_define_datatype(.dx_chr(var, "data_type"))
  if (is.null(val) || !nrow(val)) {
    return(list(variables = vt, values = character(0)))
  }
  lt <- .to_define_datatype(.dx_chr(val, "data_type"))
  from_parent <- .dx_get(.dx_map(oids$variable, vt), oids$value_parent)
  blank <- .dx_blank(lt)
  lt[blank] <- from_parent[blank]
  list(variables = vt, values = lt)
}

# ---- value lists ----------------------------------------------------------

# The where-clause foreign key on a value-level row. Two reader generations
# put it in two places: the Define-XML reader fills `where_clause_id`, while
# the workbook readers converge on `where_clause` (see .wc_from_values()).
# Only a value that names a DEFINED clause is treated as a key, so rendered
# display text is never emitted as a dangling reference.
#' @noRd
.dx_where_key <- function(val, i, known, call = rlang::caller_env()) {
  id <- .dx_chr(val, "where_clause_id")[[i]]
  txt <- .dx_chr(val, "where_clause")[[i]]
  for (candidate in c(id, txt)) {
    if (!.dx_blank(candidate) && trimws(candidate) %in% known) {
      return(trimws(candidate))
    }
  }
  if (.dx_blank(id) && .dx_blank(txt)) {
    return(NA_character_)
  }
  # A row that names a condition artoo cannot resolve must NOT be written
  # without one: a value-level definition with no def:WhereClauseRef applies
  # to every row of its parent variable, which is a different claim from the
  # one the spec made.
  named <- c(id, txt)
  named <- named[!.dx_blank(named)][[1]]
  ds <- .dx_chr(val, "dataset")[[i]]
  vr <- .dx_chr(val, "variable")[[i]]
  .artoo_abort(
    c(
      "Value-level row {i} ({.val {ds}}.{.val {vr}}) names a where clause the spec does not define.",
      "x" = "{.val {named}}.",
      "i" = "Add it to the {.code where_clauses} table, or clear the row's where clause."
    ),
    kind = "define",
    call = call
  )
}

#' @noRd
.dx_value_lists <- function(spec, oids, p, call = rlang::caller_env()) {
  val <- spec@values
  if (is.null(val) || !nrow(val)) {
    return(list())
  }
  known <- unique(as.character(spec@where_clauses$where_clause_id))
  vkey <- oids$value_parent
  # Groups in first-appearance order, so the output is stable under a stable
  # input rather than under the locale's collation.
  groups <- unique(vkey)
  lapply(groups, function(g) {
    rows <- which(vkey == g)
    rows <- rows[.dx_row_order(val[rows, , drop = FALSE])]
    .dx_node(
      "def:ValueListDef",
      attrs = .dx_attrs(OID = .dx_get(oids$value_list, g)),
      kids = list(
        ItemRef = lapply(rows, function(i) {
          wc <- .dx_where_key(val, i, known, call)
          .dx_node(
            "ItemRef",
            attrs = .dx_attrs(
              ItemOID = oids$value_item[[i]],
              OrderNumber = .dx_chr(val, "order")[[i]],
              Mandatory = .dx_yesno(
                .dx_lgl(val, "mandatory")[[i]],
                default = FALSE
              ),
              MethodOID = .dx_chr(val, "method_id")[[i]]
            ),
            kids = list(
              `def:WhereClauseRef` = if (is.na(wc)) {
                NULL
              } else {
                .dx_node(
                  "def:WhereClauseRef",
                  attrs = .dx_attrs(WhereClauseOID = wc)
                )
              }
            )
          )
        })
      )
    )
  })
}

# ---- where clauses --------------------------------------------------------

#' @noRd
.dx_where_clause_defs <- function(spec, oids, p, call = rlang::caller_env()) {
  wc <- spec@where_clauses
  if (!nrow(wc)) {
    return(list())
  }
  ids <- unique(as.character(wc$where_clause_id))
  lapply(ids, function(id) {
    rows <- wc[wc$where_clause_id == id, , drop = FALSE]
    checks <- unique(rows$check_order)
    checks <- checks[order(suppressWarnings(as.integer(checks)))]
    .dx_node(
      "def:WhereClauseDef",
      attrs = .dx_attrs(
        OID = id,
        "def:CommentOID" = .dx_one(.dx_chr(rows, "comment_id"))
      ),
      kids = list(
        RangeCheck = lapply(checks, function(k) {
          .dx_range_check(
            rows[rows$check_order %in% k, , drop = FALSE],
            id,
            oids,
            p,
            call
          )
        })
      )
    )
  })
}

# The ItemDef OID of a variable named without its dataset. NA when nothing
# defines it; an abort when more than one dataset does, because guessing
# would silently change which rows a value-level definition applies to.
#' @noRd
.dx_resolve_by_name <- function(map, variable, id, call = rlang::caller_env()) {
  if (.dx_blank(variable) || !length(map)) {
    return(NA_character_)
  }
  hit <- which(sub("^[^\r]*\r", "", names(map)) == trimws(variable))
  if (!length(hit)) {
    return(NA_character_)
  }
  found <- unique(unname(map[hit]))
  if (length(found) > 1L) {
    owners <- sub("\r.*$", "", names(map)[hit])
    .artoo_abort(
      c(
        "Where clause {.val {id}} names {.val {variable}} without a dataset.",
        "x" = "{length(owners)} datasets define it: {.val {owners}}.",
        "i" = "Set {.code dataset} on the where-clause row to say which."
      ),
      kind = "define",
      call = call
    )
  }
  found[[1]]
}

#' @noRd
.dx_range_check <- function(rc, id, oids, p, call = rlang::caller_env()) {
  item <- .dx_one(.dx_chr(rc, "itemoid"))
  if (.dx_blank(item)) {
    dataset <- .dx_one(.dx_chr(rc, "dataset"))
    variable <- .dx_one(.dx_chr(rc, "variable"))
    item <- .dx_get(oids$variable, .dx_key(dataset, variable))
    if (is.na(item)) {
      # A where clause can qualify a variable in a DIFFERENT dataset -- the
      # CDISC SDTM example conditions a VS value on DM.COUNTRY -- and the
      # free-text parser stamps the value-level row's own dataset onto every
      # condition, because at parse time there is no spec to check against.
      # Resolve by name when exactly one dataset defines it; refuse when
      # several do, rather than picking one and changing which rows the
      # definition selects.
      item <- .dx_resolve_by_name(oids$variable, variable, id, call)
    }
  }
  if (.dx_blank(item)) {
    .artoo_abort(
      c(
        "Where clause {.val {id}} names no variable.",
        "x" = "{.code RangeCheck/@def:ItemOID} is required, and the clause carries neither {.code itemoid} nor a dataset and variable that resolve to one.",
        "i" = "Set {.code dataset} and {.code variable} on the where-clause rows."
      ),
      kind = "define",
      call = call
    )
  }
  ord <- order(suppressWarnings(as.integer(rc$value_order)))
  vals <- as.character(rc$value)[ord]
  .dx_node(
    "RangeCheck",
    attrs = .dx_attrs(
      Comparator = .dx_enum(
        .dx_one(.dx_chr(rc, "comparator")),
        p$enum$comparator,
        "RangeCheck Comparator",
        call
      ),
      # SoftHard is required by ODM; a value-level where clause is always
      # Soft, which is what Define-XML constrains it to.
      SoftHard = {
        sh <- .dx_one(.dx_chr(rc, "soft_hard"))
        if (.dx_blank(sh)) {
          "Soft"
        } else {
          .dx_enum(sh, p$enum$soft_hard, "SoftHard", call)
        }
      },
      "def:ItemOID" = item
    ),
    kids = list(
      CheckValue = lapply(vals[!is.na(vals)], function(v) {
        .dx_node("CheckValue", text = v)
      })
    )
  )
}
