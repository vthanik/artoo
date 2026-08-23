# aaa_class.R — S7 class definitions, loaded first (aaa_ prefix).
#
# Two classes: `artoo_spec` (the CDISC specification) and `artoo_meta`
# (the metadata a dataset carries — the codec contract). Both validate
# at construction. The per-slot column schemas and closed vocabularies
# below are the single source of truth; adding a column is a one-line
# edit here.

# ---- Closed vocabularies (CDISC Dataset-JSON v1.1) -----------------------

# Canonical variable types == Dataset-JSON `dataType` (verified against
# the CDISC spec; do not invent a artoo-private set).
.cdisc_datatypes <- c(
  "string",
  "integer",
  "decimal",
  "float",
  "double",
  "boolean",
  "date",
  "datetime",
  "time",
  "URI"
)

# `targetDataType`: physical storage when it differs from `dataType`
# (e.g. an ADaM numeric date is dataType "date", targetDataType "integer").
.cdisc_targettypes <- c("integer", "decimal")

# ---- Per-slot column schemas: name -> required storage mode --------------
# `req` lists the columns a slot MUST carry; the rest are optional and are
# filled with a typed NA at construction.

.spec_cols_datasets <- c(
  dataset = "character",
  label = "character",
  class = "character",
  subclass = "character",
  structure = "character",
  keys = "character",
  comment_id = "character",
  # ---- Define-XML ItemGroupDef attributes ----
  # Carried so a written define.xml can be submission-grade rather than
  # merely schema-valid: Pinnacle 21 treats most of these as required even
  # though the XSD marks them optional.
  itemgroupoid = "character", # ItemGroupDef/@OID            both
  domain = "character", # @Domain                      both
  sas_dataset_name = "character", # @SASDatasetName              both
  repeating = "logical", # @Repeating (schema-required) both
  reference_data = "logical", # @IsReferenceData             both
  purpose = "character", # @Purpose                     both
  archive_location_id = "character", # @def:ArchiveLocationID       both
  standard_id = "character", # @def:StandardOID             2.1
  is_non_standard = "logical", # @def:IsNonStandard           2.1
  has_no_data = "logical", # @def:HasNoData               2.1
  alias_context = "character", # Alias/@Context               both
  alias_name = "character", # Alias/@Name                  both
  order = "integer" # emission order            artoo
)
.spec_req_datasets <- c("dataset")

.spec_cols_variables <- c(
  dataset = "character",
  variable = "character",
  itemoid = "character",
  label = "character",
  data_type = "character",
  target_data_type = "character",
  length = "integer",
  display_format = "character",
  informat = "character",
  key_sequence = "integer",
  order = "integer",
  codelist_id = "character",
  method_id = "character",
  comment_id = "character",
  mandatory = "logical",
  significant_digits = "integer",
  origin = "character",
  source = "character",
  predecessor = "character",
  assigned_value = "character",
  pages = "character",
  role = "character",
  # ---- Define-XML ItemDef / ItemRef additions ----
  sas_field_name = "character", # ItemDef/@SASFieldName             both
  value_list_id = "character", # def:ValueListRef/@ValueListOID    both
  origin_description = "character", # def:Origin/Description            both
  origin_document_id = "character", # def:Origin//def:DocumentRef@leafID both
  page_type = "character", # def:PDFPageRef/@Type              both
  role_codelist_id = "character", # ItemRef/@RoleCodeListOID          both
  is_non_standard = "logical", # ItemRef/@def:IsNonStandard        2.1
  has_no_data = "logical", # ItemRef/@def:HasNoData            2.1
  alias_context = "character", # ItemDef/Alias/@Context            both
  alias_name = "character" # ItemDef/Alias/@Name               both
)
.spec_req_variables <- c("dataset", "variable", "data_type")

# Codelists are one row per TERM, so the list-level attributes below repeat
# on every term row of the same codelist. That matches the shape of the source
# workbook, which also repeats them, and it keeps the slot a plain rectangle;
# .spec_validate() checks they agree within a codelist so the duplication
# cannot drift.
.spec_cols_codelists <- c(
  codelist_id = "character",
  term = "character",
  decode = "character",
  order = "integer",
  extended = "logical",
  comment_id = "character",
  # ---- list-level, repeated on each term row ----
  name = "character", # CodeList/@Name (required)     both
  data_type = "character", # CodeList/@DataType (required) both
  sas_format_name = "character", # @SASFormatName                both
  nci_code = "character", # Alias[nci:ExtCodeID]/@Name    both
  standard_id = "character", # @def:StandardOID              2.1
  is_non_standard = "logical", # @def:IsNonStandard            2.1
  # ---- term-level ----
  term_nci_code = "character", # CodeListItem Alias/@Name      both
  rank = "integer", # CodeListItem/@Rank            both
  term_description = "character" # CodeListItem/Description      2.1
)
.spec_req_codelists <- c("codelist_id", "term")

