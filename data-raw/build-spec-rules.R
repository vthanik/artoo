# build-spec-rules.R -- generate inst/spec_rules.json, the open catalog of
# every spec-validation check vport runs (and the rules it defers).
#
# Hand-authored (no external rule catalog is copied or shipped); vport uses
# its OWN behavioral check ids -- never another tool's rule numbering.
# Re-run after adding/removing a check:
#   Rscript data-raw/build-spec-rules.R
# A parity test asserts the implemented ids here == the ids the engine emits.

stopifnot(requireNamespace("jsonlite", quietly = TRUE))

rule <- function(
  id,
  dimension,
  severity,
  description,
  requires_data = FALSE,
  scope = "scoped",
  status = "implemented",
  reason = NA_character_
) {
  data.frame(
    id = id,
    dimension = dimension,
    severity = severity,
    requires_data = requires_data,
    scope = scope,
    status = status,
    description = description,
    reason = reason,
    stringsAsFactors = FALSE
  )
}

rules <- rbind(
  # ---- study ----
  rule(
    "study_name_present",
    "study",
    "warning",
    "The study-level metadata carries no study name."
  ),

  # ---- dataset ----
  rule(
    "dataset_label_present",
    "dataset",
    "warning",
    "A dataset has no label."
  ),
  rule(
    "dataset_keys_resolve",
    "dataset",
    "error",
    "A dataset's key variables are not all defined in the spec."
  ),
  rule(
    "dataset_comment_resolves",
    "dataset",
    "error",
    "A dataset references a comment id that is not defined."
  ),

  # ---- variable ----
  rule(
    "variable_label_present",
    "variable",
    "note",
    "A variable has no label."
  ),
  rule(
    "variable_length_positive",
    "variable",
    "error",
    "A variable has a non-positive length."
  ),
  rule(
    "variable_sigdigits_nonneg",
    "variable",
    "error",
    "A variable has negative significant digits."
  ),
  rule(
    "variable_method_resolves",
    "variable",
    "error",
    "A variable references a method id that is not defined."
  ),
  rule(
    "variable_comment_resolves",
    "variable",
    "error",
    "A variable references a comment id that is not defined."
  ),
  rule(
    "variable_derived_has_method",
    "variable",
    "warning",
    "A variable with Origin='Derived' has no method."
  ),

  rule(
    "variable_order_positive",
    "variable",
    "error",
    "A variable order is not a positive integer."
  ),
  rule(
    "variable_length_for_text",
    "variable",
    "warning",
    "A string/integer variable has no length."
  ),

  # ---- value-level ----
  rule(
    "value_whereclause_present",
    "value",
    "error",
    "A value-level row has no where-clause."
  ),
  rule(
    "value_variable_resolves",
    "value",
    "warning",
    "A value-level row names a variable not in the dataset."
  ),
  rule(
    "value_method_resolves",
    "value",
    "error",
    "A value-level row references a method id that is not defined."
  ),
  rule(
    "value_comment_resolves",
    "value",
    "error",
    "A value-level row references a comment id that is not defined."
  ),
  rule(
    "value_codelist_resolves",
    "value",
    "error",
    "A value-level row references a codelist id that is not defined."
  ),

  # ---- codelist ----
  rule(
    "codelist_comment_resolves",
    "codelist",
    "error",
    "A codelist references a comment id that is not defined."
  ),
  rule(
    "codelist_terms_present",
    "codelist",
    "warning",
    "A referenced codelist defines no terms."
  ),

  # ---- method ----
  rule(
    "method_id_unique",
    "method",
    "error",
    "A method id is defined more than once."
  ),
  rule(
    "method_description_present",
    "method",
    "warning",
    "A referenced method has a blank description."
  ),
  rule(
    "method_document_resolves",
    "method",
    "note",
    "A method references a document id that is not defined."
  ),

  # ---- comment ----
  rule(
    "comment_id_unique",
    "comment",
    "error",
    "A comment id is defined more than once."
  ),
  rule(
    "comment_description_present",
    "comment",
    "warning",
    "A referenced comment has a blank description."
  ),
  rule(
    "comment_document_resolves",
    "comment",
    "note",
    "A comment references a document id that is not defined."
  ),

  # ---- document ----
  rule(
    "document_id_unique",
    "document",
    "error",
    "A document id is defined more than once."
  ),

  # ---- unreferenced (whole-spec mode only) ----
  rule(
    "method_unused",
    "method",
    "note",
    "A method is defined but referenced by nothing.",
    scope = "whole-spec"
  ),
  rule(
    "comment_unused",
    "comment",
    "note",
    "A comment is defined but referenced by nothing.",
    scope = "whole-spec"
  ),
  rule(
    "document_unused",
    "document",
    "note",
    "A document is defined but referenced by nothing.",
    scope = "whole-spec"
  ),

  # ---- controlled terminology vs input data (requires data) ----
  rule(
    "ct_value_in_codelist",
    "ct",
    "warning",
    "A data value is not among the codelist's terms.",
    requires_data = TRUE
  ),
  rule(
    "ct_term_unused",
    "ct",
    "note",
    "A codelist term is defined in the spec but absent from the data.",
    requires_data = TRUE
  ),
  rule(
    "variable_present_in_data",
    "variable",
    "warning",
    "A spec variable has no column in the supplied data.",
    requires_data = TRUE
  ),

  # ---- deferred (transparent, not silently dropped) ----
  rule(
    "arm_result_metadata",
    "arm",
    "error",
    "Analysis Results Metadata integrity.",
    status = "deferred",
    reason = "needs ARM slots vport does not carry"
  ),
  rule(
    "codelist_term_standard_ct",
    "codelist",
    "warning",
    "Codelist term/decode is a valid NCI CT pair.",
    status = "deferred",
    reason = "needs a bundled NCI CT library"
  ),
  rule(
    "codelist_decode_present",
    "codelist",
    "note",
    "A coded term has no decoded value.",
    status = "deferred",
    reason = "cannot distinguish enumerated value lists (no decode expected) from coded terms"
  ),
  rule(
    "data_composite_key_unique",
    "dataset",
    "error",
    "No duplicate rows for the spec-declared composite key in data.",
    requires_data = TRUE,
    status = "deferred",
    reason = "in-data conformance beyond CT membership"
  )
)

out <- file.path("inst", "spec_rules.json")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
json <- jsonlite::toJSON(
  rules,
  dataframe = "rows",
  na = "null",
  auto_unbox = TRUE,
  pretty = TRUE
)
con <- file(out, open = "w", encoding = "UTF-8")
writeLines(json, con)
close(con)
message("Wrote ", out, " (", nrow(rules), " rules)")
