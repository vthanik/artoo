# define_lint.R — define_lint(): reference integrity of a Define-XML document.
#
# This is the half of correctness XML Schema cannot express. A schema checks
# that every element is shaped right; it has no way to say "this OID reference
# resolves" or "something points at this definition". Both classes of defect
# produce a document that validates cleanly and is still wrong:
#
#   * a DANGLING reference points at a definition that does not exist. The
#     reviewer's tool silently shows nothing where metadata should be.
#   * an ORPHAN definition is one nothing points at. A def:ValueListDef with
#     no def:ValueListRef is the sharpest case: every value-level definition
#     in it renders nowhere, and the file still validates.
#
# The design is one collection pass over every reference site, then a
# symmetric difference per kind. Findings are DIRECTIONAL -- dangling and
# orphan are separate condition ids -- because they have different causes and
# different severities.
#
# Two carve-outs exist purely to stop false positives, and both are load
# bearing on real submissions:
#
#   * a CodeList backed by an ExternalCodeList (MedDRA, WHODrug, ISO 3166)
#     is a dictionary reference, not an enumerable list. It legitimately has
#     no CodeListRef pointing at it.
#   * a CodeList reached through ItemRef/@RoleCodeListOID is referenced, just
#     not through CodeListRef.
#
# Without those, every real AE or CM define fires spurious orphan findings.

# ---- the reference graph, as data ---------------------------------------

# Where definitions come from: element local-name -> the attribute carrying
# the OID, and the kind other sites resolve against.
.define_def_sites <- list(
  list(element = "ItemGroupDef", attr = "OID", kind = "item_group"),
  list(element = "ItemDef", attr = "OID", kind = "item"),
  list(element = "CodeList", attr = "OID", kind = "codelist"),
  list(element = "MethodDef", attr = "OID", kind = "method"),
  list(element = "CommentDef", attr = "OID", kind = "comment"),
  list(element = "ValueListDef", attr = "OID", kind = "value_list"),
  list(element = "WhereClauseDef", attr = "OID", kind = "where_clause"),
  list(element = "leaf", attr = "ID", kind = "leaf"),
  list(element = "Standard", attr = "OID", kind = "standard")
)

# Where references come from. `kind` is the definition kind the reference
# resolves against; `finding` is the condition id raised when it does not.
# Several sites resolve against the same kind but get their own finding id,
# because "an analysis dataset names a missing dataset" and "an ItemRef names
# a missing variable" are different problems to the person fixing them.
#
# `counts` is FALSE where a site should NOT mark its target as referenced --
# see .define_ref_sites below for the one case that matters.
.define_ref_sites <- list(
  list(
    element = "ItemRef",
    attr = "ItemOID",
    kind = "item",
    finding = "define_dangling_item"
  ),
  list(
    element = "AnalysisVariable",
    attr = "ItemOID",
    kind = "item",
    finding = "define_dangling_item"
  ),
  list(
    element = "RangeCheck",
    attr = "ItemOID",
    kind = "item",
    finding = "define_dangling_item"
  ),
  list(
    element = "AnalysisResult",
    attr = "ParameterOID",
    kind = "item",
    finding = "define_dangling_arm_parameter"
  ),
  list(
    element = "CodeListRef",
    attr = "CodeListOID",
    kind = "codelist",
    finding = "define_dangling_codelist"
  ),
  list(
    element = "ItemRef",
    attr = "RoleCodeListOID",
    kind = "codelist",
    finding = "define_dangling_codelist"
  ),
  list(
    element = "ItemRef",
    attr = "MethodOID",
    kind = "method",
    finding = "define_dangling_method"
  ),
  list(
    element = "ValueListRef",
    attr = "ValueListOID",
    kind = "value_list",
    finding = "define_dangling_value_list"
  ),
  list(
    element = "WhereClauseRef",
    attr = "WhereClauseOID",
    kind = "where_clause",
    finding = "define_dangling_where_clause"
  ),
  list(
    element = "DocumentRef",
    attr = "leafID",
    kind = "leaf",
    finding = "define_dangling_leaf"
  ),
  list(
    element = "ItemGroupDef",
    attr = "ArchiveLocationID",
    kind = "leaf",
    finding = "define_dangling_archive_location"
  ),
  list(
    element = "AnalysisDataset",
    attr = "ItemGroupOID",
    kind = "item_group",
    finding = "define_dangling_arm_item_group"
  )
)

# def:CommentOID and def:StandardOID hang off many different elements, so they
# are collected by attribute across the whole MetaDataVersion rather than by
# element.
.define_loose_refs <- list(
  list(
    attr = "CommentOID",
    kind = "comment",
    finding = "define_dangling_comment"
  ),
  list(
    attr = "StandardOID",
    kind = "standard",
    finding = "define_dangling_standard"
  )
)

