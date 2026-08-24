# define_build.R — structural builders: study, standards, datasets,
# variables, codelists, methods, comments, documents.
#
# Every function here returns a .dx_node() spec with a NAMED child list and
# never touches xml2. Element ORDER is the version profile's job (see
# define_profile.R), so a builder that assigns its children in the wrong
# order still emits a schema-valid document. Version branches live only in
# the small functions named after the feature that differs: .dx_context(),
# .dx_class(), .dx_origin().
#
# Schema-required attributes that a spec may legitimately not carry are
# DERIVED from the spec where a derivation exists (def:Structure from the
# dataset keys, Purpose from the CDISC standard) and defaulted only where the
# common case is unambiguous (Repeating = "No"). Where neither holds, the
# write ABORTS naming the column to fill, rather than inventing a value that
# a reviewer would read as a sponsor's assertion.

# A column as character, tolerating an absent column or a NULL table.
#' @noRd
.dx_chr <- function(df, name) {
  n <- if (is.null(df)) 0L else nrow(df)
  if (!n || !(name %in% names(df))) {
    return(rep(NA_character_, n))
  }
  as.character(df[[name]])
}

# A column as logical, same tolerance.
#' @noRd
.dx_lgl <- function(df, name) {
  n <- if (is.null(df)) 0L else nrow(df)
  if (!n || !(name %in% names(df))) {
    return(rep(NA, n))
  }
  as.logical(df[[name]])
}

#' @noRd
.dx_blank <- function(x) {
  x <- as.character(x)
  is.na(x) | !nzchar(trimws(x))
}

# The one non-blank value in a repeated list-level column, or NA. The
# codelist slot repeats its list-level fields on every term row and a source
# workbook commonly fills only the first, so "the first row" loses the value
# whenever the first row is blank.
#' @noRd
.dx_one <- function(x) {
  v <- unique(as.character(x)[!.dx_blank(x)])
  if (!length(v)) NA_character_ else v[[1]]
}

# An ODM Yes/No attribute from a logical, with a default when unset.
#' @noRd
.dx_yesno <- function(x, default = NA) {
  v <- as.logical(x)
  v[is.na(v)] <- default
  ifelse(is.na(v), NA_character_, ifelse(v, "Yes", "No"))
}

# An odm:YesOnly attribute: the ATTRIBUTE'S PRESENCE is the assertion, so
# FALSE must emit nothing rather than "No", which is not in the type.
#' @noRd
.dx_yesonly <- function(x) {
  if (isTRUE(.dx_any(x))) "Yes" else NA_character_
}

# TRUE when any element is TRUE. Reducing a repeated list-level flag needs
# this, not isTRUE(): isTRUE() on a length-3 vector is FALSE whatever it
# holds, which silently dropped every non-standard codelist flag once.
#' @noRd
.dx_any <- function(x) {
  v <- as.logical(x)
  length(v) > 0L && any(v, na.rm = TRUE)
}

# ---- version-branching helpers -------------------------------------------

# Attributes that exist only in some versions. Naming them here, at the call
# site, is what makes the version dependency readable: the alternative is a
# silent filter somewhere downstream, and then a reader of .dx_itemgroup()
# cannot tell which of its attributes are conditional.
#
# What a downgrade DROPS is reported once, up front, by .dx_downgrade_notice()
# -- not per attribute, which would be one warning per row.
#' @noRd
.dx_only <- function(p, element, ...) {
  a <- .dx_attrs(...)
  a[names(a) %in% p$def_attrs[[element]]]
}

# def:Context on ODM. 2.1 only; the profile carries NULL for 2.0, which is
# how a builder learns the attribute does not exist without naming a version.
#' @noRd
.dx_context <- function(context, p, call = rlang::caller_env()) {
  if (is.null(p$enum$context)) {
    return(list())
  }
  .dx_attrs(
    "def:Context" = .dx_enum(context, p$enum$context, "def:Context", call)
  )
}

