# spec_write_define.R — write_spec() on a .xml path: emit Define-XML.
#
# The pipeline is four steps, in this order, and the order is the point:
#
#   1. mint every OID           (define_oid.R)      -- no node exists yet
#   2. build an ordered tree    (define_build*.R)   -- no xml2 call yet
#   3. emit and serialise       (define_emit.R)
#   4. SCHEMA-VALIDATE the serialised bytes, then move into place
#
# Step 4 runs against the temp file, so an invalid document never replaces a
# good one. That matters more here than for any other artoo output: a
# define.xml is the map a reviewer reads before opening a single dataset, and
# a half-written one is worse than none.
#
# CreationDateTime is UTC and overridable, so a submission build is
# reproducible byte for byte. Same argument, same spelling, as codec_xpt.R.

#' @noRd
.write_spec_define <- function(
  spec,
  path,
  version = NULL,
  created = NULL,
  stylesheet = TRUE,
  validate = TRUE,
  call = rlang::caller_env()
) {
  rlang::check_installed("xml2", reason = "to write Define-XML specs.")
  target <- .dx_target_version(version, spec, call)
  p <- .define_profile(target, call)

  .dx_incomplete_notice(spec, call)
  .dx_downgrade_notice(spec, p, call)

  doc <- .dx_document(spec, p, created, call)
  href <- .dx_stylesheet_href(stylesheet, p)
  txt <- .dx_serialise(doc, href, call)

  .with_atomic_write(
    path,
    ".xml",
    function(tmp) {
      con <- file(tmp, open = "wb")
      on.exit(close(con), add = TRUE)
      writeLines(enc2utf8(txt), con, useBytes = TRUE)
      close(con)
      on.exit()
      if (isTRUE(validate)) {
        .dx_assert_valid(tmp, target, path, call)
      }
    },
    call = call
  )

  if (isTRUE(stylesheet)) {
    .dx_copy_stylesheet(path, p, call)
  }
  invisible(path)
}

# The columns a submission-grade define.xml is expected to carry, by slot.
#
# None of these is required by the SCHEMA -- a document without them validates
# -- and every one of them is something a conformance report will raise. artoo
# still writes the file: a spec is often incomplete on purpose partway through
# a study, and refusing to write it would make the tool useless exactly when
# it is most wanted. It says what is missing instead, once, before building.
.dx_expected_columns <- list(
  datasets = c(
    "label",
    "class",
    "domain",
    "purpose",
    "repeating",
    "structure",
    "archive_location_id"
  ),
  variables = c("label", "origin", "length"),
  codelists = c("name", "nci_code"),
  methods = c("description"),
  comments = c("description")
)

# Name every expected column the spec does not fill.
#
# "Does not fill" means absent OR entirely blank, because a workbook that
# emits a header and no values is the ordinary shape of a partly written
# spec, and a column of NAs is exactly as missing as no column.
#' @noRd
.dx_incomplete_notice <- function(spec, call = rlang::caller_env()) {
  gaps <- character(0)
  for (slot in names(.dx_expected_columns)) {
    tbl <- S7::prop(spec, slot)
    if (is.null(tbl) || !nrow(tbl)) {
      next
    }
    for (column in .dx_expected_columns[[slot]]) {
      empty <- if (!(column %in% names(tbl))) {
        TRUE
      } else if (is.logical(tbl[[column]])) {
        all(is.na(tbl[[column]]))
      } else {
        all(.dx_blank(tbl[[column]]))
      }
      if (empty) {
        gaps <- c(gaps, paste0(slot, "$", column))
      }
    }
  }
  if (is.na(spec@standard) && !nrow(spec@standards)) {
    gaps <- c(gaps, "the CDISC standard")
  }
  if (!length(gaps)) {
    return(invisible(character(0)))
  }
  .artoo_warn(
    c(
      "The define.xml is valid but not submission-grade.",
      "x" = "Nothing fills {.val {gaps}}.",
      "i" = "A conformance report will raise {length(gaps)} finding{?s}; fill them in the source spec."
    ),
    kind = "spec_incomplete",
    call = call
  )
  invisible(gaps)
}