# Methods, comments, documents — the Define-XML supporting metadata that
# variables / value-level rows reference by id. Carried so validation can
# check completeness (e.g. a referenced method's description is present)
# and referential integrity.
.spec_cols_methods <- c(
  method_id = "character",
  name = "character",
  type = "character",
  description = "character",
  expression_context = "character",
  expression_code = "character",
  document_id = "character",
  pages = "character",
  page_type = "character" # def:PDFPageRef/@Type
)
.spec_req_methods <- c("method_id")

.spec_cols_comments <- c(
  comment_id = "character",
  description = "character",
  document_id = "character",
  pages = "character",
  page_type = "character" # def:PDFPageRef/@Type
)
.spec_req_comments <- c("comment_id")

.spec_cols_documents <- c(
  document_id = "character",
  title = "character",
  href = "character",
  # Which MetaDataVersion container owns this leaf: annotated_crf,
  # supplemental, archive, or other. Read off the container rather than
  # guessed from the filename -- a title-regex heuristic writes a different
  # document than it read, because a leaf referenced only from def:Origin
  # sits in no container at all.
  role = "character"
)
.spec_req_documents <- c("document_id")

# ---- Slots that need their own table -------------------------------------
# These carry structure a rectangle on an existing slot cannot hold, so each
# is its own S7 property. They all land in ONE release deliberately: an S7
# object embeds a copy of its class, so every property addition strands every
# previously-saved spec, and one migration covers N properties exactly as
# cheaply as it covers one.

# def:Standards (2.1). Define-XML 2.0 instead carries a single
# def:StandardName + def:StandardVersion pair on MetaDataVersion, which is
# derived from the row flagged `is_primary` when writing 2.0.
.spec_cols_standards <- c(
  standard_id = "character", # def:Standard/@OID
  name = "character", # @Name
  type = "character", # @Type: IG or CT
  version = "character", # @Version
  status = "character", # @Status
  publishing_set = "character", # @PublishingSet (Type = "CT" only)
  comment_id = "character", # @def:CommentOID
  is_primary = "logical", # artoo: which IG becomes 2.0's single pair
  order = "integer"
)
.spec_req_standards <- c("standard_id", "name", "version")

# def:WhereClauseDef, fully normalised: one row per CheckValue.
# A CheckValue is free text and CAN contain a comma or a space (the CDISC
# example carries "LOCAL LAB"), so any collapsed encoding is lossy.
.spec_cols_where_clauses <- c(
  where_clause_id = "character", # def:WhereClauseDef/@OID
  check_order = "integer", # RangeCheck index within the clause
  dataset = "character", # human-writable target
  variable = "character", # human-writable target
  itemoid = "character", # RangeCheck/@def:ItemOID (authoritative)
  comparator = "character", # @Comparator
  soft_hard = "character", # @SoftHard
  value = "character", # CheckValue text
  value_order = "integer", # CheckValue index within the RangeCheck
  comment_id = "character" # @def:CommentOID (2.1)
)
.spec_req_where_clauses <- c("where_clause_id", "comparator")

# MethodDef/FormalExpression, 0..n per method. A separate table rather than
# extra rows on `methods`, because validate_spec() already publishes a
# method_id_unique rule and repeating the id would silently change what that
# rule means.
.spec_cols_method_expressions <- c(
  method_id = "character",
  order = "integer",
  context = "character", # FormalExpression/@Context
  code = "character" # the expression body
)
.spec_req_method_expressions <- c("method_id")

# Analysis Results Metadata (ARM v1.0). Version-neutral: the arm: vocabulary
# is identical for Define-XML 2.0 and 2.1, only the namespace binding differs.
.spec_cols_arm_displays <- c(
  display_id = "character", # arm:ResultDisplay/@OID
  name = "character", # @Name
  description = "character",
  document_id = "character",
  pages = "character",
  page_type = "character",
  order = "integer"
)
.spec_req_arm_displays <- c("display_id")

# Grain is one row per (result x analysis dataset), because an
# arm:AnalysisDataset carries its own def:WhereClauseRef and a delimited
# string cannot express that.
.spec_cols_arm_results <- c(
  display_id = "character",
  result_id = "character", # arm:AnalysisResult/@OID
  name = "character",
  description = "character",
  parameter_id = "character", # @ParameterOID
  reason = "character", # @AnalysisReason
  purpose = "character", # @AnalysisPurpose
  dataset = "character", # arm:AnalysisDataset/@ItemGroupOID
  variables = "character", # space-separated arm:AnalysisVariable names
  where_clause_id = "character",
  datasets_comment_id = "character",
  documentation = "character",
  documentation_document_id = "character",
  documentation_pages = "character",
  programming_context = "character",
  programming_code = "character",
  programming_document_id = "character",
  order = "integer"
)
.spec_req_arm_results <- c("display_id", "result_id")