# def:Class. A child element carrying an optional def:SubClass in 2.1; a
# plain attribute on ItemGroupDef in 2.0.
#' @noRd
.dx_class <- function(class, subclass, p, call = rlang::caller_env()) {
  if (.dx_blank(class)) {
    return(NULL)
  }
  cls <- .dx_enum(
    toupper(trimws(class)),
    p$enum$class,
    "def:Class Name",
    call
  )
  if (!identical(p$class_slot, "element")) {
    return(cls)
  }
  sub <- if (.dx_blank(subclass)) {
    NULL
  } else {
    .dx_node(
      "def:SubClass",
      attrs = .dx_attrs(
        Name = .dx_enum(
          toupper(trimws(subclass)),
          p$enum$subclass,
          "def:SubClass Name",
          call
        )
      )
    )
  }
  .dx_node(
    "def:Class",
    attrs = .dx_attrs(Name = cls),
    kids = list(`def:SubClass` = sub)
  )
}

# ---- shared leaf builders -------------------------------------------------

#' @noRd
.dx_docref <- function(
  document_id,
  pages,
  page_type,
  p,
  call = rlang::caller_env(),
  title = NA_character_
) {
  if (.dx_blank(document_id)) {
    return(NULL)
  }
  pg <- if (.dx_blank(pages)) {
    NULL
  } else {
    # @Type is required on def:PDFPageRef, and a page list without a type is
    # the commonest source of a page reference no reader can follow.
    type <- if (.dx_blank(page_type)) "PhysicalRef" else trimws(page_type)
    # @Title is 2.1-only, and LOCAL to def:PDFPageRef -- unprefixed, so the
    # emitter's def: guard cannot see it. The profile's local table is how a
    # builder learns whether the version has it.
    title_attr <- if ("Title" %in% p$local_attrs[["def:PDFPageRef"]]) {
      .dx_attrs(Title = title)
    } else {
      list()
    }
    .dx_node(
      "def:PDFPageRef",
      attrs = c(
        .dx_page_attrs(pages, type),
        .dx_attrs(
          Type = .dx_enum(type, p$enum$page_type, "def:PDFPageRef Type", call)
        ),
        title_attr
      )
    )
  }
  .dx_node(
    "def:DocumentRef",
    attrs = .dx_attrs(leafID = trimws(document_id)),
    kids = list(`def:PDFPageRef` = pg)
  )
}

# The inverse of .dx_page_refs(): "4-5" on a physical page reference is the
# @FirstPage/@LastPage range it was read from, and anything else is a
# @PageRefs list.
#' @noRd
.dx_page_attrs <- function(pages, type) {
  v <- trimws(pages)
  if (identical(type, "PhysicalRef") && grepl("^[0-9]+-[0-9]+$", v)) {
    bounds <- strsplit(v, "-", fixed = TRUE)[[1]]
    return(.dx_attrs(FirstPage = bounds[[1]], LastPage = bounds[[2]]))
  }
  .dx_attrs(PageRefs = v)
}

#' @noRd
.dx_leaf <- function(document_id, href, title) {
  .dx_node(
    "def:leaf",
    attrs = .dx_attrs(ID = document_id, "xlink:href" = href),
    kids = list(
      `def:title` = .dx_node(
        "def:title",
        text = if (.dx_blank(title)) document_id else trimws(title)
      )
    )
  )
}

# def:AnnotatedCRF / def:SupplementalDoc: a container of DocumentRefs, one
# per document carrying that role. Absent when the role has no documents.
#' @noRd
.dx_doc_container <- function(documents, role, element, p) {
  if (is.null(documents) || !nrow(documents)) {
    return(NULL)
  }
  hit <- which(.dx_chr(documents, "role") == role)
  if (!length(hit)) {
    return(NULL)
  }
  .dx_node(
    element,
    kids = list(
      `def:DocumentRef` = lapply(hit, function(i) {
        .dx_docref(
          documents$document_id[[i]],
          NA_character_,
          NA_character_,
          p
        )
      })
    )
  )
}

# ---- study / metadata version ---------------------------------------------

#' @noRd
.dx_global_variables <- function(spec) {
  name <- .dx_study_field(spec, "study_name")
  protocol <- .dx_study_field(spec, "protocol_name")
  desc <- .dx_study_field(spec, "study_description")
  # All three elements are required by ODM. Fall back along the chain rather
  # than inventing a third string: a spec that names a protocol but no study
  # is still describing one study.
  if (is.na(name)) {
    name <- if (is.na(protocol)) "Unspecified" else protocol
  }
  .dx_node(
    "GlobalVariables",
    kids = list(
      StudyName = .dx_node("StudyName", text = name),
      StudyDescription = .dx_node(
        "StudyDescription",
        text = if (is.na(desc)) name else desc
      ),
      ProtocolName = .dx_node(
        "ProtocolName",
        text = if (is.na(protocol)) name else protocol
      )
    )
  )
}