# Say once, before a single node exists, what a downgrade will not carry.
#
# Per-attribute warnings would be one per row; a silent filter would hand the
# user a document quietly weaker than their spec. This reads the spec against
# the target profile and names the whole loss in one message.
#' @noRd
.dx_downgrade_notice <- function(spec, p, call = rlang::caller_env()) {
  lost <- character(0)
  available <- unlist(p$def_attrs, use.names = FALSE)
  has <- function(name) name %in% available
  any_set <- function(df, col) .dx_any(.dx_lgl(df, col))
  any_value <- function(df, col) any(!.dx_blank(.dx_chr(df, col)))

  if (!has("def:StandardOID")) {
    if (nrow(spec@standards) > 1L) {
      lost <- c(lost, "def:Standards (only the primary standard survives)")
    }
    if (
      any_value(spec@datasets, "standard_id") ||
        any_value(spec@codelists, "standard_id")
    ) {
      lost <- c(lost, "def:StandardOID")
    }
  }
  if (!has("def:IsNonStandard")) {
    for (tbl in list(spec@datasets, spec@variables, spec@codelists)) {
      if (any_set(tbl, "is_non_standard")) {
        lost <- c(lost, "def:IsNonStandard")
        break
      }
    }
  }
  if (!has("def:HasNoData")) {
    for (tbl in list(spec@datasets, spec@variables)) {
      if (any_set(tbl, "has_no_data")) {
        lost <- c(lost, "def:HasNoData")
        break
      }
    }
  }
  if (
    is.null(p$enum$origin_source) &&
      (any_value(spec@variables, "source") || any_value(spec@values, "source"))
  ) {
    lost <- c(lost, "def:Origin/@Source")
  }
  if (!has("def:CommentOID") || is.null(p$order[["def:Class"]])) {
    # 2.0 has no def:SubClass element, and no CodeList/CodeListItem
    # Description, so those go without a place to put them.
    if (any_value(spec@datasets, "subclass")) {
      lost <- c(lost, "def:SubClass")
    }
    if (any_value(spec@codelists, "term_description")) {
      lost <- c(lost, "CodeListItem/Description")
    }
  }
  if (is.null(p$enum$context) && !is.na(.dx_study_field(spec, "odm_context"))) {
    lost <- c(lost, "ODM/@def:Context")
  }
  if (!("def:CommentOID" %in% p$def_attrs$MetaDataVersion)) {
    if (!is.na(.dx_study_field(spec, "metadata_version_comment_id"))) {
      lost <- c(lost, "MetaDataVersion/@def:CommentOID")
    }
  }
  if (nrow(spec@standards) == 1L && !has("def:StandardOID")) {
    # 2.0 keeps a name and a version and nothing else about the standard.
    extra <- c("status", "publishing_set", "comment_id")
    if (
      any(vapply(extra, function(k) any_value(spec@standards, k), logical(1)))
    ) {
      lost <- c(lost, "def:Standard status, publishing set and comment")
    }
  }
  if (
    !("Title" %in% p$local_attrs[["def:PDFPageRef"]]) &&
      any(vapply(
        list(
          list(spec@arm_displays, "page_title"),
          list(spec@variables, "page_title"),
          list(spec@values, "page_title"),
          list(spec@methods, "page_title"),
          list(spec@comments, "page_title"),
          list(spec@arm_results, "documentation_page_title"),
          list(spec@arm_results, "programming_page_title")
        ),
        function(where) any_value(where[[1]], where[[2]]),
        logical(1)
      ))
  ) {
    lost <- c(lost, "def:PDFPageRef/@Title")
  }
  # The origin vocabulary is TRANSLATED rather than dropped, and a
  # translation is a change to what the document asserts: a variable the
  # spec says was "Collected" is written as CRF-collected, because CRF is
  # 2.0's only spelling for it.
  if (
    !is.null(p$enum$origin_type) &&
      !("Collected" %in% p$enum$origin_type) &&
      (any(.dx_chr(spec@variables, "origin") == "Collected", na.rm = TRUE) ||
        any(.dx_chr(spec@values, "origin") == "Collected", na.rm = TRUE))
  ) {
    lost <- c(lost, "Collected origins, rewritten as CRF")
  }
  lost <- unique(lost)
  if (!length(lost)) {
    return(invisible(character(0)))
  }
  version <- p$version
  .artoo_warn(
    c(
      "Define-XML {version} cannot carry everything this spec holds.",
      "x" = "Dropped or rewritten: {.val {lost}}.",
      "i" = "Write the spec as {.val 2.1}, or to native JSON, to keep it whole."
    ),
    kind = "define",
    call = call
  )
  invisible(lost)
}

