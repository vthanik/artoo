# spec_read_define.R — read_spec() on a native Define-XML v2.x document.
#
# Maps the CDISC Define-XML 2.0/2.1 metadata model onto the artoo_spec slots
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

# A Define-XML Yes/No attribute as a logical. NA when the attribute is absent,
# which is meaningfully different from "No" for def:HasNoData (odm:YesOnly,
# where the attribute's presence IS the assertion).
# A def:PDFPageRef states its pages as EITHER a @PageRefs list or a
# @FirstPage/@LastPage range. Reading only the list dropped every range
# silently -- the CDISC 2.0 SDTM example annotates most of its CRF that way.
#
# Both collapse into the one `pages` column, a range as "4-5". That is
# unambiguous where it matters: a range is only legal for Type="PhysicalRef",
# whose @PageRefs is a space-separated list of integers and so can never
# contain a hyphen. A lone @FirstPage with no @LastPage is read as that page.
#' @noRd
.dx_page_refs <- function(pg) {
  refs <- .dx_attr(pg, "PageRefs")
  if (!is.na(refs)) {
    return(refs)
  }
  first <- .dx_attr(pg, "FirstPage")
  if (is.na(first)) {
    return(NA_character_)
  }
  last <- .dx_attr(pg, "LastPage")
  if (is.na(last)) first else paste0(first, "-", last)
}

#' @noRd
.dx_yn <- function(x) {
  ifelse(is.na(x), NA, toupper(x) == "YES")
}