# def:Standards (2.1). NULL when the spec carries no standards table, which
# is legal: the element is optional.
# The spellings Define-XML 2.0 used for standards 2.1 renamed. 2.0's name is
# free text, so this is a normalisation of the same standard rather than a
# claim about a different one.
.dx_standard_renames <- c(
  "SDTM-IG" = "SDTMIG",
  "ADaM-IG" = "ADaMIG",
  "SEND-IG" = "SENDIG",
  "CDISC-NCI" = "CDISC/NCI"
)

#' @noRd
.dx_standards <- function(spec, p, call = rlang::caller_env()) {
  if (is.null(p$order[["def:Standards"]])) {
    return(NULL)
  }
  std <- spec@standards
  if (!nrow(std)) {
    if (!is.na(spec@standard)) {
      # The spec names a standard but not in a form def:Standard can carry,
      # which is the shape every workbook-built spec has. Saying nothing here
      # while the partly-filled path warns would make the quieter case the
      # more misleading one.
      version <- p$version
      .artoo_warn(
        c(
          "The {.code def:Standards} block was not written.",
          "x" = "The spec names {.val {spec@standard}} but carries no {.code standards} table.",
          "i" = "Define-XML {version} needs a name, version, type and status for each standard."
        ),
        kind = "define",
        call = call
      )
    }
    return(NULL)
  }
  # def:Standard requires a Name from a CLOSED list, a Version, a Type and a
  # Status. A spec read from a Define-XML 2.0 document carries only a free
  # text name and a version -- 2.0 has no def:Standard element at all -- so
  # it cannot always be promoted. Emitting a partial one produces an invalid
  # document; emitting none is valid and honest, and this says which.
  missing <- .dx_standards_gaps(std, p)
  if (length(missing)) {
    .artoo_warn(
      c(
        "The {.code def:Standards} block was not written.",
        "x" = "Define-XML {p$version} requires {.val {missing}} on every standard, and the spec does not supply {?it/them}.",
        "i" = "Fill the {.code standards} table to describe the standards this study follows."
      ),
      kind = "define",
      call = call
    )
    return(NULL)
  }
  ord <- .dx_row_order(std)
  .dx_node(
    "def:Standards",
    kids = list(
      `def:Standard` = lapply(ord, function(i) {
        .dx_node(
          "def:Standard",
          attrs = .dx_attrs(
            OID = std$standard_id[[i]],
            Name = .dx_standard_name(std$name[[i]], p, call),
            Type = .dx_enum(
              .dx_chr(std, "type")[[i]],
              p$enum$standard_type,
              "def:Standard Type",
              call
            ),
            PublishingSet = .dx_chr(std, "publishing_set")[[i]],
            Version = .dx_chr(std, "version")[[i]],
            Status = .dx_enum(
              .dx_chr(std, "status")[[i]],
              p$enum$standard_status,
              "def:Standard Status",
              call
            ),
            "def:CommentOID" = .dx_chr(std, "comment_id")[[i]]
          )
        )
      })
    )
  )
}

# What every def:Standard row would still be missing, as field names.
#' @noRd
.dx_standards_gaps <- function(std, p) {
  need <- c(
    Name = "name",
    Version = "version",
    Type = "type",
    Status = "status"
  )
  gaps <- vapply(
    need,
    function(col) any(.dx_blank(.dx_chr(std, col))),
    logical(1)
  )
  bad_name <- !all(
    .dx_standard_names(.dx_chr(std, "name")) %in% p$enum$standard_name
  )
  c(names(need)[gaps], if (bad_name && !gaps[["Name"]]) "a recognised Name")
}

#' @noRd
.dx_standard_names <- function(x) {
  v <- trimws(as.character(x))
  hit <- unname(.dx_standard_renames[v])
  # ifelse() inherits names from its condition, so unname BOTH sides.
  unname(ifelse(is.na(hit), v, hit))
}

#' @noRd
.dx_standard_name <- function(x, p, call = rlang::caller_env()) {
  .dx_enum(
    .dx_standard_names(x),
    p$enum$standard_name,
    "def:Standard Name",
    call
  )
}

