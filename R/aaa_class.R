# aaa_class.R -- S7 class definitions, loaded first (aaa_ prefix).
#
# Two classes: `artoo_spec` (the CDISC specification) and `artoo_meta`
# (the metadata a dataset carries -- the codec contract). Both validate
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
  comment_id = "character"
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
  role = "character"
)
.spec_req_variables <- c("dataset", "variable", "data_type")

.spec_cols_codelists <- c(
  codelist_id = "character",
  term = "character",
  decode = "character",
  order = "integer",
  extended = "logical",
  comment_id = "character"
)
.spec_req_codelists <- c("codelist_id", "term")

# Methods, comments, documents -- the Define-XML supporting metadata that
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
  pages = "character"
)
.spec_req_methods <- c("method_id")

.spec_cols_comments <- c(
  comment_id = "character",
  description = "character",
  document_id = "character",
  pages = "character"
)
.spec_req_comments <- c("comment_id")

.spec_cols_documents <- c(
  document_id = "character",
  title = "character",
  href = "character"
)
.spec_req_documents <- c("document_id")

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
    # standards aborts at construction -- see .resolve_standard().
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
    values = S7::new_property(S7::class_any, default = NULL)
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
