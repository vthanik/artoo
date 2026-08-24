# define_profile.R — the Define-XML 2.0 / 2.1 version profiles.
#
# ONE data structure per version, holding everything the two standards
# disagree about: namespace URIs, the xs:sequence child order of every element
# artoo emits, the legal attribute set of every element, and the closed value
# vocabularies.
#
# The builders in define_build*.R are version-BLIND. They assemble a node spec
# with a NAMED child list and set attributes by name; the emitter consults this
# profile to decide the order children are written in and to reject anything
# the version does not allow. A version branch may live ONLY in a function
# named after the feature that differs -- .dx_class(), .dx_origin(),
# .dx_standard() -- never inside a builder.
#
# That is not stylistic. Element order in Define-XML is a schema-enforced
# xs:sequence, and the prior art emitted def:Class before ItemRef because the
# order lived in the statement sequence of a 2,000-line function, where
# nothing could check it. Here the order is DATA, so a builder cannot get it
# wrong: assigning node$kids[["def:Class"]] before or after the ItemRef slot
# produces byte-identical output.

.define_profile_versions <- c("2.0", "2.1")

# Child order for every element artoo emits, per version. Derived from the
# xs:sequence declarations in the bundled schemas; a test re-derives these
# from the XSDs so a future CDISC revision fails the test rather than the
# submission.
.dx_order_common <- list(
  ODM = c("Study"),
  Study = c("GlobalVariables", "MetaDataVersion"),
  GlobalVariables = c("StudyName", "StudyDescription", "ProtocolName"),
  ItemRef = c("def:WhereClauseRef"),
  ItemDef = c(
    "Description",
    "CodeListRef",
    "Alias",
    "def:Origin",
    "def:ValueListRef"
  ),
  CodeList = c("Description", "CodeListItem", "EnumeratedItem", "Alias"),
  MethodDef = c("Description", "FormalExpression", "Alias", "def:DocumentRef"),
  `def:CommentDef` = c("Description", "def:DocumentRef"),
  `def:WhereClauseDef` = c("RangeCheck"),
  RangeCheck = c("CheckValue"),
  `def:Origin` = c("Description", "def:DocumentRef"),
  `def:DocumentRef` = c("def:PDFPageRef"),
  `def:AnnotatedCRF` = c("def:DocumentRef"),
  `def:SupplementalDoc` = c("def:DocumentRef"),
  `def:leaf` = c("def:title"),
  Description = c("TranslatedText"),
  Decode = c("TranslatedText"),
  `def:PDFPageRef` = character(0),
  # Analysis Results Metadata. The 2.0 and 2.1 ARM schemas are identical
  # except for the def: namespace they import, so the whole vocabulary lives
  # here rather than in either profile.
  `arm:AnalysisResultDisplays` = c("arm:ResultDisplay"),
  `arm:ResultDisplay` = c(
    "Description",
    "def:DocumentRef",
    "arm:AnalysisResult"
  ),
  `arm:AnalysisResult` = c(
    "Description",
    "arm:AnalysisDatasets",
    "arm:Documentation",
    "arm:ProgrammingCode"
  ),
  `arm:AnalysisDatasets` = c("arm:AnalysisDataset"),
  `arm:AnalysisDataset` = c("def:WhereClauseRef", "arm:AnalysisVariable"),
  `arm:Documentation` = c("Description", "def:DocumentRef"),
  `arm:ProgrammingCode` = c("arm:Code", "def:DocumentRef")
)