# Row indices in emission order: the `order` column when it is usable, else
# source order. Never partially applied -- a table where only some rows carry
# an order would otherwise interleave unpredictably.
#' @noRd
.dx_row_order <- function(df) {
  n <- if (is.null(df)) 0L else nrow(df)
  if (!n) {
    return(integer(0))
  }
  if (!("order" %in% names(df))) {
    return(seq_len(n))
  }
  o <- suppressWarnings(as.integer(df$order))
  if (anyNA(o) || anyDuplicated(o)) {
    return(seq_len(n))
  }
  order(o)
}

# ---- datasets -------------------------------------------------------------

# def:Structure is schema-required. The dataset keys ARE the structure, said
# the way CDISC says it, so deriving from them is a restatement rather than
# an invention; with neither, the write aborts.
#' @noRd
.dx_structure <- function(
  structure,
  keys,
  dataset,
  call = rlang::caller_env()
) {
  if (!.dx_blank(structure)) {
    return(trimws(structure))
  }
  if (!.dx_blank(keys)) {
    return(paste0(
      "One record per ",
      gsub("[[:space:]]+", ", ", trimws(keys))
    ))
  }
  .artoo_abort(
    c(
      "Dataset {.val {dataset}} has no structure.",
      "x" = "Define-XML requires {.code def:Structure} on every ItemGroupDef.",
      "i" = "Set {.code structure} on the datasets table, or give the dataset keys."
    ),
    kind = "define",
    call = call
  )
}

# Purpose is schema-required and follows from the standard: ADaM is analysis
# metadata, SDTM and SEND are tabulation metadata.
#' @noRd
.dx_purpose <- function(purpose, standard, p, call = rlang::caller_env()) {
  if (!.dx_blank(purpose)) {
    return(.dx_enum(trimws(purpose), p$enum$purpose, "Purpose", call))
  }
  if (!is.na(standard) && grepl("adam", standard, ignore.case = TRUE)) {
    "Analysis"
  } else {
    "Tabulation"
  }
}

#' @noRd
.dx_itemgroup <- function(
  spec,
  i,
  refs,
  archive_leaf,
  p,
  oids,
  call = rlang::caller_env()
) {
  ds <- spec@datasets
  name <- ds$dataset[[i]]
  cls <- .dx_class(
    .dx_chr(ds, "class")[[i]],
    .dx_chr(ds, "subclass")[[i]],
    p,
    call
  )
  # In 2.0 def:Class is an attribute, so .dx_class() hands back a string.
  cls_attr <- if (is.character(cls)) cls else NA_character_
  cls_kid <- if (is.character(cls)) NULL else cls
  .dx_node(
    "ItemGroupDef",
    attrs = c(
      .dx_attrs(
        OID = .dx_get(oids$dataset, name),
        Name = name,
        Domain = .dx_chr(ds, "domain")[[i]],
        Repeating = .dx_yesno(.dx_lgl(ds, "repeating")[[i]], default = FALSE),
        # Repeating is schema-required, so an unset one takes a default;
        # IsReferenceData is optional, so silence stays silent rather than
        # becoming an assertion the spec never made.
        IsReferenceData = .dx_yesno(.dx_lgl(ds, "reference_data")[[i]]),
        SASDatasetName = if (.dx_blank(.dx_chr(ds, "sas_dataset_name")[[i]])) {
          name
        } else {
          .dx_chr(ds, "sas_dataset_name")[[i]]
        },
        Purpose = .dx_purpose(
          .dx_chr(ds, "purpose")[[i]],
          spec@standard,
          p,
          call
        ),
        "def:Structure" = .dx_structure(
          .dx_chr(ds, "structure")[[i]],
          .dx_chr(ds, "keys")[[i]],
          name,
          call
        ),
        "def:Class" = cls_attr,
        "def:ArchiveLocationID" = .dx_chr(ds, "archive_location_id")[[i]],
        "def:CommentOID" = .dx_chr(ds, "comment_id")[[i]]
      ),
      .dx_only(
        p,
        "ItemGroupDef",
        "def:StandardOID" = .dx_chr(ds, "standard_id")[[i]],
        "def:IsNonStandard" = .dx_yesonly(.dx_lgl(ds, "is_non_standard")[[i]]),
        "def:HasNoData" = .dx_yesonly(.dx_lgl(ds, "has_no_data")[[i]])
      )
    ),
    kids = list(
      Description = .dx_desc(.dx_chr(ds, "label")[[i]]),
      ItemRef = refs,
      Alias = .dx_alias_node(
        .dx_chr(ds, "alias_context")[[i]],
        .dx_chr(ds, "alias_name")[[i]]
      ),
      `def:Class` = cls_kid,
      `def:leaf` = archive_leaf
    )
  )
}

