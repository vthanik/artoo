# a dataset with neither structure nor keys is refused

    Code
      write_spec(spec, path, created = FROZEN)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$label", "datasets$class", "datasets$domain", "datasets$purpose", "datasets$repeating", "datasets$structure", "datasets$archive_location_id", "variables$label", "variables$origin", "variables$length", and "the CDISC standard".
      i A conformance report will raise 11 findings; fill them in the source spec.
      Error:
      ! Dataset "DM" has no structure.
      x Define-XML requires `def:Structure` on every ItemGroupDef.
      i Set `structure` on the datasets table, or give the dataset keys.

# a value-level row qualifying an absent variable is refused

    Code
      write_spec(spec, path, created = FROZEN)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$label", "datasets$class", "datasets$domain", "datasets$purpose", "datasets$repeating", "datasets$archive_location_id", "variables$label", "variables$origin", "variables$length", "values$label", "values$origin", "values$length", and "the CDISC standard".
      i A conformance report will raise 13 findings; fill them in the source spec.
      Error:
      ! 1 value-level row qualifies a variable the spec does not carry.
      x "VS.VSORRES".
      i A def:ValueListDef hangs off its parent ItemDef, so the variable must be in the spec.

# an invalid document never replaces the target file

    Code
      write_spec(small_spec(), path, created = FROZEN)
    Condition
      Error:
      ! The Define-XML artoo built is not schema-valid, so '<tmp>/define.xml' was not written.
      x 1 schema error, first: "Element 'ItemDef': something is wrong.".
      i This is an artoo defect; the spec that produced it is worth attaching to a report.

# a codelist that decodes only some of its terms is refused (#p4-review)

    Code
      write_spec(spec, path, created = FROZEN)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$label", "datasets$class", "datasets$domain", "datasets$purpose", "datasets$repeating", "datasets$archive_location_id", "variables$label", "variables$origin", "variables$length", "codelists$nci_code", and "the CDISC standard".
      i A conformance report will raise 11 findings; fill them in the source spec.
      Error:
      ! Codelist "CL.SEX" decodes some terms and not others.
      x 1 term carries no decode: "U".
      i A CodeListItem requires a Decode, so give every term one, or clear them all and emit an enumerated list.

# several def:WhereClauseRefs on one item are refused, not narrowed

    Code
      suppressWarnings(read_spec(src))
    Condition
      Error:
      ! '<tmp>/or.xml' has a value-level item selected by more than one where clause.
      x "WC.ADQSADAS.AVAL.ACITM01-ACITM14" and "WC.ADQSADAS.AVAL.ACITM01-ACITM14" are combined with OR, and artoo carries one clause per value-level row.
      i Merge them into one def:WhereClauseDef, or split the item into one row per clause.

# a spec declaring a version artoo cannot write is refused

    Code
      artoo:::.dx_target_version(NULL, spec)
    Condition
      Error:
      ! The spec declares Define-XML version "1.0.0".
      x artoo writes "2.0" and "2.1".
      i Pass `version` to write it as one of those anyway.

# a downgrade says once what it cannot carry

    Code
      spec <- write_spec(read_define("define21-sdtm.xml"), path, version = "2.0",
      created = FROZEN)
    Condition
      Warning:
      Define-XML 2.0 cannot carry everything this spec holds.
      x Dropped or rewritten: "def:Standards (only the primary standard survives)", "def:StandardOID", "def:IsNonStandard", "def:HasNoData", "def:Origin/@Source", "ODM/@def:Context", and "Collected origins, rewritten as CRF".
      i Write the spec as "2.1", or to native JSON, to keep it whole.

# 2.0 refuses a spec that names no standard at all

    Code
      write_spec(spec, path, version = "2.0", created = FROZEN)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$label", "datasets$class", "datasets$domain", "datasets$purpose", "datasets$repeating", "datasets$archive_location_id", "variables$label", "variables$origin", "variables$length", and "the CDISC standard".
      i A conformance report will raise 10 findings; fill them in the source spec.
      Error in `.dx_metadata_version()`:
      ! Define-XML 2.0 needs a standard name and version.
      x The spec names no standard.
      i Set `standard` to a name and a version, or flag a `standards` row `is_primary`.

# a one-token standard is refused, not blamed on artoo (#p5-review-2)

    Code
      write_spec(spec, path, version = "2.0", created = FROZEN)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$label", "datasets$class", "datasets$domain", "datasets$purpose", "datasets$repeating", "datasets$archive_location_id", "variables$label", "variables$origin", and "variables$length".
      i A conformance report will raise 9 findings; fill them in the source spec.
      Error in `.dx_metadata_version()`:
      ! Define-XML 2.0 needs a standard name and version.
      x `standard` is "SDTMIG", which names no version.
      i Set `standard` to a name and a version, or flag a `standards` row `is_primary`.

# a value-level row's origin source counts as a downgrade loss

    Code
      spec <- write_spec(spec, path, version = "2.0", created = FROZEN)
    Condition
      Warning:
      The spec is not submission-grade.
      x Nothing fills "datasets$label", "datasets$class", "datasets$domain", "datasets$purpose", "datasets$repeating", "datasets$archive_location_id", "variables$label", "variables$origin", "variables$length", "values$label", and "values$length".
      i A conformance report will raise 11 findings; fill them in the source spec.
      Warning:
      Define-XML 2.0 cannot carry everything this spec holds.
      x Dropped or rewritten: "def:Origin/@Source" and "Collected origins, rewritten as CRF".
      i Write the spec as "2.1", or to native JSON, to keep it whole.

