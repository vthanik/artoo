# aaa_class.R -- S7 class definitions, loaded first (aaa_ prefix).
#
# Two classes: `vport_spec` (the CDISC specification) and `vport_meta`
# (the metadata a dataset carries -- the codec contract). Both validate
# at construction. The per-slot column schemas and closed vocabularies
# below are the single source of truth; adding a column is a one-line
# edit here.

# ---- Closed vocabularies (CDISC Dataset-JSON v1.1) -----------------------

# Canonical variable types == Dataset-JSON `dataType` (verified against
# the CDISC spec; do not invent a vport-private set).
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

# SDTM/ADaM variable origin (Define-XML).
.vport_origin <- c(
  "Collected",
  "Derived",
  "Assigned",
  "Protocol",
  "Predecessor",
  NA
)

# Codelist decode no-match policy.
.vport_nomatch <- c("error", "keep", "na")

# ---- Per-slot column schemas: name -> required storage mode --------------
# `req` lists the columns a slot MUST carry; the rest are optional and are
# filled with a typed NA at construction.

.spec_cols_datasets <- c(
  dataset = "character",
  label = "character",
  class = "character",
  structure = "character",
  keys = "character"
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
  key_sequence = "integer",
  order = "integer",
  codelist_id = "character",
  mandatory = "logical",
  significant_digits = "integer",
  origin = "character"
)
.spec_req_variables <- c("dataset", "variable", "data_type")

.spec_cols_codelists <- c(
  codelist_id = "character",
  term = "character",
  decode = "character",
  order = "integer",
  extended = "logical"
)
.spec_req_codelists <- c("codelist_id", "term")

# ---- S7 classes ----------------------------------------------------------

# The S7 vport_spec class. Internal: the public face is vport_spec()
# (constructor) and is_vport_spec() (predicate). Slots: study, datasets,
# variables, codelists (plain data frames so they stay dplyr/base-friendly)
# and values (optional VLM). Validated by .spec_validate().
#' @noRd
vport_spec_class <- S7::new_class(
  "vport_spec",
  package = "vport",
  properties = list(
    study = S7::class_data.frame,
    datasets = S7::class_data.frame,
    variables = S7::class_data.frame,
    codelists = S7::class_data.frame,
    values = S7::new_property(S7::class_any, default = NULL)
  ),
  validator = function(self) {
    .spec_validate(self)
  }
)

# The S7 vport_meta class (the codec contract): dataset-level fields plus
# one entry per column, in the CDISC Dataset-JSON vocabulary. Internal;
# bridged to a data frame's attributes by get_meta()/set_meta() (Phase 2).
# Validated by .meta_validate().
#' @noRd
vport_meta_class <- S7::new_class(
  "vport_meta",
  package = "vport",
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