#' @noRd
.dx_alias_node <- function(context, name) {
  if (.dx_blank(name)) {
    return(NULL)
  }
  .dx_node("Alias", attrs = .dx_attrs(Context = context, Name = name))
}

# ---- variables ------------------------------------------------------------

# The ItemRef inside an ItemGroupDef. Everything here belongs to the
# REFERENCE, not the definition, which is why two datasets may reference one
# ItemDef with different roles and key positions.
#' @noRd
.dx_itemref <- function(var, i, oid, order_number, p) {
  .dx_node(
    "ItemRef",
    attrs = c(
      .dx_attrs(
        ItemOID = oid,
        OrderNumber = order_number,
        Mandatory = .dx_yesno(.dx_lgl(var, "mandatory")[[i]], default = FALSE),
        KeySequence = .dx_chr(var, "key_sequence")[[i]],
        MethodOID = .dx_chr(var, "method_id")[[i]],
        Role = .dx_chr(var, "role")[[i]],
        RoleCodeListOID = .dx_chr(var, "role_codelist_id")[[i]]
      ),
      .dx_only(
        p,
        "ItemRef",
        "def:IsNonStandard" = .dx_yesonly(.dx_lgl(var, "is_non_standard")[[i]]),
        "def:HasNoData" = .dx_yesonly(.dx_lgl(var, "has_no_data")[[i]])
      )
    )
  )
}

# The two origin vocabularies, translated. CDISC renamed the collection
# origins between the versions, so a spec read from one and written as the
# other dies on the first collected variable -- which is most of a study --
# unless the rename is applied.
#
# The two directions are not symmetric. 2.0's CRF and eDT both mean
# "collected", so an upgrade folds them together and loses which; a downgrade
# can only pick one back, and CRF is the overwhelmingly common source. 2.1's
# "Not Available" and "Other" have NO 2.0 spelling at all, so those refuse
# rather than being silently recorded as something the sponsor did not say.
.dx_origin_upgrade <- c(CRF = "Collected", eDT = "Collected")
.dx_origin_downgrade <- c(Collected = "CRF")

#' @noRd
.dx_origin_type <- function(value, p, call = rlang::caller_env()) {
  v <- trimws(value)
  allowed <- p$enum$origin_type
  if (is.null(allowed) || v %in% allowed) {
    return(.dx_enum(v, allowed, "def:Origin Type", call))
  }
  hit <- c(.dx_origin_upgrade, .dx_origin_downgrade)[v]
  if (!is.na(hit) && unname(hit) %in% allowed) {
    return(unname(hit))
  }
  .dx_enum(v, allowed, "def:Origin Type", call)
}

# def:Origin. Type is required in 2.1, so an origin description or CRF page
# with no type is refused rather than emitted as an untyped origin that no
# reviewer tool can interpret.
#' @noRd
.dx_origin <- function(row, p, label, call = rlang::caller_env()) {
  desc <- .dx_desc(row$origin_description)
  ref <- .dx_docref(
    row$origin_document_id,
    row$pages,
    row$page_type,
    p,
    call,
    title = row$page_title
  )
  if (.dx_blank(row$origin)) {
    if (is.null(desc) && is.null(ref)) {
      return(NULL)
    }
    .artoo_abort(
      c(
        "{label} carries origin detail but no origin type.",
        "x" = "{.code def:Origin/@Type} is required in Define-XML.",
        "i" = "Set {.code origin} on the row, or clear its origin description and pages."
      ),
      kind = "define",
      call = call
    )
  }
  # @Source is 2.1-only, and it is a LOCAL attribute on def:Origin -- written
  # unprefixed -- so the emitter's def: guard cannot see it. A NULL vocabulary
  # in the profile is how a builder learns the attribute does not exist.
  #
  # Exactly two local attributes differ between the versions: this one and
  # def:PDFPageRef/@Title, which artoo does not emit. A test re-derives that
  # pair from the bundled XSDs, so a third would fail there rather than at a
  # schema gate.
  source_attr <- if (!("Source" %in% p$local_attrs[["def:Origin"]])) {
    list()
  } else {
    .dx_attrs(
      Source = .dx_enum(
        row$source,
        p$enum$origin_source,
        "def:Origin Source",
        call
      )
    )
  }
  .dx_node(
    "def:Origin",
    attrs = c(
      .dx_attrs(Type = .dx_origin_type(row$origin, p, call)),
      source_attr
    ),
    kids = list(Description = desc, `def:DocumentRef` = ref)
  )
}

