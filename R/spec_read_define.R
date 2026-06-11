# spec_read_define.R -- read_spec() on a native Define-XML v2.x document.
#
# Maps the CDISC Define-XML 2.0/2.1 metadata model onto the vport_spec slots
# (the slots are already Define-shaped, so the walk is mostly mechanical):
#   ItemGroupDef            -> datasets (keys derived from ItemRef KeySequence)
#   ItemRef + ItemDef       -> variables
#   CodeList                -> codelists (def:ExtendedValue -> extended);
#                              an ExternalCodeList (MedDRA, ISO-3166) is a
#                              dictionary, not an enumerable membership list,
#                              so it and its references are dropped
#   MethodDef               -> methods
#   def:CommentDef          -> comments
#   def:leaf                -> documents
#   def:ValueListDef (+ def:WhereClauseDef) -> values
# Grounded against the official CDISC Define-XML 2.1.0 SDTM example.
# Define-XML v1.0 (the 2005 standard) is a different model and is refused
# with guidance. Requires the lightweight `xml2` (Suggests).

# Namespace-agnostic helpers: Define files vary their prefix declarations,
# so every XPath matches on local-name().
#' @noRd
.dx_find_all <- function(node, name) {
  xml2::xml_find_all(node, sprintf(".//*[local-name()='%s']", name))
}
#' @noRd
.dx_child <- function(node, name) {
  xml2::xml_find_first(node, sprintf("./*[local-name()='%s']", name))
}
#' @noRd
.dx_attr <- function(node, name) {
  # xml2 exposes a namespaced attribute as "def:Name" etc.; try the bare
  # local name first, then any prefixarised variant.
  v <- xml2::xml_attr(node, name)
  if (!is.na(v)) {
    return(v)
  }
  attrs <- xml2::xml_attrs(node)
  hit <- grepl(paste0("(^|:)", name, "$"), names(attrs))
  if (any(hit)) unname(attrs[hit][1]) else NA_character_
}
# Description/TranslatedText (or Decode/TranslatedText) under a node.
#' @noRd
.dx_text <- function(node, wrapper = "Description") {
  d <- .dx_child(node, wrapper)
  if (is.na(d)) {
    return(NA_character_)
  }
  t <- .dx_child(d, "TranslatedText")
  if (is.na(t)) NA_character_ else trimws(xml2::xml_text(t))
}
#' @noRd
.dx_int <- function(x) {
  suppressWarnings(as.integer(x))
}