# The first Alias with the given Context under `node`, as c(context, name).
#' @noRd
.dx_alias <- function(node, context = NULL) {
  al <- xml2::xml_find_all(node, "./*[local-name()='Alias']")
  if (!length(al)) {
    return(c(NA_character_, NA_character_))
  }
  ctx <- vapply(al, .dx_attr, character(1), name = "Context")
  nm <- vapply(al, .dx_attr, character(1), name = "Name")
  hit <- if (is.null(context)) 1L else which(ctx == context)[1]
  if (is.na(hit)) {
    return(c(NA_character_, NA_character_))
  }
  c(ctx[hit], nm[hit])
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
      .artoo_abort(
        c(
          "{.path {path}} is not parseable XML.",
          "x" = "{msg}"
        ),
        kind = "input",
        call = call
      )
    }
  )
  ns_uris <- unlist(xml2::xml_ns(doc))
  if (any(grepl("cdisc.org/ns/def/v1", ns_uris, fixed = FALSE))) {
    .artoo_abort(
      c(
        "{.path {path}} is a Define-XML v1.0 document.",
        "x" = "artoo reads Define-XML 2.0 and 2.1.",
        "i" = "Re-export the define from a 2.x-capable tool."
      ),
      kind = "input",
      call = call
    )
  }
  mdv <- xml2::xml_find_first(doc, "//*[local-name()='MetaDataVersion']")
  if (is.na(mdv) || !any(grepl("cdisc.org/ns/def/v2", ns_uris))) {
    .artoo_abort(
      c(
        "{.path {path}} is not a Define-XML document.",
        "x" = "No MetaDataVersion in the Define-XML 2.x namespaces was found."
      ),
      kind = "input",
      call = call
    )
  }

  # ---- study -----------------------------------------------------------
  study_name <- xml2::xml_text(
    xml2::xml_find_first(doc, "//*[local-name()='StudyName']")
  )
  study_desc <- xml2::xml_text(
    xml2::xml_find_first(doc, "//*[local-name()='StudyDescription']")
  )
  protocol <- xml2::xml_text(
    xml2::xml_find_first(doc, "//*[local-name()='ProtocolName']")
  )
  standards <- .dx_find_all(mdv, "Standard")
  standard <- if (length(standards)) {
    # Take the first IMPLEMENTATION GUIDE standard, not merely the first node.
    # The schema imposes no order on def:Standard, so a document may list a
    # controlled-terminology standard first -- and then the scalar would read
    # as a CT publication date while standards$is_primary pointed at the
    # actual IG. One object must not carry two answers to "which standard".
    types <- vapply(standards, .dx_attr, character(1), name = "Type")
    pick <- which(!is.na(types) & types == "IG")[1]
    if (is.na(pick)) {
      pick <- 1L
    }
    paste(
      xml2::xml_attr(standards[[pick]], "Name"),
      xml2::xml_attr(standards[[pick]], "Version")
    )
  } else {
    # Define 2.0 records the standard on the MetaDataVersion itself.
    paste(
      .dx_attr(mdv, "StandardName"),
      .dx_attr(mdv, "StandardVersion")
    )
  }
  # The document's OWN identifiers, so a read and a write back keep every
  # name a reviewer, a prior submission, or a tracking system may already
  # reference. Minting fresh ones from the study name breaks all of them.
  study_node <- xml2::xml_find_first(doc, "//*[local-name()='Study']")
  study <- data.frame(
    study_name = study_name,
    study_description = study_desc,
    protocol_name = protocol,
    standard = standard,
    define_version = .dx_attr(mdv, "DefineVersion"),
    study_oid = .dx_attr(study_node, "OID"),
    file_oid = .dx_attr(xml2::xml_root(doc), "FileOID"),
    odm_context = .dx_attr(xml2::xml_root(doc), "Context"),
    metadata_version_oid = .dx_attr(mdv, "OID"),
    metadata_version_name = .dx_attr(mdv, "Name"),
    metadata_version_description = .dx_attr(mdv, "Description"),
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
  if (length(external_oids)) {
    # An ExternalCodeList names a dictionary (MedDRA, WHODrug, ISO 3166)
    # rather than an enumerable membership list, and artoo has no model for
    # one yet. Both the list AND every reference to it are dropped, so a
    # document written back from this spec loses the dictionary silently and
    # define_lint() sees nothing dangling: the loss is undetectable unless
    # the read says so.
    dicts <- vapply(
      cl_nodes[external],
      function(n) {
        ext <- .dx_child(n, "ExternalCodeList")
        d <- .dx_attr(ext, "Dictionary")
        if (is.na(d)) .dx_attr(n, "Name") else d
      },
      character(1)
    )
    .artoo_warn(
      c(
        "{length(external_oids)} external codelist{?s} in {.path {path}} dropped.",
        "x" = "{.val {dicts}}: artoo does not model external dictionaries yet.",
        "i" = "Their references are dropped too, so writing this spec back will not reproduce them."
      ),
      kind = "spec",
      call = call
    )
  }

  item_nodes <- .dx_find_all(mdv, "ItemDef")
  # Define-XML allows several def:Origin per ItemDef; artoo carries one. The
  # extra provenance is dropped, so the read says so -- a symmetric drop in
  # the reader and the writer is invisible to a round-trip test, and a loss
  # nothing reports is worse than one that fails.
  #
  # Counted in its OWN pass. Accumulating into a list from inside the lapply
  # below binds a local copy, and the warning then never fires -- which is
  # exactly how the first version of this shipped.
  multi_origin <- xml2::xml_attr(
    item_nodes[vapply(
      item_nodes,
      function(n) {
        length(xml2::xml_find_all(n, "./*[local-name()='Origin']")) > 1L
      },
      logical(1)
    )],
    "OID"
  )
  if (length(multi_origin)) {
    .artoo_warn(
      c(
        "{length(multi_origin)} ItemDef{?s} in {.path {path}} carr{?ies/y} more than one {.code def:Origin}.",
        "x" = "Only the first is read: {.val {multi_origin}}.",
        "i" = "Writing this spec back will not reproduce the others."
      ),
      kind = "spec",
      call = call
    )
  }
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
    alias <- .dx_alias(n)
    # def:Origin carries more than a Type: 2.1 adds @Source, and both
    # versions allow a Description and a DocumentRef naming the annotated CRF
    # page. Dropping those loses the CRF page annotation entirely, which is an
    # FDA expectation.
    o_doc <- c(NA_character_, NA_character_)
    o_desc <- NA_character_
    o_page_type <- NA_character_
    o_page_title <- NA_character_
    if (!is.na(origin)) {
      o_desc <- .dx_text(origin)
      dref <- .dx_child(origin, "DocumentRef")
      if (!is.na(dref)) {
        pg <- .dx_child(dref, "PDFPageRef")
        o_doc <- c(
          .dx_attr(dref, "leafID"),
          if (is.na(pg)) NA_character_ else .dx_page_refs(pg)
        )
        if (!is.na(pg)) {
          o_page_type <- .dx_attr(pg, "Type")
          o_page_title <- .dx_attr(pg, "Title")
        }
      }
    }
    list(
      oid = xml2::xml_attr(n, "OID"),
      name = xml2::xml_attr(n, "Name"),
      data_type = xml2::xml_attr(n, "DataType"),
      length = .dx_int(xml2::xml_attr(n, "Length")),
      significant_digits = .dx_int(xml2::xml_attr(n, "SignificantDigits")),
      display_format = .dx_attr(n, "DisplayFormat"),
      sas_field_name = .dx_attr(n, "SASFieldName"),
      label = .dx_text(n),
      codelist_id = clid,
      comment_id = .dx_attr(n, "CommentOID"),
      origin = if (is.na(origin)) {
        NA_character_
      } else {
        xml2::xml_attr(origin, "Type")
      },
      source = if (is.na(origin)) NA_character_ else .dx_attr(origin, "Source"),
      origin_description = o_desc,
      origin_document_id = o_doc[1],
      pages = o_doc[2],
      page_type = o_page_type,
      page_title = o_page_title,
      alias_context = alias[1],
      alias_name = alias[2],
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
    .artoo_abort(
      c(
        "{.path {path}} defines no datasets.",
        "x" = "The MetaDataVersion has no ItemGroupDef.",
        "i" = "Check that this is a study Define-XML, not a standards or CT document."
      ),
      kind = "input",
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
    # def:Class is a CHILD ELEMENT in 2.1 but an ATTRIBUTE in 2.0. Reading
    # only the element loses `class` on every 2.0 document -- which it did,
    # silently, until this fallback was added.
    cls_name <- if (is.na(cls)) {
      .dx_attr(ig, "Class")
    } else {
      .dx_attr(cls, "Name")
    }
    sub_cls <- if (is.na(cls)) {
      NA_character_
    } else {
      sc <- .dx_child(cls, "SubClass")
      if (is.na(sc)) NA_character_ else .dx_attr(sc, "Name")
    }
    ig_alias <- .dx_alias(ig)
    ds_rows[[length(ds_rows) + 1L]] <- data.frame(
      dataset = ds_name,
      label = .dx_text(ig),
      class = cls_name,
      subclass = sub_cls,
      structure = .dx_attr(ig, "Structure"),
      keys = if (length(key_names)) {
        paste(key_names, collapse = " ")
      } else {
        NA_character_
      },
      comment_id = .dx_attr(ig, "CommentOID"),
      itemgroupoid = .dx_attr(ig, "OID"),
      domain = .dx_attr(ig, "Domain"),
      sas_dataset_name = .dx_attr(ig, "SASDatasetName"),
      repeating = .dx_yn(.dx_attr(ig, "Repeating")),
      reference_data = .dx_yn(.dx_attr(ig, "IsReferenceData")),
      purpose = .dx_attr(ig, "Purpose"),
      archive_location_id = .dx_attr(ig, "ArchiveLocationID"),
      standard_id = .dx_attr(ig, "StandardOID"),
      is_non_standard = .dx_yn(.dx_attr(ig, "IsNonStandard")),
      has_no_data = .dx_yn(.dx_attr(ig, "HasNoData")),
      alias_context = ig_alias[1],
      alias_name = ig_alias[2],
      stringsAsFactors = FALSE
    )
    for (j in seq_along(refs)) {
      it <- items[[ref_oid[j]]]
      if (is.null(it)) {
        .artoo_abort(
          c(
            "{.path {path}} is inconsistent.",
            "x" = "ItemRef {.val {ref_oid[j]}} has no ItemDef."
          ),
          kind = "input",
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
        source = it$source,
        origin_description = it$origin_description,
        origin_document_id = it$origin_document_id,
        pages = it$pages,
        page_type = it$page_type,
        page_title = it$page_title,
        sas_field_name = it$sas_field_name,
        value_list_id = it$value_list,
        alias_context = it$alias_context,
        alias_name = it$alias_name,
        # ItemRef-level attributes: these belong to the reference, not the
        # definition, so two datasets may reference one ItemDef differently.
        role = .dx_attr(refs[[j]], "Role"),
        role_codelist_id = .dx_attr(refs[[j]], "RoleCodeListOID"),
        is_non_standard = .dx_yn(.dx_attr(refs[[j]], "IsNonStandard")),
        has_no_data = .dx_yn(.dx_attr(refs[[j]], "HasNoData")),
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
    # The NCI C-code lives on an Alias with Context "nci:ExtCodeID", at both
    # list and term level. It is a Pinnacle 21 conformance check and an FDA
    # expectation for CDISC controlled terminology, so dropping it makes the
    # output non-submission-grade.
    cl_alias <- .dx_alias(n, "nci:ExtCodeID")
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
      name = .dx_attr(n, "Name"),
      data_type = .dx_attr(n, "DataType"),
      sas_format_name = .dx_attr(n, "SASFormatName"),
      nci_code = cl_alias[2],
      standard_id = .dx_attr(n, "StandardOID"),
      is_non_standard = .dx_yn(.dx_attr(n, "IsNonStandard")),
      comment_id = .dx_attr(n, "CommentOID"),
      term_nci_code = vapply(
        terms,
        function(t) .dx_alias(t, "nci:ExtCodeID")[2],
        character(1)
      ),
      rank = .dx_int(xml2::xml_attr(terms, "Rank")),
      term_description = vapply(terms, .dx_text, character(1)),
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
      if (is.na(pg)) NA_character_ else .dx_page_refs(pg),
      # @Type is REQUIRED on def:PDFPageRef in 2.1, so a writer that never
      # read it cannot round-trip one. @Title is 2.1-only and names the
      # table or listing the page holds -- the analysis-results displays use
      # it on every reference.
      if (is.na(pg)) NA_character_ else .dx_attr(pg, "Type"),
      if (is.na(pg)) NA_character_ else .dx_attr(pg, "Title")
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
      page_type = vapply(refs, `[`, character(1), 3L),
      page_title = vapply(refs, `[`, character(1), 4L),
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
      # Dropping @Type made the writer default it to PhysicalRef, so a
      # comment pointing at a named destination came back asserting that
      # destination was a page number.
      page_type = vapply(refs, `[`, character(1), 3L),
      page_title = vapply(refs, `[`, character(1), 4L),
      stringsAsFactors = FALSE
    )
  } else {
    NULL
  }
  # A leaf's ROLE is which MetaDataVersion container owns it. Read it off the
  # container rather than guessing from the filename: a leaf referenced only
  # from def:Origin sits in no container at all, so a title regex would
  # fabricate a def:AnnotatedCRF the source does not have, and write a
  # different document than it read.
  role_of <- function(id) {
    if (id %in% acrf_ids) {
      "annotated_crf"
    } else if (id %in% supp_ids) {
      "supplemental"
    } else if (id %in% archive_ids) {
      "archive"
    } else {
      "other"
    }
  }
  container_ids <- function(container) {
    node <- .dx_child(mdv, container)
    if (is.na(node)) {
      return(character(0))
    }
    refs <- xml2::xml_find_all(node, "./*[local-name()='DocumentRef']")
    if (!length(refs)) {
      character(0)
    } else {
      vapply(refs, .dx_attr, character(1), name = "leafID")
    }
  }
  acrf_ids <- container_ids("AnnotatedCRF")
  supp_ids <- container_ids("SupplementalDoc")
  archive_ids <- vapply(
    .dx_find_all(mdv, "ItemGroupDef"),
    .dx_attr,
    character(1),
    name = "ArchiveLocationID"
  )
  archive_ids <- archive_ids[!is.na(archive_ids)]

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
      role = vapply(
        leaf_nodes,
        function(n) role_of(.dx_attr(n, "ID")),
        character(1)
      ),
      stringsAsFactors = FALSE
    )
    d[!duplicated(d$document_id), , drop = FALSE]
  } else {
    NULL
  }

  # ---- def:Standards (2.1) -----------------------------------------------
  # 2.0 carries a single def:StandardName + def:StandardVersion pair on
  # MetaDataVersion; 2.1 replaces it with this table plus def:StandardOID
  # back-references. Collapsing it to one scalar, as the reader used to, loses
  # which standard each dataset and codelist actually claims.
  std_nodes <- .dx_find_all(mdv, "Standard")
  standards <- if (length(std_nodes)) {
    # A def:Standard missing @Type is invalid but readable, and a read never
    # schema-validates. Left as NA it poisons the cumsum below and every
    # subsequent row, so the primary flag silently becomes NA.
    ig <- vapply(std_nodes, .dx_attr, character(1), name = "Type") == "IG"
    ig <- !is.na(ig) & ig
    data.frame(
      standard_id = vapply(std_nodes, .dx_attr, character(1), name = "OID"),
      name = vapply(std_nodes, .dx_attr, character(1), name = "Name"),
      type = vapply(std_nodes, .dx_attr, character(1), name = "Type"),
      version = vapply(std_nodes, .dx_attr, character(1), name = "Version"),
      status = vapply(std_nodes, .dx_attr, character(1), name = "Status"),
      publishing_set = vapply(
        std_nodes,
        .dx_attr,
        character(1),
        name = "PublishingSet"
      ),
      comment_id = vapply(
        std_nodes,
        .dx_attr,
        character(1),
        name = "CommentOID"
      ),
      # The first IG standard is the one a 2.0 document could express; mark
      # it so a downgrade has an unambiguous choice rather than guessing.
      # The first IG standard: the one a 2.0 document can express, since 2.0
      # carries a single name/version pair rather than a table.
      is_primary = ig & cumsum(ig) == 1L,
      order = seq_along(std_nodes),
      stringsAsFactors = FALSE
    )
  } else {
    NULL
  }

  # ---- def:WhereClauseDef, structured ------------------------------------
  where_clauses <- .dx_where_clauses(mdv, items)

  # ---- MethodDef/FormalExpression ----------------------------------------
  method_expressions <- .dx_method_expressions(md_nodes)

  # ---- analysis results metadata -----------------------------------------
  arm <- .dx_read_arm(mdv, items, ig_nodes)

  # ---- value-level metadata ----------------------------------------------
  values <- .dx_values(mdv, items, vl_owner, path, call)

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

  artoo_spec(
    datasets = scoped$datasets,
    variables = variables,
    codelists = codelists,
    study = study,
    values = scoped$values,
    methods = methods,
    comments = comments,
    documents = documents,
    standards = standards,
    where_clauses = where_clauses,
    method_expressions = method_expressions,
    arm_displays = arm$displays,
    arm_results = arm$results
  )
}

# arm:AnalysisResultDisplays -> arm_displays + arm_results.
#
# The two tables have different grains, and both are forced by the schema:
# one row per arm:ResultDisplay (which carries at most one display-level
# def:DocumentRef), and one row per arm:AnalysisResult x arm:AnalysisDataset,
# because each analysis dataset carries its own def:WhereClauseRef and its own
# list of analysis variables. A delimited string cannot express that.
#
# Identifiers are resolved to NAMES where a name exists -- an ItemGroupOID to
# its dataset, an analysis variable's ItemOID to its variable -- because that
# is the form a workbook carries and the form the rest of the spec uses.
# An OID that resolves to nothing is kept verbatim, so nothing is lost.
#' @noRd
.dx_read_arm <- function(mdv, items, ig_nodes) {
  none <- list(displays = NULL, results = NULL)
  root <- .dx_child(mdv, "AnalysisResultDisplays")
  if (is.na(root)) {
    return(none)
  }
  displays <- xml2::xml_find_all(root, "./*[local-name()='ResultDisplay']")
  if (!length(displays)) {
    return(none)
  }
  group_name <- vapply(ig_nodes, .dx_attr, character(1), name = "Name")
  names(group_name) <- vapply(ig_nodes, .dx_attr, character(1), name = "OID")

  disp_rows <- list()
  res_rows <- list()
  for (di in seq_along(displays)) {
    d <- displays[[di]]
    did <- .dx_attr(d, "OID")
    ref <- .dx_read_arm_docref(d)
    disp_rows[[length(disp_rows) + 1L]] <- data.frame(
      display_id = did,
      name = .dx_attr(d, "Name"),
      description = .dx_text(d),
      document_id = ref[[1]],
      pages = ref[[2]],
      page_type = ref[[3]],
      page_title = ref[[4]],
      order = di,
      stringsAsFactors = FALSE
    )
    results <- xml2::xml_find_all(d, "./*[local-name()='AnalysisResult']")
    for (ri in seq_along(results)) {
      res_rows[[length(res_rows) + 1L]] <- .dx_read_arm_result(
        results[[ri]],
        did,
        ri,
        items,
        group_name
      )
    }
  }
  list(
    displays = do.call(rbind, disp_rows),
    results = if (length(res_rows)) do.call(rbind, res_rows) else NULL
  )
}

# leafID, pages, page type, page title off a node's first def:DocumentRef.
#' @noRd
.dx_read_arm_docref <- function(node) {
  r <- .dx_child(node, "DocumentRef")
  if (is.na(r)) {
    return(rep(NA_character_, 4L))
  }
  pg <- .dx_child(r, "PDFPageRef")
  c(
    .dx_attr(r, "leafID"),
    if (is.na(pg)) NA_character_ else .dx_page_refs(pg),
    if (is.na(pg)) NA_character_ else .dx_attr(pg, "Type"),
    if (is.na(pg)) NA_character_ else .dx_attr(pg, "Title")
  )
}

#' @noRd
.dx_read_arm_result <- function(node, display_id, order, items, group_name) {
  sets <- .dx_child(node, "AnalysisDatasets")
  comment <- if (is.na(sets)) NA_character_ else .dx_attr(sets, "CommentOID")
  each <- if (is.na(sets)) {
    list()
  } else {
    xml2::xml_find_all(sets, "./*[local-name()='AnalysisDataset']")
  }
  doc <- .dx_child(node, "Documentation")
  doc_ref <- if (is.na(doc)) {
    rep(NA_character_, 4L)
  } else {
    .dx_read_arm_docref(doc)
  }
  code <- .dx_child(node, "ProgrammingCode")
  code_ref <- if (is.na(code)) {
    rep(NA_character_, 4L)
  } else {
    .dx_read_arm_docref(code)
  }
  code_text <- NA_character_
  if (!is.na(code)) {
    body <- .dx_child(code, "Code")
    if (!is.na(body)) {
      code_text <- trimws(xml2::xml_text(body))
    }
  }

  row <- function(dataset, variables, where_clause_id) {
    data.frame(
      display_id = display_id,
      result_id = .dx_attr(node, "OID"),
      description = .dx_text(node),
      parameter_id = .dx_attr(node, "ParameterOID"),
      reason = .dx_attr(node, "AnalysisReason"),
      purpose = .dx_attr(node, "AnalysisPurpose"),
      dataset = dataset,
      variables = variables,
      where_clause_id = where_clause_id,
      datasets_comment_id = comment,
      documentation = if (is.na(doc)) NA_character_ else .dx_text(doc),
      documentation_document_id = doc_ref[[1]],
      documentation_pages = doc_ref[[2]],
      documentation_page_type = doc_ref[[3]],
      documentation_page_title = doc_ref[[4]],
      programming_context = if (is.na(code)) {
        NA_character_
      } else {
        .dx_attr(code, "Context")
      },
      programming_code = code_text,
      programming_document_id = code_ref[[1]],
      programming_pages = code_ref[[2]],
      programming_page_type = code_ref[[3]],
      programming_page_title = code_ref[[4]],
      order = order,
      stringsAsFactors = FALSE
    )
  }
  if (!length(each)) {
    return(row(NA_character_, NA_character_, NA_character_))
  }
  parts <- lapply(each, function(ds) {
    oid <- .dx_attr(ds, "ItemGroupOID")
    named <- unname(group_name[oid])
    vars <- xml2::xml_find_all(ds, "./*[local-name()='AnalysisVariable']")
    var_oids <- vapply(vars, .dx_attr, character(1), name = "ItemOID")
    var_names <- vapply(
      var_oids,
      function(o) items[[o]]$name %||% o,
      character(1)
    )
    wcr <- .dx_child(ds, "WhereClauseRef")
    row(
      if (is.na(named)) oid else named,
      if (length(var_names)) {
        paste(var_names, collapse = " ")
      } else {
        NA_character_
      },
      if (is.na(wcr)) NA_character_ else .dx_attr(wcr, "WhereClauseOID")
    )
  })
  do.call(rbind, parts)
}

# def:WhereClauseDef -> one row per CheckValue. Fully normalised because a
# CheckValue is free text and can contain a comma or a space, so any
# collapsed encoding would be lossy. The rendered display string on
# `values$where_clause` stays, but this is now the authoritative form.
#' @noRd
.dx_where_clauses <- function(mdv, items) {
  wc_nodes <- .dx_find_all(mdv, "WhereClauseDef")
  if (!length(wc_nodes)) {
    return(NULL)
  }
  rows <- list()
  for (w in wc_nodes) {
    wc_id <- .dx_attr(w, "OID")
    checks <- xml2::xml_find_all(w, "./*[local-name()=\'RangeCheck\']")
    for (ci in seq_along(checks)) {
      rc <- checks[[ci]]
      target <- .dx_attr(rc, "ItemOID")
      it <- items[[target]]
      vals <- xml2::xml_text(
        xml2::xml_find_all(rc, "./*[local-name()=\'CheckValue\']")
      )
      if (!length(vals)) {
        vals <- NA_character_
      }
      rows[[length(rows) + 1L]] <- data.frame(
        where_clause_id = wc_id,
        check_order = ci,
        dataset = NA_character_,
        variable = if (is.null(it)) NA_character_ else it$name,
        itemoid = target,
        comparator = .dx_attr(rc, "Comparator"),
        soft_hard = .dx_attr(rc, "SoftHard"),
        value = vals,
        value_order = seq_along(vals),
        comment_id = .dx_attr(w, "CommentOID"),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) NULL else do.call(rbind, rows)
}

# MethodDef/FormalExpression, 0..n per method. The reader previously dropped
# these entirely even though the slot columns existed.
#' @noRd
.dx_method_expressions <- function(md_nodes) {
  if (!length(md_nodes)) {
    return(NULL)
  }
  rows <- list()
  for (m in md_nodes) {
    mid <- .dx_attr(m, "OID")
    fes <- xml2::xml_find_all(m, "./*[local-name()=\'FormalExpression\']")
    for (i in seq_along(fes)) {
      rows[[length(rows) + 1L]] <- data.frame(
        method_id = mid,
        order = i,
        context = .dx_attr(fes[[i]], "Context"),
        code = trimws(xml2::xml_text(fes[[i]])),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) NULL else do.call(rbind, rows)
}

# ValueListDefs -> one row per value-level ItemRef, with the owning
# dataset/variable (from the parent ItemDef's def:ValueListRef) and the
# WhereClauseDef rendered as readable "VAR IN (a, b)" text.
#' @noRd
.dx_values <- function(mdv, items, vl_owner, path, call) {
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
      wcrs <- xml2::xml_find_all(r, "./*[local-name()='WhereClauseRef']")
      if (length(wcrs) > 1L) {
        # Define-XML combines several refs with OR. Keeping the first would
        # silently narrow which rows the definition applies to, which is the
        # same class of defect as folding an OR into an AND.
        oids <- vapply(wcrs, .dx_attr, character(1), name = "WhereClauseOID")
        .artoo_abort(
          c(
            "{.path {path}} has a value-level item selected by more than one where clause.",
            "x" = "{.val {oids}} are combined with OR, and artoo carries one clause per value-level row.",
            "i" = "Merge them into one def:WhereClauseDef, or split the item into one row per clause."
          ),
          kind = "input",
          call = call
        )
      }
      wcid <- if (!length(wcrs)) {
        NA_character_
      } else {
        .dx_attr(wcrs[[1]], "WhereClauseOID")
      }
      rows[[length(rows) + 1L]] <- data.frame(
        dataset = owner[1],
        variable = owner[2],
        # The FOREIGN KEY, which is what a writer needs; `where_clause` below
        # keeps the rendered display text. Leaving this NA made every
        # value-level row unwritable without re-joining on prose.
        where_clause_id = wcid,
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
        # A value-level row IS an ItemDef, so it carries the whole ItemDef
        # surface. Reading only label/type/length made every value-level
        # origin, comment and display format vanish on a round trip, which
        # define_lint() then reported as a missing Origin.
        significant_digits = if (is.null(it)) {
          NA_integer_
        } else {
          it$significant_digits
        },
        display_format = if (is.null(it)) NA_character_ else it$display_format,
        sas_field_name = if (is.null(it)) NA_character_ else it$sas_field_name,
        comment_id = if (is.null(it)) NA_character_ else it$comment_id,
        origin = if (is.null(it)) NA_character_ else it$origin,
        source = if (is.null(it)) NA_character_ else it$source,
        origin_description = if (is.null(it)) {
          NA_character_
        } else {
          it$origin_description
        },
        origin_document_id = if (is.null(it)) {
          NA_character_
        } else {
          it$origin_document_id
        },
        pages = if (is.null(it)) NA_character_ else it$pages,
        page_type = if (is.null(it)) NA_character_ else it$page_type,
        page_title = if (is.null(it)) NA_character_ else it$page_title,
        method_id = xml2::xml_attr(r, "MethodOID"),
        order = .dx_int(xml2::xml_attr(r, "OrderNumber")),
        mandatory = identical(xml2::xml_attr(r, "Mandatory"), "Yes"),
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}