#' @noRd
.dx_itemdef <- function(row, p, call = rlang::caller_env()) {
  label <- sprintf("ItemDef %s", row$oid)
  .dx_node(
    "ItemDef",
    attrs = .dx_attrs(
      OID = row$oid,
      Name = row$name,
      DataType = row$data_type,
      Length = row$length,
      SignificantDigits = row$significant_digits,
      SASFieldName = row$sas_field_name,
      "def:DisplayFormat" = row$display_format,
      "def:CommentOID" = row$comment_id
    ),
    kids = list(
      Description = .dx_desc(row$label),
      CodeListRef = if (.dx_blank(row$codelist_id)) {
        NULL
      } else {
        .dx_node(
          "CodeListRef",
          attrs = .dx_attrs(CodeListOID = row$codelist_id)
        )
      },
      Alias = .dx_alias_node(row$alias_context, row$alias_name),
      `def:Origin` = .dx_origin(row, p, label, call),
      `def:ValueListRef` = if (.dx_blank(row$value_list_id)) {
        NULL
      } else {
        .dx_node(
          "def:ValueListRef",
          attrs = .dx_attrs(ValueListOID = row$value_list_id)
        )
      }
    )
  )
}

# ---- codelists ------------------------------------------------------------

#' @noRd
.dx_codelist <- function(cl, p, call = rlang::caller_env()) {
  id <- .dx_one(cl$codelist_id)
  name <- .dx_one(.dx_chr(cl, "name"))
  dtype <- .dx_one(.dx_chr(cl, "data_type"))
  dtype <- if (.dx_blank(dtype)) "text" else .to_define_datatype(dtype)
  # A term with a decode is a CodeListItem; one without is an EnumeratedItem.
  # The schema offers a choice between the two, not a mixture, so the whole
  # list follows whichever its terms need.
  # An empty decode is not an absent one: a document may carry
  # <Decode><TranslatedText/></Decode>, and that is a decoded term with
  # nothing to say. Only NA means the source gave no decode at all.
  decodes <- .dx_chr(cl, "decode")
  decoded <- any(!is.na(decodes))
  if (decoded) {
    undecoded <- is.na(decodes)
    if (any(undecoded)) {
      terms <- as.character(cl$term)[undecoded]
      .artoo_abort(
        c(
          "Codelist {.val {id}} decodes some terms and not others.",
          "x" = "{length(terms)} term{?s} carr{?ies/y} no decode: {.val {terms}}.",
          "i" = "A CodeListItem requires a Decode, so give every term one, or clear them all and emit an enumerated list."
        ),
        kind = "codelist",
        call = call
      )
    }
  }
  ord <- .dx_row_order(cl)
  terms <- lapply(ord, function(i) .dx_codelist_term(cl, i, decoded, p))
  kids <- list(
    Description = NULL,
    Alias = .dx_alias_node("nci:ExtCodeID", .dx_one(.dx_chr(cl, "nci_code")))
  )
  kids[[if (decoded) "CodeListItem" else "EnumeratedItem"]] <- terms
  .dx_node(
    "CodeList",
    attrs = c(
      .dx_attrs(
        OID = id,
        Name = if (.dx_blank(name)) id else name,
        DataType = .dx_enum(
          dtype,
          p$enum$cl_data_type,
          "CodeList DataType",
          call
        ),
        SASFormatName = .dx_one(.dx_chr(cl, "sas_format_name"))
      ),
      # CodeList carries NO def: attribute in 2.0 -- not even def:CommentOID,
      # which is legal there on every other element. One global set of legal
      # attributes would pass exactly this document.
      .dx_only(
        p,
        "CodeList",
        "def:StandardOID" = .dx_one(.dx_chr(cl, "standard_id")),
        "def:IsNonStandard" = .dx_yesonly(.dx_lgl(cl, "is_non_standard")),
        "def:CommentOID" = .dx_one(.dx_chr(cl, "comment_id"))
      )
    ),
    kids = kids
  )
}

