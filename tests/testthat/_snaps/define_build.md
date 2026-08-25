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

# a duplicated coded value collapses only when its rows agree (#p12-final-2)

    Code
      suppressWarnings(artoo:::.dx_codelist(cl, p21()))
    Condition
      Error:
      ! Codelist "CL.AVISIT" defines 1 coded value more than one way.
      x "UNSCHEDULED".
      i Define-XML allows a coded value once per codelist; make the repeated rows agree, or drop the wrong ones.

# a repeated definition row collapses only when identical (#p12-final-2)

    Code
      artoo:::.dx_unique_defs(cm, "comment_id", "comment")
    Condition
      Error:
      ! 1 comment id is defined more than one way.
      x "COM.1".
      i Define-XML allows one definition per OID; make the repeated rows agree, or give them distinct ids.

