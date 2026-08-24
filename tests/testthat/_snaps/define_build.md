# origin detail with no origin type is refused, not emitted untyped

    Code
      artoo:::.dx_origin(row, p21(), "ItemDef IT.DM.SEX")
    Condition
      Error:
      ! ItemDef IT.DM.SEX carries origin detail but no origin type.
      x `def:Origin/@Type` is required in Define-XML.
      i Set `origin` on the row, or clear its origin description and pages.

# a 2.1 origin with no 2.0 spelling is refused, not approximated

    Code
      artoo:::.dx_origin_type("Not Available", p20())
    Condition
      Error:
      ! def:Origin Type "Not Available" is not allowed in this Define-XML version.
      i Allowed: "CRF", "Derived", "Assigned", "Protocol", "eDT", and "Predecessor".