# Which definition kinds get an orphan check, and under which condition id.
# item_group is absent deliberately: an ItemGroupDef is a top-level dataset
# definition and is not required to be referenced by anything.
.define_orphan_kinds <- list(
  list(kind = "item", finding = "define_orphan_item"),
  list(kind = "codelist", finding = "define_orphan_codelist"),
  list(kind = "method", finding = "define_orphan_method"),
  list(kind = "comment", finding = "define_orphan_comment"),
  list(kind = "value_list", finding = "define_orphan_value_list"),
  list(kind = "where_clause", finding = "define_orphan_where_clause"),
  list(kind = "leaf", finding = "define_orphan_leaf"),
  list(kind = "standard", finding = "define_orphan_standard")
)

# ---- collection ---------------------------------------------------------

# Every OID defined in the document, as kind -> character vector.
#' @noRd
.define_collect_defs <- function(mdv) {
  out <- list()
  for (site in .define_def_sites) {
    nodes <- .dx_find_all(mdv, site$element)
    ids <- if (length(nodes)) {
      vapply(nodes, .dx_attr, character(1), name = site$attr)
    } else {
      character(0)
    }
    ids <- ids[!is.na(ids) & nzchar(ids)]
    out[[site$kind]] <- c(out[[site$kind]], ids)
  }
  out
}