# Build the whole document. The root is created directly rather than emitted,
# because the namespace declarations are what every prefixed child name below
# resolves against.
#' @noRd
.dx_document <- function(spec, p, created, call = rlang::caller_env()) {
  oids <- .dx_oids(spec, call)
  stamp <- .dx_timestamp(created)
  root_attrs <- c(
    list(
      "xmlns" = unname(p$ns[["odm"]]),
      "xmlns:def" = unname(p$ns[["def"]]),
      "xmlns:xlink" = unname(p$ns[["xlink"]])
    ),
    # The arm: namespace is declared only when the document carries analysis
    # results. An unused declaration on every define.xml is noise a reviewer
    # reads as a promise the file does not keep.
    if (nrow(spec@arm_displays)) {
      list("xmlns:arm" = unname(p$ns[["arm"]]))
    } else {
      list()
    },
    .dx_attrs(
      ODMVersion = p$odm_version,
      FileType = "Snapshot",
      FileOID = .dx_file_oid(spec, oids, p),
      CreationDateTime = stamp,
      # Who built the document and with what. Optional, and sponsor-authored:
      # artoo never invents them, but a document that carried them keeps them.
      Originator = .dx_study_field(spec, "originator"),
      SourceSystem = .dx_study_field(spec, "source_system"),
      SourceSystemVersion = .dx_study_field(spec, "source_system_version")
    ),
    # The document's own context, not an assumption. Asserting "Submission"
    # on a file the sponsor marked otherwise is a claim artoo has no standing
    # to make.
    .dx_context(.dx_context_value(spec), p, call)
  )
  doc <- do.call(xml2::xml_new_root, c(list("ODM"), root_attrs))
  .dx_emit(doc, .dx_study_node(spec, p, oids, call), p, call)
  doc
}

#' @noRd
.dx_context_value <- function(spec) {
  v <- .dx_study_field(spec, "odm_context")
  if (is.na(v)) "Submission" else v
}

# ISO 8601, UTC, second precision. `created` accepts anything as.POSIXct
# understands so a build script can freeze it.
#' @noRd
.dx_timestamp <- function(created) {
  when <- if (is.null(created)) Sys.time() else as.POSIXct(created, tz = "UTC")
  format(when, "%Y-%m-%dT%H:%M:%S", tz = "UTC")
}

#' @noRd
.dx_study_node <- function(spec, p, oids, call = rlang::caller_env()) {
  .dx_node(
    "Study",
    attrs = .dx_attrs(OID = oids$study),
    kids = list(
      GlobalVariables = .dx_global_variables(spec),
      MetaDataVersion = .dx_metadata_version(spec, p, oids, call)
    )
  )
}