.define_profiles <- list(
  "2.1" = list(
    version = "2.1",
    define_version = "2.1.0",
    odm_version = "1.3.2",
    asset_dir = "2.1.0",
    stylesheet = "define2-1.xsl",
    ns = c(
      odm = "http://www.cdisc.org/ns/odm/v1.3",
      def = "http://www.cdisc.org/ns/def/v2.1",
      xlink = "http://www.w3.org/1999/xlink",
      arm = "http://www.cdisc.org/ns/arm/v1.0"
    ),
    # def:Class is a CHILD ELEMENT here, positioned after every ItemRef and
    # before def:leaf.
    class_slot = "element",
    # def:DefineVersion is a PATTERN in 2.1 (2.1.0, 2.1.10, ...), so a
    # document's own revision is kept.
    define_version_fixed = FALSE,
    # The def:-namespaced attributes each element may carry. The emitter
    # refuses anything else, so a 2.1-only attribute cannot reach a 2.0
    # document and surface later as a schema error against a line number.
    #
    # PER ELEMENT, not one global set: def:CommentOID is legal in 2.0, but
    # not on CodeList, and a global set passes exactly that document.
    #
    # A test re-derives this from the bundled XSDs with comments stripped --
    # def:Label, def:DomainKeys and def:Rank are DECLARED in 2.0 but their
    # references are commented out as deprecated, so they are not usable.
    # LOCAL attributes -- written unprefixed, so the emitter's def: guard
    # cannot see them -- on the def: elements where the two versions differ.
    # Only those two elements are listed; a test asserts that is still the
    # whole difference. Builders gate by hand off this table.
    local_attrs = list(
      `def:Origin` = c("Source", "Type"),
      `def:PDFPageRef` = c("FirstPage", "LastPage", "PageRefs", "Title", "Type")
    ),
    def_attrs = list(
      CodeList = c("def:CommentOID", "def:IsNonStandard", "def:StandardOID"),
      CodeListItem = "def:ExtendedValue",
      EnumeratedItem = "def:ExtendedValue",
      ItemDef = c("def:CommentOID", "def:DisplayFormat"),
      ItemGroupDef = c(
        "def:ArchiveLocationID",
        "def:CommentOID",
        "def:HasNoData",
        "def:IsNonStandard",
        "def:StandardOID",
        "def:Structure"
      ),
      ItemRef = c("def:HasNoData", "def:IsNonStandard"),
      MetaDataVersion = c("def:CommentOID", "def:DefineVersion"),
      ODM = "def:Context",
      RangeCheck = "def:ItemOID",
      `def:Standard` = "def:CommentOID",
      `def:WhereClauseDef` = "def:CommentOID",
      `arm:AnalysisDatasets` = "def:CommentOID"
    ),
    order = c(
      .dx_order_common,
      list(
        MetaDataVersion = c(
          "def:Standards",
          "def:AnnotatedCRF",
          "def:SupplementalDoc",
          "def:ValueListDef",
          "def:WhereClauseDef",
          "ItemGroupDef",
          "ItemDef",
          "CodeList",
          "MethodDef",
          "def:CommentDef",
          "def:leaf",
          "arm:AnalysisResultDisplays"
        ),
        ItemGroupDef = c(
          "Description",
          "ItemRef",
          "Alias",
          "def:Class",
          "def:leaf"
        ),
        `def:ValueListDef` = c("Description", "ItemRef"),
        `def:Standards` = c("def:Standard"),
        # 2.1 adds an odm:Description to both term elements (term_description).
        CodeListItem = c("Decode", "Alias", "Description"),
        EnumeratedItem = c("Alias", "Description"),
        `def:Class` = c("def:SubClass"),
        # STRICTLY EMPTY in 2.1: a complexContent restriction, so any text or
        # child makes the document invalid.
        `def:WhereClauseRef` = character(0)
      )
    ),
    enum = list(
      context = c("Submission", "Other"),
      origin_type = c(
        "Assigned",
        "Collected",
        "Derived",
        "Not Available",
        "Other",
        "Predecessor",
        "Protocol"
      ),
      origin_source = c("Investigator", "Sponsor", "Subject", "Vendor"),
      standard_type = c("CT", "IG"),
      standard_status = c("Draft", "Final", "Provisional"),
      # 2.1 closes def:Standard/@Name to this list. 2.0 has no def:Standard
      # at all -- it carries a free-text name on MetaDataVersion -- so a 2.0
      # document read and written as 2.1 has to be reconciled against it.
      standard_name = c(
        "ADaMIG",
        "ADaMIG-MD",
        "BIMO",
        "CDISC/NCI",
        "SDTMIG",
        "SDTMIG-AP",
        "SDTMIG-MD",
        "SENDIG",
        "SENDIG-AR",
        "SENDIG-DART",
        "SENDIG-GENETOX"
      ),
      purpose = c("Tabulation", "Analysis"),
      method_type = c("Computation", "Imputation"),
      comparator = .wc_comparators,
      soft_hard = c("Soft", "Hard"),
      cl_data_type = c("integer", "float", "text", "string"),
      page_type = c("PhysicalRef", "NamedDestination"),
      class = c(
        "ADAM OTHER",
        "BASIC DATA STRUCTURE",
        "DEVICE LEVEL ANALYSIS DATASET",
        "EVENTS",
        "FINDINGS",
        "FINDINGS ABOUT",
        "INTERVENTIONS",
        "MEDICAL DEVICE BASIC DATA STRUCTURE",
        "MEDICAL DEVICE OCCURRENCE DATA STRUCTURE",
        "OCCURRENCE DATA STRUCTURE",
        "REFERENCE DATA STRUCTURE",
        "RELATIONSHIP",
        "SPECIAL PURPOSE",
        "STUDY REFERENCE",
        "SUBJECT LEVEL ANALYSIS DATASET",
        "TRIAL DESIGN"
      ),
      subclass = c(
        "ADVERSE EVENT",
        "MEDICAL DEVICE TIME-TO-EVENT",
        "NON-COMPARTMENTAL ANALYSIS",
        "POPULATION PHARMACOKINETIC ANALYSIS",
        "TIME-TO-EVENT"
      )
    )
  ),
  "2.0" = list(
    version = "2.0",
    # The 2.0 schema fixes this value, but libxml2 drops `fixed` through
    # xs:redefine, so the schema gate will NOT catch a wrong one. artoo
    # asserts it instead.
    define_version = "2.0.0",
    odm_version = "1.3.2",
    asset_dir = "2.0.0",
    stylesheet = "define2-0-0.xsl",
    ns = c(
      odm = "http://www.cdisc.org/ns/odm/v1.3",
      def = "http://www.cdisc.org/ns/def/v2.0",
      xlink = "http://www.w3.org/1999/xlink",
      arm = "http://www.cdisc.org/ns/arm/v1.0"
    ),
    # def:Class is an ATTRIBUTE here, and unconstrained odm:text.
    class_slot = "attribute",
    # 2.0 fixes def:DefineVersion at 2.0.0, but libxml2 drops `fixed` through
    # xs:redefine, so artoo asserts it rather than emitting whatever the spec
    # happens to carry.
    define_version_fixed = TRUE,
    local_attrs = list(
      `def:Origin` = "Type",
      `def:PDFPageRef` = c("FirstPage", "LastPage", "PageRefs", "Type")
    ),
    def_attrs = list(
      CodeListItem = "def:ExtendedValue",
      EnumeratedItem = "def:ExtendedValue",
      ItemDef = c("def:CommentOID", "def:DisplayFormat"),
      ItemGroupDef = c(
        "def:ArchiveLocationID",
        "def:Class",
        "def:CommentOID",
        "def:Structure"
      ),
      MetaDataVersion = c(
        "def:DefineVersion",
        "def:StandardName",
        "def:StandardVersion"
      ),
      RangeCheck = "def:ItemOID",
      `def:WhereClauseDef` = "def:CommentOID",
      `arm:AnalysisDatasets` = "def:CommentOID"
    ),
    order = c(
      .dx_order_common,
      list(
        MetaDataVersion = c(
          "def:AnnotatedCRF",
          "def:SupplementalDoc",
          "def:ValueListDef",
          "def:WhereClauseDef",
          "ItemGroupDef",
          "ItemDef",
          "CodeList",
          "MethodDef",
          "def:CommentDef",
          "def:leaf",
          "arm:AnalysisResultDisplays"
        ),
        ItemGroupDef = c("Description", "ItemRef", "Alias", "def:leaf"),
        `def:ValueListDef` = c("ItemRef"),
        CodeListItem = c("Decode", "Alias"),
        EnumeratedItem = c("Alias"),
        # simpleContent in 2.0, so text is permitted -- but artoo emits none.
        `def:WhereClauseRef` = character(0)
      )
    ),
    enum = list(
      context = NULL, # def:Context does not exist in 2.0
      origin_type = c(
        "CRF",
        "Derived",
        "Assigned",
        "Protocol",
        "eDT",
        "Predecessor"
      ),
      origin_source = NULL, # def:Origin/@Source does not exist in 2.0
      standard_type = NULL,
      standard_status = NULL,
      purpose = c("Tabulation", "Analysis"),
      method_type = c("Computation", "Imputation"),
      comparator = .wc_comparators,
      soft_hard = c("Soft", "Hard"),
      cl_data_type = c("integer", "float", "text", "string"),
      page_type = c("PhysicalRef", "NamedDestination"),
      class = NULL, # odm:text in 2.0: unconstrained
      subclass = NULL
    )
  )
)

