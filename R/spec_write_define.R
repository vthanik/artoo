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

  if (identical(target, "2.0")) {
    .artoo_abort(
      c(
        "artoo cannot write Define-XML 2.0 yet.",
        "x" = "This release writes Define-XML 2.1.",
        "i" = "Pass {.code version = \"2.1\"} to write the spec as 2.1."
      ),
      kind = "define",
      call = call
    )
  }

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
    .dx_copy_stylesheet(path, p)
  }
  invisible(path)
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
    .dx_attrs(
      ODMVersion = p$odm_version,
      FileType = "Snapshot",
      FileOID = paste0(oids$study, ".Define-XML_", p$define_version),
      CreationDateTime = stamp
    ),
    .dx_context("Submission", p, call)
  )
  doc <- do.call(xml2::xml_new_root, c(list("ODM"), root_attrs))
  .dx_emit(doc, .dx_study_node(spec, p, oids, call), p, call)
  doc
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
    rows <- rows[order(.dx_row_order(var[rows, , drop = FALSE]))]
    refs <- lapply(rows, function(j) {
      .dx_itemref(
        var,
        j,
        .dx_get(oids$variable, .dx_key(var$dataset[[j]], var$variable[[j]])),
        .dx_chr(var, "order")[[j]]
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
    attrs = .dx_attrs(
      OID = oids$mdv,
      Name = .dx_mdv_name(spec),
      Description = .dx_study_field(spec, "metadata_version_description"),
      "def:DefineVersion" = .dx_define_version(spec, p)
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
      `def:leaf` = mdv_leaves
    )
  )
}

# The spec's own def:DefineVersion wins when it is a revision of the target
# version, so reading 2.1.10 and writing it back does not silently restate it
# as 2.1.0. Anything else falls back to the profile's version.
#' @noRd
.dx_define_version <- function(spec, p) {
  dv <- .dx_study_field(spec, "define_version")
  prefix <- sub("[.][^.]*$", ".", p$define_version)
  if (!is.na(dv) && startsWith(dv, prefix)) dv else p$define_version
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
.dx_copy_stylesheet <- function(path, p) {
  src <- .artoo_extdata(p$asset_dir, "cdisc-xsl", p$stylesheet)
  if (!nzchar(src)) {
    return(invisible(FALSE))
  }
  invisible(file.copy(
    src,
    file.path(dirname(path), p$stylesheet),
    overwrite = TRUE
  ))
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