#' @noRd
.read_spec_define <- function(
  path,
  scope_datasets = NULL,
  on_duplicate = "error",
  call = rlang::caller_env()
) {
  rlang::check_installed("xml2", reason = "to read Define-XML specs.")
  doc <- tryCatch(
    xml2::read_xml(path),
    error = function(e) {
      msg <- .safe_msg(e)
      cli::cli_abort(
        c(
          "{.path {path}} is not parseable XML.",
          "x" = "{msg}"
        ),
        class = "vport_error_input",
        call = call
      )
    }
  )
  ns_uris <- unlist(xml2::xml_ns(doc))
  if (any(grepl("cdisc.org/ns/def/v1", ns_uris, fixed = FALSE))) {
    cli::cli_abort(
      c(
        "{.path {path}} is a Define-XML v1.0 document.",
        "x" = "vport reads Define-XML 2.0 and 2.1.",
        "i" = "Re-export the define from a 2.x-capable tool."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  mdv <- xml2::xml_find_first(doc, "//*[local-name()='MetaDataVersion']")
  if (is.na(mdv) || !any(grepl("cdisc.org/ns/def/v2", ns_uris))) {
    cli::cli_abort(
      c(
        "{.path {path}} is not a Define-XML document.",
        "x" = "No MetaDataVersion in the Define-XML 2.x namespaces was found."
      ),
      class = "vport_error_input",
      call = call
    )
  }

  # ---- study -----------------------------------------------------------
  study_name <- xml2::xml_text(
    xml2::xml_find_first(doc, "//*[local-name()='StudyName']")
  )
  protocol <- xml2::xml_text(
    xml2::xml_find_first(doc, "//*[local-name()='ProtocolName']")
  )
  standards <- .dx_find_all(mdv, "Standard")
  standard <- if (length(standards)) {
    paste(
      xml2::xml_attr(standards[[1]], "Name"),
      xml2::xml_attr(standards[[1]], "Version")
    )
  } else {
    # Define 2.0 records the standard on the MetaDataVersion itself.
    paste(
      .dx_attr(mdv, "StandardName"),
      .dx_attr(mdv, "StandardVersion")
    )
  }
  study <- data.frame(
    study_name = study_name,
    protocol_name = protocol,
    standard = standard,
    define_version = .dx_attr(mdv, "DefineVersion"),
    stringsAsFactors = FALSE
  )

  # ---- ItemDefs (OID -> attributes), external codelists ------------------
  cl_nodes <- .dx_find_all(mdv, "CodeList")
  cl_oids <- xml2::xml_attr(cl_nodes, "OID")
  external <- vapply(
    cl_nodes,
    function(n) !is.na(.dx_child(n, "ExternalCodeList")),
    logical(1)
  )
  external_oids <- cl_oids[external]

  item_nodes <- .dx_find_all(mdv, "ItemDef")
  items <- lapply(item_nodes, function(n) {
    clref <- .dx_child(n, "CodeListRef")
    clid <- if (is.na(clref)) {
      NA_character_
    } else {
      xml2::xml_attr(clref, "CodeListOID")
    }
    if (!is.na(clid) && clid %in% external_oids) {
      clid <- NA_character_ # dictionaries are not membership lists
    }
    origin <- .dx_child(n, "Origin")
    vlref <- .dx_child(n, "ValueListRef")
    list(
      oid = xml2::xml_attr(n, "OID"),
      name = xml2::xml_attr(n, "Name"),
      data_type = xml2::xml_attr(n, "DataType"),
      length = .dx_int(xml2::xml_attr(n, "Length")),
      significant_digits = .dx_int(xml2::xml_attr(n, "SignificantDigits")),
      display_format = .dx_attr(n, "DisplayFormat"),
      label = .dx_text(n),
      codelist_id = clid,
      comment_id = .dx_attr(n, "CommentOID"),
      origin = if (is.na(origin)) {
        NA_character_
      } else {
        xml2::xml_attr(origin, "Type")
      },
      value_list = if (is.na(vlref)) {
        NA_character_
      } else {
        xml2::xml_attr(vlref, "ValueListOID")
      }
    )
  })
  names(items) <- vapply(items, function(i) i$oid, character(1))

  # ---- ItemGroupDefs -> datasets + variables -----------------------------
  ig_nodes <- .dx_find_all(mdv, "ItemGroupDef")
  if (!length(ig_nodes)) {
    cli::cli_abort(
      c(
        "{.path {path}} defines no datasets.",
        "x" = "The MetaDataVersion has no ItemGroupDef."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  ds_rows <- list()
  var_rows <- list()
  vl_owner <- list() # ValueListOID -> c(dataset, variable)
  for (ig in ig_nodes) {
    ds_name <- xml2::xml_attr(ig, "Name")
    cls <- .dx_child(ig, "Class")
    refs <- xml2::xml_find_all(ig, "./*[local-name()='ItemRef']")
    ref_oid <- xml2::xml_attr(refs, "ItemOID")
    ks <- .dx_int(xml2::xml_attr(refs, "KeySequence"))
    keyed <- !is.na(ks)
    key_names <- vapply(
      ref_oid[keyed][order(ks[keyed])],
      function(o) items[[o]]$name %||% NA_character_,
      character(1)
    )
    ds_rows[[length(ds_rows) + 1L]] <- data.frame(
      dataset = ds_name,
      label = .dx_text(ig),
      class = if (is.na(cls)) NA_character_ else xml2::xml_attr(cls, "Name"),
      structure = .dx_attr(ig, "Structure"),
      keys = if (length(key_names)) {
        paste(key_names, collapse = " ")
      } else {
        NA_character_
      },
      comment_id = .dx_attr(ig, "CommentOID"),
      stringsAsFactors = FALSE
    )
    for (j in seq_along(refs)) {
      it <- items[[ref_oid[j]]]
      if (is.null(it)) {
        cli::cli_abort(
          c(
            "{.path {path}} is inconsistent.",
            "x" = "ItemRef {.val {ref_oid[j]}} has no ItemDef."
          ),
          class = "vport_error_input",
          call = call
        )
      }
      if (!is.na(it$value_list)) {
        vl_owner[[it$value_list]] <- c(ds_name, it$name)
      }
      var_rows[[length(var_rows) + 1L]] <- data.frame(
        dataset = ds_name,
        variable = it$name,
        itemoid = it$oid,
        label = it$label,
        data_type = it$data_type,
        length = it$length,
        display_format = it$display_format,
        key_sequence = ks[j],
        order = .dx_int(xml2::xml_attr(refs[[j]], "OrderNumber")),
        codelist_id = it$codelist_id,
        method_id = xml2::xml_attr(refs[[j]], "MethodOID"),
        comment_id = it$comment_id,
        mandatory = identical(xml2::xml_attr(refs[[j]], "Mandatory"), "Yes"),
        significant_digits = it$significant_digits,
        origin = it$origin,
        stringsAsFactors = FALSE
      )
    }
  }
  datasets <- do.call(rbind, ds_rows)
  variables <- do.call(rbind, var_rows)

  # ---- codelists ---------------------------------------------------------
  cl_rows <- list()
  for (k in seq_along(cl_nodes)) {
    if (external[k]) {
      next
    }
    n <- cl_nodes[[k]]
    terms <- xml2::xml_find_all(
      n,
      "./*[local-name()='CodeListItem' or local-name()='EnumeratedItem']"
    )
    if (!length(terms)) {
      next
    }
    cl_rows[[length(cl_rows) + 1L]] <- data.frame(
      codelist_id = cl_oids[k],
      term = xml2::xml_attr(terms, "CodedValue"),
      decode = vapply(terms, .dx_text, character(1), wrapper = "Decode"),
      order = .dx_int(xml2::xml_attr(terms, "OrderNumber")),
      extended = vapply(
        terms,
        function(t) identical(.dx_attr(t, "ExtendedValue"), "Yes"),
        logical(1)
      ),
      stringsAsFactors = FALSE
    )
  }
  codelists <- if (length(cl_rows)) do.call(rbind, cl_rows) else NULL
  # Keep referential integrity: a variable whose codelist carries no
  # enumerable terms (and so was dropped) loses the reference.
  if (!is.null(codelists)) {
    gone <- !is.na(variables$codelist_id) &
      !(variables$codelist_id %in% codelists$codelist_id)
    variables$codelist_id[gone] <- NA_character_
  } else {
    variables$codelist_id <- NA_character_
  }

  # ---- methods / comments / documents ------------------------------------
  doc_ref <- function(n) {
    r <- .dx_child(n, "DocumentRef")
    if (is.na(r)) {
      return(c(NA_character_, NA_character_))
    }
    pg <- .dx_child(r, "PDFPageRef")
    c(
      xml2::xml_attr(r, "leafID"),
      if (is.na(pg)) NA_character_ else xml2::xml_attr(pg, "PageRefs")
    )
  }
  md_nodes <- .dx_find_all(mdv, "MethodDef")
  methods <- if (length(md_nodes)) {
    refs <- lapply(md_nodes, doc_ref)
    data.frame(
      method_id = xml2::xml_attr(md_nodes, "OID"),
      name = xml2::xml_attr(md_nodes, "Name"),
      type = xml2::xml_attr(md_nodes, "Type"),
      description = vapply(md_nodes, .dx_text, character(1)),
      document_id = vapply(refs, `[`, character(1), 1L),
      pages = vapply(refs, `[`, character(1), 2L),
      stringsAsFactors = FALSE
    )
  } else {
    NULL
  }
  cm_nodes <- .dx_find_all(mdv, "CommentDef")
  comments <- if (length(cm_nodes)) {
    refs <- lapply(cm_nodes, doc_ref)
    data.frame(
      comment_id = xml2::xml_attr(cm_nodes, "OID"),
      description = vapply(cm_nodes, .dx_text, character(1)),
      document_id = vapply(refs, `[`, character(1), 1L),
      pages = vapply(refs, `[`, character(1), 2L),
      stringsAsFactors = FALSE
    )
  } else {
    NULL
  }
  leaf_nodes <- .dx_find_all(mdv, "leaf")
  documents <- if (length(leaf_nodes)) {
    d <- data.frame(
      document_id = xml2::xml_attr(leaf_nodes, "ID"),
      title = vapply(
        leaf_nodes,
        function(n) {
          t <- .dx_child(n, "title")
          if (is.na(t)) NA_character_ else trimws(xml2::xml_text(t))
        },
        character(1)
      ),
      href = vapply(leaf_nodes, .dx_attr, character(1), name = "href"),
      stringsAsFactors = FALSE
    )
    d[!duplicated(d$document_id), , drop = FALSE]
  } else {
    NULL
  }

  # ---- value-level metadata ----------------------------------------------
  values <- .dx_values(mdv, items, vl_owner)

  # Scope before the duplicate guard (a problem confined to another
  # ItemGroup never blocks this read), then resolve duplicates by policy.
  scoped <- .spec_scope_tables(
    list(datasets = datasets, variables = variables, values = values),
    scope_datasets,
    call
  )
  variables <- .resolve_duplicate_variables(
    scoped$variables,
    on_duplicate,
    where = "The variables table",
    call = call
  )

  vport_spec(
    datasets = scoped$datasets,
    variables = variables,
    codelists = codelists,
    study = study,
    values = scoped$values,
    methods = methods,
    comments = comments,
    documents = documents
  )
}

# ValueListDefs -> one row per value-level ItemRef, with the owning
# dataset/variable (from the parent ItemDef's def:ValueListRef) and the
# WhereClauseDef rendered as readable "VAR IN (a, b)" text.
#' @noRd
.dx_values <- function(mdv, items, vl_owner) {
  vl_nodes <- .dx_find_all(mdv, "ValueListDef")
  if (!length(vl_nodes)) {
    return(NULL)
  }
  wc_nodes <- .dx_find_all(mdv, "WhereClauseDef")
  wc_text <- vapply(
    wc_nodes,
    function(w) {
      checks <- xml2::xml_find_all(w, "./*[local-name()='RangeCheck']")
      paste(
        vapply(
          checks,
          function(rc) {
            target <- .dx_attr(rc, "ItemOID")
            var <- if (!is.null(items[[target]])) {
              items[[target]]$name
            } else {
              target
            }
            vals <- xml2::xml_text(xml2::xml_find_all(
              rc,
              "./*[local-name()='CheckValue']"
            ))
            sprintf(
              "%s %s (%s)",
              var,
              xml2::xml_attr(rc, "Comparator"),
              paste(vals, collapse = ", ")
            )
          },
          character(1)
        ),
        collapse = " AND "
      )
    },
    character(1)
  )
  names(wc_text) <- xml2::xml_attr(wc_nodes, "OID")

  rows <- list()
  for (vl in vl_nodes) {
    oid <- xml2::xml_attr(vl, "OID")
    owner <- vl_owner[[oid]] %||% c(NA_character_, NA_character_)
    refs <- xml2::xml_find_all(vl, "./*[local-name()='ItemRef']")
    for (r in refs) {
      it <- items[[xml2::xml_attr(r, "ItemOID")]]
      wcr <- .dx_child(r, "WhereClauseRef")
      wcid <- if (is.na(wcr)) {
        NA_character_
      } else {
        xml2::xml_attr(wcr, "WhereClauseOID")
      }
      rows[[length(rows) + 1L]] <- data.frame(
        dataset = owner[1],
        variable = owner[2],
        where_clause = if (!is.na(wcid)) {
          unname(wc_text[wcid]) %||% NA_character_
        } else {
          NA_character_
        },
        itemoid = if (is.null(it)) NA_character_ else it$oid,
        label = if (is.null(it)) NA_character_ else it$label,
        data_type = if (is.null(it)) NA_character_ else it$data_type,
        length = if (is.null(it)) NA_integer_ else it$length,
        codelist_id = if (is.null(it)) NA_character_ else it$codelist_id,
        method_id = xml2::xml_attr(r, "MethodOID"),
        order = .dx_int(xml2::xml_attr(r, "OrderNumber")),
        mandatory = identical(xml2::xml_attr(r, "Mandatory"), "Yes"),
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}
