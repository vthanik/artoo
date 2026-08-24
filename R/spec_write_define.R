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
  data = NULL,
  stylesheet = TRUE,
  html = FALSE,
  validate = TRUE,
  call = rlang::caller_env()
) {
  rlang::check_installed("xml2", reason = "to write Define-XML specs.")
  if (!isFALSE(html)) {
    .dx_check_render_deps()
  }
  target <- .dx_target_version(version, spec, call)
  p <- .define_profile(target, call)

  # Let the data speak first, so everything downstream -- the completeness
  # notice, the OID table, the builders -- sees one spec and cannot tell a
  # data-informed one from a hand-written one.
  spec <- .dx_apply_data(spec, data, p, call)
  # Names become OIDs here, on a copy: a spec author writes `AEENDY` on a
  # Methods sheet, and the document says `MT.AEENDY`, because an OID must be
  # unique across the whole MetaDataVersion and a bare name is not.
  spec <- .dx_namespace_spec(spec)
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
  if (!isFALSE(html)) {
    .dx_render_html(path, html, p, call)
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
    "purpose",
    "repeating",
    "structure",
    "archive_location_id"
  ),
  variables = c("label", "origin", "length"),
  values = c("label", "origin", "length"),
  documents = c("href", "title"),
  codelists = c("name", "nci_code"),
  methods = c("description"),
  comments = c("description")
)

# ADaM or not, read off the standard the spec names -- the same test
# .dx_purpose() uses to choose Analysis over Tabulation, so the two cannot
# disagree about what an ADaM spec is.
#' @noRd
.dx_is_adam <- function(spec) {
  named <- c(spec@standard, spec@standards$name)
  named <- named[!is.na(named)]
  any(grepl("adam", named, ignore.case = TRUE))
}