#' @noRd
.dx_codelist_term <- function(cl, i, decoded, p) {
  el <- if (decoded) "CodeListItem" else "EnumeratedItem"
  kids <- list(
    Alias = .dx_alias_node("nci:ExtCodeID", .dx_chr(cl, "term_nci_code")[[i]])
  )
  if (decoded) {
    kids$Decode <- .dx_node(
      "Decode",
      kids = list(
        TranslatedText = .dx_node(
          "TranslatedText",
          attrs = list(`xml:lang` = "en"),
          text = as.character(.dx_chr(cl, "decode")[[i]])
        )
      )
    )
  }
  # 2.1 adds a term-level Description; the 2.0 profile does not list it, so
  # emitting it there would abort at build time rather than fail validation.
  if (!is.null(p$order[[el]]) && "Description" %in% p$order[[el]]) {
    kids$Description <- .dx_desc(.dx_chr(cl, "term_description")[[i]])
  }
  .dx_node(
    el,
    attrs = .dx_attrs(
      CodedValue = cl$term[[i]],
      Rank = .dx_chr(cl, "rank")[[i]],
      OrderNumber = .dx_chr(cl, "order")[[i]],
      "def:ExtendedValue" = .dx_yesonly(.dx_lgl(cl, "extended")[[i]])
    ),
    kids = kids
  )
}

# ---- methods / comments ---------------------------------------------------

#' @noRd
.dx_method <- function(md, i, expressions, p, call = rlang::caller_env()) {
  id <- md$method_id[[i]]
  name <- .dx_chr(md, "name")[[i]]
  desc <- .dx_chr(md, "description")[[i]]
  type <- .dx_chr(md, "type")[[i]]
  fes <- expressions[expressions$method_id == id, , drop = FALSE]
  .dx_node(
    "MethodDef",
    attrs = .dx_attrs(
      OID = id,
      Name = if (.dx_blank(name)) id else name,
      # Type is required and closed to Computation / Imputation; a derivation
      # is a computation unless the spec says otherwise. ODM's own schema also
      # accepts Transpose and Other, which Define-XML forbids, so the gate
      # cannot catch a wrong one.
      Type = if (.dx_blank(type)) {
        "Computation"
      } else {
        .dx_enum(trimws(type), p$enum$method_type, "MethodDef Type", call)
      }
    ),
    kids = list(
      # Description is required on MethodDef, so an undescribed method falls
      # back to its name rather than emitting an empty element.
      Description = .dx_desc(
        if (.dx_blank(desc)) {
          if (.dx_blank(name)) id else name
        } else {
          desc
        }
      ),
      FormalExpression = lapply(.dx_row_order(fes), function(j) {
        .dx_node(
          "FormalExpression",
          attrs = .dx_attrs(Context = fes$context[[j]]),
          text = as.character(fes$code[[j]])
        )
      }),
      `def:DocumentRef` = .dx_docref(
        .dx_chr(md, "document_id")[[i]],
        .dx_chr(md, "pages")[[i]],
        .dx_chr(md, "page_type")[[i]],
        p,
        call,
        title = .dx_chr(md, "page_title")[[i]]
      )
    )
  )
}

#' @noRd
.dx_comment <- function(cm, i, p, call = rlang::caller_env()) {
  .dx_node(
    "def:CommentDef",
    attrs = .dx_attrs(OID = cm$comment_id[[i]]),
    kids = list(
      # Description is required on def:CommentDef. A workbook that carries a
      # comment id with no text is an ordinary input, so this falls back to
      # the id rather than emitting an element the schema refuses; the
      # missing column is named up front by .dx_incomplete_notice().
      Description = .dx_desc({
        text <- .dx_chr(cm, "description")[[i]]
        if (.dx_blank(text)) cm$comment_id[[i]] else text
      }),
      `def:DocumentRef` = .dx_docref(
        .dx_chr(cm, "document_id")[[i]],
        .dx_chr(cm, "pages")[[i]],
        .dx_chr(cm, "page_type")[[i]],
        p,
        call,
        title = .dx_chr(cm, "page_title")[[i]]
      )
    )
  )
}