# Every OID reference, as a data frame of (kind, finding, value, context).
# `context` names the element the reference sits on, so a finding can say
# where to look.
#' @noRd
.define_collect_refs <- function(mdv) {
  rows <- list()

  add <- function(values, kind, finding, context) {
    values <- values[!is.na(values) & nzchar(values)]
    if (!length(values)) {
      return(invisible(NULL))
    }
    rows[[length(rows) + 1L]] <<- data.frame(
      kind = kind,
      finding = finding,
      value = values,
      context = context,
      stringsAsFactors = FALSE
    )
    invisible(NULL)
  }

  for (site in .define_ref_sites) {
    nodes <- .dx_find_all(mdv, site$element)
    if (!length(nodes)) {
      next
    }
    vals <- vapply(nodes, .dx_attr, character(1), name = site$attr)
    add(vals, site$kind, site$finding, site$element)
  }

  # Attribute-driven references, which appear on many element types.
  all_nodes <- xml2::xml_find_all(mdv, ".//*")
  for (site in .define_loose_refs) {
    vals <- vapply(all_nodes, .dx_attr, character(1), name = site$attr)
    keep <- !is.na(vals) & nzchar(vals)
    if (any(keep)) {
      add(
        vals[keep],
        site$kind,
        site$finding,
        xml2::xml_name(all_nodes[keep])
      )
    }
  }

  if (!length(rows)) {
    return(data.frame(
      kind = character(0),
      finding = character(0),
      value = character(0),
      context = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

# CodeList OIDs that are exempt from the orphan check: those backed by an
# external dictionary rather than an enumerable term list.
#' @noRd
.define_external_codelists <- function(mdv) {
  nodes <- .dx_find_all(mdv, "CodeList")
  if (!length(nodes)) {
    return(character(0))
  }
  external <- vapply(
    nodes,
    function(n) !is.na(.dx_child(n, "ExternalCodeList")),
    logical(1)
  )
  ids <- vapply(nodes[external], .dx_attr, character(1), name = "OID")
  ids[!is.na(ids) & nzchar(ids)]
}

#' Check the reference integrity of a Define-XML document
#'
#' Reports OID references that resolve to nothing, and definitions that nothing
#' references. Neither is expressible in XML Schema, so a document can pass
#' [validate_define()] and still fail here.
#'
#' @details
#' **Findings are directional.** A dangling reference and an orphan definition
#' have different causes and different consequences, so they are separate
#' conditions. Dangling references are errors. Orphans are warnings, except for
#' an orphaned value list: a `def:ValueListDef` that no `def:ValueListRef`
#' points at means every value-level definition it holds renders nowhere, which
#' is a silent loss of submission metadata rather than untidiness.
#'
#' **Two exemptions prevent false positives.** A `CodeList` backed by an
#' `ExternalCodeList` (MedDRA, WHODrug, ISO 3166) is a dictionary reference and
#' is not expected to be referenced by a `CodeListRef`. A `CodeList` reached
#' through `ItemRef/@RoleCodeListOID` counts as referenced. Without these,
#' every real adverse-event or medication define reports spurious orphans.
#'
#' @param path *Define-XML document to check.* `<character(1)>: required`.
#'
#' @return *An `artoo_check` object.* Its `@findings` data frame has columns
#'   `check`, `dimension`, `severity`, `dataset`, `variable`, `message`, and is
#'   empty when every reference resolves and every definition is used.
#'
#' @examples
#' # ---- Example 1: a sound document ----
#' #
#' # The bundled minimal example resolves cleanly, so the findings table is
#' # empty and the summary counts what was inspected.
#' minimal <- system.file("extdata", "define-minimal.xml", package = "artoo")
#' report <- define_lint(minimal)
#' nrow(report@findings)
#' report@summary$n_definitions
#'
#' # ---- Example 2: a reference that resolves to nothing ----
#' #
#' # Point a variable's codelist reference at an OID no CodeList defines. The
#' # document still passes schema validation; only the lint sees it.
#' broken <- tempfile(fileext = ".xml")
#' writeLines(
#'   sub('CodeListOID="CL.SEX"', 'CodeListOID="CL.MISSING"',
#'     readLines(minimal),
#'     fixed = TRUE
#'   ),
#'   broken
#' )
#' validate_define(broken)@summary$valid
#' define_lint(broken)@findings[, c("check", "severity", "message")]
#'
#' @seealso
#' **Validate first:** [validate_define()] for schema conformance, which this
#' complements rather than repeats.
#'
#' @export
define_lint <- function(path) {
  call <- rlang::current_env()
  rlang::check_installed("xml2", reason = "to lint Define-XML documents.")
  .check_path(path, call = call)

  if (!file.exists(path)) {
    .artoo_abort(
      c(
        "{.path {path}} does not exist.",
        "i" = "Check the path, or pass the file artoo should lint."
      ),
      kind = "input",
      call = call
    )
  }
  doc <- tryCatch(
    xml2::read_xml(path),
    error = function(e) {
      msg <- .safe_msg(e)
      .artoo_abort(
        c("{.path {path}} is not parseable XML.", "x" = "{msg}"),
        kind = "input",
        call = call
      )
    }
  )
  mdv <- xml2::xml_find_first(doc, "//*[local-name()='MetaDataVersion']")
  if (is.na(mdv)) {
    .artoo_abort(
      c(
        "{.path {path}} is not a Define-XML document.",
        "x" = "It has no MetaDataVersion element."
      ),
      kind = "input",
      call = call
    )
  }

  defs <- .define_collect_defs(mdv)
  refs <- .define_collect_refs(mdv)
  external <- .define_external_codelists(mdv)

  parts <- list(
    .define_dangling(defs, refs),
    .define_orphans(defs, refs, external),
    .define_origin_findings(mdv)
  )

  artoo_check_class(
    findings = .bind_findings(parts),
    scope = character(0),
    study = basename(path),
    summary = list(
      n_definitions = sum(lengths(defs)),
      n_references = nrow(refs),
      n_external_codelists = length(external)
    )
  )
}

# References whose target is not defined.
#' @noRd
.define_dangling <- function(defs, refs) {
  if (!nrow(refs)) {
    return(NULL)
  }
  out <- list()
  for (fid in unique(refs$finding)) {
    sub <- refs[refs$finding == fid, , drop = FALSE]
    known <- defs[[sub$kind[1]]] %||% character(0)
    bad <- sub[!sub$value %in% known, , drop = FALSE]
    if (!nrow(bad)) {
      next
    }
    bad <- bad[!duplicated(bad$value), , drop = FALSE]
    out[[length(out) + 1L]] <- .finding(
      fid,
      dataset = NA_character_,
      variable = NA_character_,
      message = sprintf(
        "%s on %s references %s, which is not defined.",
        .define_ref_label(bad$kind),
        bad$context,
        bad$value
      )
    )
  }
  .bind_findings(out)
}

# Definitions nothing references.
#' @noRd
.define_orphans <- function(defs, refs, external) {
  out <- list()
  for (spec in .define_orphan_kinds) {
    defined <- unique(defs[[spec$kind]] %||% character(0))
    if (!length(defined)) {
      next
    }
    used <- refs$value[refs$kind == spec$kind]
    unused <- setdiff(defined, used)
    if (identical(spec$kind, "codelist")) {
      # A dictionary-backed codelist is referenced by its dictionary, not by
      # a CodeListRef.
      unused <- setdiff(unused, external)
    }
    if (!length(unused)) {
      next
    }
    out[[length(out) + 1L]] <- .finding(
      spec$finding,
      dataset = NA_character_,
      variable = NA_character_,
      message = sprintf(
        "%s %s is defined but nothing references it.",
        .define_noun(spec$kind),
        unused
      )
    )
  }
  .bind_findings(out)
}

# Origin inheritance, both directions.
#
# def:Origin is schema-OPTIONAL, so "nothing anywhere carries an Origin" is
# expressible in a perfectly valid document and only a lint can see it. The
# rule is not "every ItemDef needs an Origin" -- that would fire on every
# variable with value-level metadata:
#
#   * a PARENT variable may omit Origin when every one of its value-level
#     items supplies one, because the value level is where the real answer
#     lives (a lab result collected one way and derived another).
#   * a VALUE-LEVEL item may omit Origin when its parent supplies one, and
#     inherits it.
#
# Only "neither level has one" is a finding. Getting this wrong reports the
# official CDISC examples as defective, which is how the half-implemented
# version of this check was caught.
#' @noRd
.define_origin_findings <- function(mdv) {
  items <- .dx_find_all(mdv, "ItemDef")
  if (!length(items)) {
    return(NULL)
  }
  oids <- vapply(items, .dx_attr, character(1), name = "OID")
  has_origin <- vapply(
    items,
    function(n) !is.na(.dx_child(n, "Origin")),
    logical(1)
  )
  names(has_origin) <- oids

  # ValueListDef OID -> the ItemOIDs it contains.
  vls <- .dx_find_all(mdv, "ValueListDef")
  vl_items <- list()
  for (vl in vls) {
    oid <- .dx_attr(vl, "OID")
    refs <- xml2::xml_find_all(vl, "./*[local-name()='ItemRef']")
    if (!is.na(oid) && length(refs)) {
      vl_items[[oid]] <- xml2::xml_attr(refs, "ItemOID")
    }
  }
  # Every item that is a value-level item of some list.
  all_vl_items <- unlist(vl_items, use.names = FALSE) %||% character(0)

  flagged <- character(0)
  for (i in seq_along(items)) {
    oid <- oids[[i]]
    if (is.na(oid) || !nzchar(oid) || has_origin[[i]]) {
      next
    }
    vlref <- .dx_child(items[[i]], "ValueListRef")
    if (!is.na(vlref)) {
      # A parent: exempt when every value-level item supplies an Origin.
      kids <- vl_items[[xml2::xml_attr(vlref, "ValueListOID")]] %||%
        character(0)
      covered <- length(kids) > 0 &&
        all(vapply(kids, function(k) isTRUE(has_origin[[k]]), logical(1)))
      if (covered) {
        next
      }
    }
    if (oid %in% all_vl_items) {
      # A value-level item: exempt when its parent supplies an Origin. Find
      # the parent by walking back through the value list that holds it.
      owner <- names(vl_items)[vapply(
        vl_items,
        function(v) oid %in% v,
        logical(1)
      )]
      parent_has <- FALSE
      for (o in owner) {
        pref <- .dx_find_all(mdv, "ValueListRef")
        for (pr in pref) {
          if (identical(xml2::xml_attr(pr, "ValueListOID"), o)) {
            pid <- .dx_attr(xml2::xml_parent(pr), "OID")
            if (!is.na(pid) && isTRUE(has_origin[[pid]])) {
              parent_has <- TRUE
            }
          }
        }
      }
      if (parent_has) {
        next
      }
    }
    flagged <- c(flagged, oid)
  }

  if (!length(flagged)) {
    return(NULL)
  }
  .finding(
    "define_missing_origin",
    dataset = NA_character_,
    variable = NA_character_,
    message = sprintf(
      "Variable %s carries no Origin, and neither do its value-level items.",
      flagged
    )
  )
}

# Human-readable labels, so a finding reads as prose rather than as an
# internal kind name. Dangling messages lead with the reference phrase,
# orphan messages with the bare noun, so each sentence reads naturally.
#' @noRd
.define_ref_label <- function(kind) {
  labels <- c(
    item = "A variable reference",
    item_group = "A dataset reference",
    codelist = "A codelist reference",
    method = "A method reference",
    comment = "A comment reference",
    value_list = "A value list reference",
    where_clause = "A where clause reference",
    leaf = "A document reference",
    standard = "A standard reference"
  )
  out <- unname(labels[kind])
  ifelse(is.na(out), kind, out)
}

#' @noRd
.define_noun <- function(kind) {
  nouns <- c(
    item = "Variable",
    item_group = "Dataset",
    codelist = "Codelist",
    method = "Method",
    comment = "Comment",
    value_list = "Value list",
    where_clause = "Where clause",
    leaf = "Document",
    standard = "Standard"
  )
  out <- unname(nouns[kind])
  ifelse(is.na(out), kind, out)
}