#' @noRd
.define_profile <- function(version, call = rlang::caller_env()) {
  version <- as.character(version)
  if (
    length(version) != 1L ||
      is.na(version) ||
      !version %in% .define_profile_versions
  ) {
    known <- .define_profile_versions
    .artoo_abort(
      c(
        "{.arg version} must be {.val {known[1]}} or {.val {known[2]}}.",
        "x" = "You supplied {.val {version}}."
      ),
      kind = "input",
      call = call
    )
  }
  .define_profiles[[version]]
}

# Resolve the target version: an explicit argument wins, then the spec's own
# define_version, then 2.1. Defaulting to 2.1 rather than hardcoding it as the
# signature default keeps the two versions equal -- a hardcoded default is a
# quiet statement that one of them is the real target.
#
# NOT named .define_resolve_version(): define_validate.R already owns that
# name for the READER's version detection, and R would keep whichever file
# collated last.
#' @noRd
.dx_target_version <- function(version, spec, call = rlang::caller_env()) {
  if (!is.null(version)) {
    return(.define_profile(version, call)$version)
  }
  study <- spec@study
  if (nrow(study) && "define_version" %in% names(study)) {
    dv <- as.character(study$define_version[[1]])
    if (!is.na(dv) && nzchar(dv)) {
      if (startsWith(dv, "2.1")) {
        return("2.1")
      }
      if (startsWith(dv, "2.0")) {
        return("2.0")
      }
      # Silently writing a 1.0 spec as 2.1 would produce a document claiming
      # to be a version of something the source never was.
      known <- .define_profile_versions
      .artoo_abort(
        c(
          "The spec declares Define-XML version {.val {dv}}.",
          "x" = "artoo writes {.val {known}}.",
          "i" = "Pass {.arg version} to write it as one of those anyway."
        ),
        kind = "input",
        call = call
      )
    }
  }
  "2.1"
}

# Check a value against a closed vocabulary. A NULL vocabulary means the
# version does not constrain it.
#' @noRd
.dx_enum <- function(value, allowed, what, call = rlang::caller_env()) {
  if (is.null(allowed) || is.na(value) || !nzchar(value)) {
    return(value)
  }
  if (!value %in% allowed) {
    .artoo_abort(
      c(
        "{what} {.val {value}} is not allowed in this Define-XML version.",
        "i" = "Allowed: {.val {allowed}}."
      ),
      kind = "define",
      call = call
    )
  }
  value
}