#' @noRd
.dx_metadata_version <- function(spec, p, oids, call = rlang::caller_env()) {
  var <- spec@variables
  ds <- spec@datasets
  docs <- spec@documents

  # A leaf whose id is a dataset's archive location belongs INSIDE that
  # ItemGroupDef; every other leaf sits on the MetaDataVersion. Reading the
  # placement off the reference, not off the document's title, is what makes
  # a read/write round trip put each leaf back where it came from.
  archive_of <- .dx_map(
    .dx_chr(ds, "archive_location_id"),
    as.character(ds$dataset)
  )

  groups <- lapply(.dx_row_order(ds), function(i) {
    name <- ds$dataset[[i]]
    rows <- which(as.character(var$dataset) == name)
    rows <- rows[.dx_row_order(var[rows, , drop = FALSE])]
    refs <- lapply(rows, function(j) {
      .dx_itemref(
        var,
        j,
        .dx_get(oids$variable, .dx_key(var$dataset[[j]], var$variable[[j]])),
        .dx_chr(var, "order")[[j]],
        p
      )
    })
    .dx_itemgroup(
      spec,
      i,
      refs,
      .dx_archive_leaf(docs, .dx_chr(ds, "archive_location_id")[[i]]),
      p,
      oids,
      call
    )
  })

  mdv_leaves <- if (is.null(docs) || !nrow(docs)) {
    list()
  } else {
    keep <- which(!(as.character(docs$document_id) %in% names(archive_of)))
    lapply(keep, function(i) {
      .dx_leaf(
        docs$document_id[[i]],
        .dx_chr(docs, "href")[[i]],
        .dx_chr(docs, "title")[[i]]
      )
    })
  }

  cl <- spec@codelists
  codelists <- if (!nrow(cl)) {
    list()
  } else {
    lapply(unique(as.character(cl$codelist_id)), function(id) {
      .dx_codelist(
        cl[as.character(cl$codelist_id) == id, , drop = FALSE],
        p,
        call
      )
    })
  }

  md <- spec@methods
  fes <- spec@method_expressions
  methods <- lapply(.dx_row_order(md), function(i) {
    .dx_method(md, i, fes, p, call)
  })

  cm <- spec@comments
  comments <- lapply(.dx_row_order(cm), function(i) .dx_comment(cm, i, p, call))

  .dx_node(
    "MetaDataVersion",
    attrs = c(
      .dx_attrs(
        OID = oids$mdv,
        Name = .dx_mdv_name(spec),
        Description = .dx_study_field(spec, "metadata_version_description"),
        "def:DefineVersion" = .dx_define_version(spec, p),
        "def:CommentOID" = .dx_mdv_comment(spec, p)
      ),
      .dx_standard_attrs(spec, p)
    ),
    kids = list(
      `def:Standards` = .dx_standards(spec, p, call),
      `def:AnnotatedCRF` = .dx_doc_container(
        docs,
        "annotated_crf",
        "def:AnnotatedCRF",
        p
      ),
      `def:SupplementalDoc` = .dx_doc_container(
        docs,
        "supplemental",
        "def:SupplementalDoc",
        p
      ),
      `def:ValueListDef` = .dx_value_lists(spec, oids, p, call),
      `def:WhereClauseDef` = .dx_where_clause_defs(spec, oids, p, call),
      ItemGroupDef = groups,
      ItemDef = {
        pool <- .dx_itemdefs(spec, oids, call)
        lapply(seq_len(nrow(pool)), function(i) {
          .dx_itemdef(as.list(pool[i, , drop = FALSE]), p, call)
        })
      },
      CodeList = codelists,
      MethodDef = methods,
      `def:CommentDef` = comments,
      `def:leaf` = mdv_leaves,
      `arm:AnalysisResultDisplays` = .dx_arm_displays(spec, oids, p, call)
    )
  )
}

# The spec's own def:DefineVersion wins when the version admits revisions, so
# reading 2.1.10 and writing it back does not silently restate it as 2.1.0.
# 2.0 fixes the value at 2.0.0, and libxml2 drops `fixed` through xs:redefine,
# so there the standard's value is asserted rather than the spec's.
#' @noRd
.dx_define_version <- function(spec, p) {
  if (isTRUE(p$define_version_fixed)) {
    return(p$define_version)
  }
  dv <- .dx_study_field(spec, "define_version")
  prefix <- sub("[.][^.]*$", ".", p$define_version)
  if (!is.na(dv) && startsWith(dv, prefix)) dv else p$define_version
}

# Define-XML 2.0 has no def:Standards element: it carries ONE name/version
# pair on MetaDataVersion, both required. The pair comes from the standards
# row flagged is_primary, which the reader sets to the first implementation
# guide -- 2.0 cannot express the rest, and picking a controlled-terminology
# publication date as "the standard" would be worse than picking nothing.
#' @noRd
.dx_standard_attrs <- function(spec, p, call = rlang::caller_env()) {
  if (!("def:StandardName" %in% p$def_attrs$MetaDataVersion)) {
    return(list())
  }
  std <- spec@standards
  pick <- if (nrow(std)) which(.dx_lgl(std, "is_primary")) else integer(0)
  if (!length(pick)) {
    # Fall back to the scalar @standard, which is where a spec built from a
    # WORKBOOK carries it: "SDTMIG 3.4" splits into a name and a version.
    #
    # The split is a guess, and it is only ever reached for a source that
    # never had the two fields apart. A Define-XML read fills the standards
    # table instead, precisely so a version containing a space
    # ("3.1.2 Amendment 1") is not silently cut in half here.
    scalar <- spec@standard
    parts <- if (is.na(scalar)) {
      character(0)
    } else {
      strsplit(trimws(scalar), "[[:space:]]+")[[1]]
    }
    if (length(parts) < 2L) {
      .artoo_abort(
        c(
          "Define-XML 2.0 needs a standard name and version.",
          "x" = if (length(parts)) {
            "{.arg standard} is {.val {scalar}}, which names no version."
          } else {
            "The spec names no standard."
          },
          "i" = "Set {.arg standard} to a name and a version, or flag a {.code standards} row {.code is_primary}."
        ),
        kind = "define",
        call = call
      )
    }
    return(.dx_attrs(
      "def:StandardName" = paste(utils::head(parts, -1L), collapse = " "),
      "def:StandardVersion" = utils::tail(parts, 1L)
    ))
  }
  i <- pick[[1]]
  .dx_attrs(
    "def:StandardName" = std$name[[i]],
    "def:StandardVersion" = .dx_chr(std, "version")[[i]]
  )
}