# External codelists (MedDRA, WHODrug, ISO 3166). RESERVED, not yet
# populated: dictionaries are out of scope for this release, but the property
# is added now because the expensive half of the feature is the property, not
# the code. Adding it later would strand every spec saved in between.
.spec_cols_dictionaries <- c(
  dictionary_id = "character", # CodeList/@OID
  name = "character", # @Name
  data_type = "character", # @DataType
  dictionary = "character", # ExternalCodeList/@Dictionary
  version = "character", # @Version
  href = "character",
  ref = "character"
)
.spec_req_dictionaries <- c("dictionary_id")

# Value-level metadata finally gets a column schema. It stays class_any on
# the S7 property so is.null(x@values) keeps meaning "no VLM", but when
# present it is coerced to this shape.
.spec_cols_values <- c(
  dataset = "character",
  variable = "character",
  where_clause_id = "character", # def:WhereClauseRef/@WhereClauseOID
  where_clause = "character", # rendered display text (derived)
  value_list_id = "character", # def:ValueListDef/@OID
  itemoid = "character",
  label = "character",
  data_type = "character",
  length = "integer",
  significant_digits = "integer",
  display_format = "character",
  codelist_id = "character",
  method_id = "character",
  comment_id = "character",
  order = "integer",
  mandatory = "logical",
  origin = "character",
  source = "character",
  predecessor = "character",
  assigned_value = "character",
  pages = "character",
  sas_field_name = "character"
)
.spec_req_values <- c("dataset", "variable")

# ---- S7 classes ----------------------------------------------------------

# The S7 artoo_spec class. Internal: the public face is artoo_spec()
# (constructor) and is_artoo_spec() (predicate). Slots: study, datasets,
# variables, codelists (plain data frames so they stay dplyr/base-friendly)
# and values (optional VLM). Validated by .spec_validate().
#' @noRd
artoo_spec_class <- S7::new_class(
  "artoo_spec",
  package = "artoo",
  properties = list(
    # One spec = one CDISC standard (scalar; NA when unspecified). Mixing
    # standards aborts at construction — see .resolve_standard().
    standard = S7::new_property(
      S7::class_character,
      default = NA_character_
    ),
    study = S7::class_data.frame,
    datasets = S7::class_data.frame,
    variables = S7::class_data.frame,
    codelists = S7::class_data.frame,
    methods = S7::class_data.frame,
    comments = S7::class_data.frame,
    documents = S7::class_data.frame,
    values = S7::new_property(S7::class_any, default = NULL),
    standards = S7::class_data.frame,
    where_clauses = S7::class_data.frame,
    method_expressions = S7::class_data.frame,
    arm_displays = S7::class_data.frame,
    arm_results = S7::class_data.frame,
    dictionaries = S7::class_data.frame
  ),
  validator = function(self) {
    .spec_validate(self)
  }
)

# The S7 artoo_meta class (the codec contract): dataset-level fields plus
# one entry per column, in the CDISC Dataset-JSON vocabulary. Internal;
# bridged to a data frame's attributes by get_meta()/set_meta() (Phase 2).
# Validated by .meta_validate().
#' @noRd
artoo_meta_class <- S7::new_class(
  "artoo_meta",
  package = "artoo",
  properties = list(
    # dataset-level: itemGroupOID, name, label, records, studyOID, ...
    dataset = S7::new_property(S7::class_list, default = list()),
    # per-column, keyed by name: itemOID, label, dataType, targetDataType,
    # length, displayFormat, keySequence (+ codelist, significantDigits)
    columns = S7::new_property(S7::class_list, default = list())
  ),
  validator = function(self) {
    .meta_validate(self)
  }
)

# The S7 artoo_check class: the result of validate_spec(). Stores the
# findings table, the validated scope (dataset names), and a short study
# label for the report header. Printed as a sectioned text report by the
# print/format methods (see validate_spec.R); @findings stays a plain data
# frame for programmatic use.
#' @noRd
artoo_check_class <- S7::new_class(
  "artoo_check",
  package = "artoo",
  properties = list(
    findings = S7::class_data.frame,
    scope = S7::new_property(S7::class_character, default = character(0)),
    study = S7::new_property(S7::class_character, default = "(unspecified)"),
    summary = S7::new_property(S7::class_list, default = list())
  ),
  validator = function(self) {
    need <- c(
      "check",
      "dimension",
      "severity",
      "dataset",
      "variable",
      "message"
    )
    miss <- setdiff(need, names(self@findings))
    if (length(miss)) {
      return(paste0(
        "@findings is missing column(s): ",
        paste(miss, collapse = ", "),
        "."
      ))
    }
    sev <- self@findings$severity
    if (length(sev) && !all(sev %in% c("error", "warning", "note"))) {
      return("@findings$severity must be one of error, warning, note.")
    }
    NULL
  }
)