# Name every expected column the spec does not fill.
#
# "Does not fill" means absent OR entirely blank, because a workbook that
# emits a header and no values is the ordinary shape of a partly written
# spec, and a column of NAs is exactly as missing as no column.
#' @noRd
.dx_incomplete_notice <- function(spec, call = rlang::caller_env()) {
  gaps <- character(0)
  expected <- .dx_expected_columns
  # `domain` is an SDTM concept. An ADaM dataset legitimately leaves it
  # blank -- CDISC's own reference ADaM define does -- so expecting it of
  # every spec told the author of a complete ADaM define that it was not
  # submission-grade, on the strength of a column ADaM does not use. A
  # notice that fires on correct input teaches users to ignore the channel
  # the whole degradation contract runs on.
  if (!.dx_is_adam(spec)) {
    at <- match("class", expected$datasets)
    expected$datasets <- append(expected$datasets, "domain", after = at)
  }
  for (slot in names(expected)) {
    tbl <- S7::prop(spec, slot)
    if (is.null(tbl) || !nrow(tbl)) {
      next
    }
    for (column in expected[[slot]]) {
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
      "The spec is not submission-grade.",
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
  # A per-ELEMENT check, not the document-wide `has()`: 2.0 carries
  # def:CommentOID on ItemGroupDef and ItemDef, and only CodeList loses it.
  # Left unnamed, the downgrade dropped four codelist comments from the 2.1
  # SDTM example and artoo's own linter then reported ten orphan comments
  # against the document artoo had just written.
  if (!("def:CommentOID" %in% p$def_attrs$CodeList)) {
    if (any_value(spec@codelists, "comment_id")) {
      lost <- c(lost, "def:CommentOID on a CodeList")
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
  # With the Z. ISO 8601 reads a zone-less time as local, so a submission
  # built in two timezones would carry two different-looking stamps for the
  # same instant.
  format(when, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
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
  #
  # The reference is the RESOLVED one, not the stated column: a blank cell
  # derives `LF.<DATASET>`, and a document already carrying that id (a
  # define read through a workbook keeps the leaves and loses only the
  # pointer) is claimed by its ItemGroupDef exactly as a stated one is.
  # Building this map off the stated column emitted that document twice,
  # and an xs:ID may appear once.
  archive_of <- .dx_map(
    vapply(
      seq_len(nrow(ds)),
      function(i) {
        .dx_archive_id(
          .dx_chr(ds, "archive_location_id")[[i]],
          as.character(ds$dataset[[i]]),
          isTRUE(.dx_lgl(ds, "has_no_data")[[i]])
        )
      },
      character(1)
    ),
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
      .dx_archive_leaf(
        docs,
        .dx_chr(ds, "archive_location_id")[[i]],
        as.character(ds$dataset[[i]]),
        isTRUE(.dx_lgl(ds, "has_no_data")[[i]])
      ),
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
  # An external dictionary is a CodeList too -- one with no terms to list
  # and an ExternalCodeList saying where the terms live. Until it was
  # emitted, a variable naming MedDRA wrote a CodeListRef pointing at
  # nothing: schema-valid, and rejected by artoo's own reference check.
  codelists <- c(codelists, .dx_dictionaries(spec@dictionaries, p, call))

  md <- .dx_unique_defs(spec@methods, "method_id", "method", call)
  fes <- spec@method_expressions
  methods <- lapply(.dx_row_order(md), function(i) {
    .dx_method(md, i, fes, p, call)
  })

  cm <- .dx_unique_defs(spec@comments, "comment_id", "comment", call)
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
  # A primary row that names neither a standard nor a version is no better
  # than no row at all, and taking it short-circuits the fallback below into
  # emitting a MetaDataVersion the schema refuses.
  if (length(pick)) {
    usable <- !.dx_blank(.dx_chr(std, "name")[pick]) &
      !.dx_blank(.dx_chr(std, "version")[pick])
    pick <- pick[usable]
  }
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
# it names defined but unreferenced, which lint_define() reports as an orphan.
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
.dx_archive_leaf <- function(
  documents,
  archive_id,
  dataset = NA_character_,
  empty = FALSE
) {
  # Nothing stated: derive the id, and prefer a document that already
  # carries it. A workbook has no archive-location column, so a define read
  # into a workbook and back keeps the LEAVES on its documents table and
  # loses only the pointer -- minting a second leaf with the same id then
  # produced two, and an xs:ID may appear once.
  derived <- .dx_blank(archive_id)
  if (derived) {
    archive_id <- .dx_archive_id(NA_character_, dataset, empty)
    if (is.na(archive_id)) {
      return(NULL)
    }
  }
  if (!is.null(documents) && nrow(documents)) {
    i <- match(trimws(archive_id), as.character(documents$document_id))
    if (!is.na(i)) {
      return(.dx_leaf(
        documents$document_id[[i]],
        .dx_chr(documents, "href")[[i]],
        .dx_chr(documents, "title")[[i]]
      ))
    }
  }
  # A stated id the documents table does not carry is the user's to fix,
  # and lint_define() reports the dangle. Minting a leaf here would pair a
  # `def:ArchiveLocationID` of one name with a leaf of another.
  if (!derived) {
    return(NULL)
  }
  .dx_default_archive(dataset, empty)
}

# Where a dataset's own file is, when nothing said.
#
# A workbook has no column for it, so nothing ever said -- and a define
# without it renders every dataset heading as "[Location: ]", which is the
# first thing a reviewer sees. This is derivation, not invention: CDISC's
# own published examples carry it on every dataset that has one, always as
# `LF.<NAME>` pointing at `<name>.xpt`, and the reference tooling derives
# it the same way.
#
# The carve-out is exactly the one those examples make. In the 2.1 SDTM
# example, 9 of 11 datasets carry a location and the two that do not are
# precisely the two flagged `def:HasNoData` -- a dataset with no records
# has no file to point at. An explicit `archive_location_id` still wins
# over both.
#' @noRd
.dx_default_archive <- function(dataset, empty = FALSE) {
  if (.dx_blank(dataset) || isTRUE(empty)) {
    return(NULL)
  }
  file <- paste0(tolower(trimws(dataset)), ".xpt")
  .dx_leaf(paste0("LF.", trimws(dataset)), file, file)
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
  target <- file.path(dirname(path), p$stylesheet)
  # NEVER clobber a stylesheet already sitting beside the output. A sponsor
  # who has customised the rendering keeps it, and the copy exists only so
  # the processing instruction resolves to something.
  if (file.exists(target)) {
    return(invisible(TRUE))
  }
  ok <- nzchar(src) && file.copy(src, target)
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

# ---- HTML ----------------------------------------------------------------

# Render the document through its stylesheet, into a real HTML file.
#
# The processing instruction is not enough on its own. Chrome removes XSLT
# support in Chrome 158 (2026-11-17), so a define.xml that renders only by
# being opened in a browser stops rendering; and a reviewer working from a
# submission archive should not need a browser at all. The PI still ships,
# because the CDISC specification calls for it and conformance tooling checks
# the file it names exists.
#
# `html` is TRUE for a sibling .html, or a path to write it to.
#' @noRd
# The stylesheet href the document names, or NULL when it names none.
# Read from the file rather than reconstructed, so the renderer and the
# browser can only ever agree.
#' @noRd
.dx_pi_href <- function(path) {
  head <- tryCatch(readLines(path, n = 4L, warn = FALSE), error = function(e) {
    character(0)
  })
  pi <- grep("<\\?xml-stylesheet", head, value = TRUE)
  if (!length(pi)) {
    return(NULL)
  }
  href <- sub('.*href="([^"]+)".*', "\\1", pi[[1]])
  if (identical(href, pi[[1]]) || !nzchar(href)) NULL else href
}

.dx_render_html <- function(path, html, p, call = rlang::caller_env()) {
  .dx_check_render_deps()
  # Render through the stylesheet the DOCUMENT names, when that file is
  # actually beside it. Otherwise a sponsor who replaced the stylesheet gets
  # a browser rendering and an artoo rendering that disagree -- and keeping
  # their file is exactly what .dx_copy_stylesheet() goes out of its way to
  # do. Reading it by path keeps its base URI, so a relative xsl:import in a
  # sponsor's sheet still resolves.
  # The name comes from the document's own processing instruction, not from
  # the profile default: `stylesheet = "acme.xsl"` writes a PI naming
  # acme.xsl, and rendering through the bundled sheet instead would give the
  # browser and artoo two different renderings of one document.
  href <- .dx_pi_href(path)
  beside <- file.path(dirname(path), href %||% p$stylesheet)
  sheet <- if (file.exists(beside)) {
    beside
  } else {
    # Falling back to the bundled sheet is the only thing left to do, but it
    # is silently the divergence this function exists to prevent: the
    # document names a stylesheet a browser will not find, and artoo renders
    # through a different one. `stylesheet = TRUE` cannot reach here (a copy
    # is placed beside the output); a sponsor sheet not yet delivered can.
    if (!is.null(href)) {
      .artoo_warn(
        c(
          "The document names a stylesheet that is not beside it.",
          "x" = "No {.file {href}} in {.path {dirname(path)}}.",
          "i" = "This HTML is rendered through the bundled Define-XML {p$version} stylesheet; a browser opening the document will find nothing."
        ),
        kind = "define",
        call = call
      )
    }
    .artoo_extdata(p$asset_dir, "cdisc-xsl", p$stylesheet)
  }
  if (!nzchar(sheet)) {
    stylesheet <- p$stylesheet
    .artoo_abort(
      c(
        "The Define-XML {p$version} stylesheet is missing from the artoo install.",
        "x" = "Expected {.file {stylesheet}}.",
        "i" = "Reinstall artoo; the stylesheets ship with the package."
      ),
      kind = "install",
      call = call
    )
  }
  target <- if (isTRUE(html)) {
    paste0(tools::file_path_sans_ext(path), ".html")
  } else {
    html
  }
  .check_path(target, call = call)
  # IN A SEPARATE PROCESS, and this is not caution for its own sake.
  #
  # libxslt and libxml2's XSD validator share global state, and driving both
  # in one session corrupts it: after the schema gate has validated a
  # document, rendering through a stylesheet leaves reading ANY XML liable to
  # segfault. Measured at nine runs in ten over the four bundled examples,
  # and never once when the render has a process to itself. A crashed R
  # session is a worse failure than a missing HTML file, so the render is
  # exiled and whatever it damages dies with it.
  rendered <- tryCatch(
    callr::r(
      function(source_path, sheet_path) {
        # KEEP THE WHITESPACE. xml2::read_xml() strips whitespace-only text
        # nodes by default, and the stylesheets take string-values that span
        # them -- so a method description rendered as
        # "Concatenation of STUDYID and SUBJIDcatx(...)" instead of leaving a
        # space between the sentence and the code. libxslt applies the XSLT
        # whitespace rules itself; stripping first is not a shortcut to them.
        # No options at all: xml2's default is NOBLANKS, and everything
        # else it offers here would suppress parse errors, which is how a
        # truncated define would render as plausible partial HTML.
        keep <- character(0)
        as.character(
          xslt::xml_xslt(
            xml2::read_xml(source_path, options = keep),
            xml2::read_xml(sheet_path, options = keep)
          )
        )
      },
      args = list(source_path = path, sheet_path = sheet)
    ),
    error = function(e) {
      msg <- .safe_msg(e)
      .artoo_abort(
        c(
          "The stylesheet could not render {.path {path}}.",
          "x" = "{msg}"
        ),
        kind = "codec",
        call = call
      )
    }
  )
  .with_atomic_write(
    target,
    ".html",
    function(tmp) writeLines(enc2utf8(rendered), tmp, useBytes = TRUE),
    call = call
  )
  invisible(target)
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

# Is the rendering toolchain present -- WITHOUT loading libxslt here.
#
# `rlang::check_installed()` calls `requireNamespace()`, which loads the
# package and its DLL. Loading libxslt beside libxml2's XSD validator in
# one process is precisely what `.dx_render_html()`'s subprocess exists to
# avoid: the two share libxml2's global state, and once both are resident,
# reading any XML can abort the session outright -- "Start tag expected"
# and a core dump, not an R error a caller could catch.
#
# So checking for xslt the friendly way defeated the isolation before the
# subprocess ever started. macOS tolerated the pair; Linux and Windows did
# not, which is why every CI runner failed on a suite that passed here.
#
# `system.file()` answers "is it installed" without loading anything. The
# friendly check runs only when the answer is no, and there loading is
# moot because there is nothing to load. callr is pure R and safe either
# way.
#' @noRd
.dx_check_render_deps <- function() {
  rlang::check_installed("callr", reason = "to render a define.xml as HTML.")
  if (!.dx_have_xslt()) {
    rlang::check_installed("xslt", reason = "to render a define.xml as HTML.")
  }
  invisible(TRUE)
}

# Its own function so a test can say "pretend xslt is missing" without
# mocking the availability check into something that loads it.
#' @noRd
.dx_have_xslt <- function() {
  nzchar(system.file(package = "xslt"))
}