# The document's own FileOID wins: it is how a prior submission, a reviewer's
# note, or a tracking system names this file.
#' @noRd
.dx_file_oid <- function(spec, oids, p) {
  supplied <- .dx_study_field(spec, "file_oid")
  if (!is.na(supplied)) {
    return(supplied)
  }
  paste0(oids$study, ".Define-XML_", p$define_version)
}

# MetaDataVersion/@def:CommentOID is 2.1-only. Dropping it left the comment
# it names defined but unreferenced, which define_lint() reports as an orphan.
#' @noRd
.dx_mdv_comment <- function(spec, p) {
  if (!("def:CommentOID" %in% p$def_attrs$MetaDataVersion)) {
    return(NA_character_)
  }
  .dx_study_field(spec, "metadata_version_comment_id")
}

#' @noRd
.dx_mdv_name <- function(spec) {
  supplied <- .dx_study_field(spec, "metadata_version_name")
  if (!is.na(supplied)) {
    return(supplied)
  }
  std <- spec@standard
  if (is.na(std)) "Data Definitions" else paste(std, "Data Definitions")
}

#' @noRd
.dx_archive_leaf <- function(documents, archive_id) {
  if (is.null(documents) || !nrow(documents) || .dx_blank(archive_id)) {
    return(NULL)
  }
  i <- match(trimws(archive_id), as.character(documents$document_id))
  if (is.na(i)) {
    return(NULL)
  }
  .dx_leaf(
    documents$document_id[[i]],
    .dx_chr(documents, "href")[[i]],
    .dx_chr(documents, "title")[[i]]
  )
}

# ---- stylesheet -----------------------------------------------------------

# TRUE emits the processing instruction naming the bundled stylesheet and
# copies that stylesheet beside the output; a string emits the PI naming it
# and copies nothing; FALSE emits neither.
#
# The PI alone is no longer enough: Chrome removes XSLT support in Chrome 158
# (2026-11-17), so a define.xml that renders only through the browser stops
# rendering. It is still emitted, because the CDISC specification calls for
# it and conformance tooling checks that the named file exists.
#' @noRd
.dx_stylesheet_href <- function(stylesheet, p) {
  if (isTRUE(stylesheet)) {
    return(p$stylesheet)
  }
  if (
    is.character(stylesheet) && length(stylesheet) == 1L && !is.na(stylesheet)
  ) {
    return(stylesheet)
  }
  NULL
}

#' @noRd
.dx_copy_stylesheet <- function(path, p, call = rlang::caller_env()) {
  src <- .artoo_extdata(p$asset_dir, "cdisc-xsl", p$stylesheet)
  ok <- nzchar(src) &&
    file.copy(src, file.path(dirname(path), p$stylesheet), overwrite = TRUE)
  if (!ok) {
    # The document already names the stylesheet in its processing
    # instruction, and a PI naming an absent file is itself a conformance
    # finding, so a silent failure here hands the user a defect to discover
    # in a validation report.
    sheet <- p$stylesheet
    .artoo_warn(
      c(
        "The Define-XML stylesheet was not copied next to {.path {path}}.",
        "i" = "The document references {.file {sheet}}; put a copy beside it, or pass {.code stylesheet = FALSE}."
      ),
      kind = "define",
      call = call
    )
  }
  invisible(ok)
}

# ---- validation gate ------------------------------------------------------

#' @noRd
.dx_assert_valid <- function(tmp, version, path, call = rlang::caller_env()) {
  report <- validate_define(tmp, version = version)
  if (isTRUE(report@summary$valid)) {
    return(invisible(TRUE))
  }
  msgs <- utils::head(as.character(report@findings$message), 3L)
  n <- report@summary$n_errors
  .artoo_abort(
    c(
      "The Define-XML artoo built is not schema-valid, so {.path {path}} was not written.",
      "x" = "{n} schema error{?s}, first: {.val {msgs}}.",
      "i" = "This is an artoo defect; the spec that produced it is worth attaching to a report."
    ),
    kind = "define",
    call = call
  )
}
