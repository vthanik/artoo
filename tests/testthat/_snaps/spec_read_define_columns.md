# dropping a second def:Origin is reported, not silent (#p4-review)

    Code
      spec <- read_spec(src)
    Condition
      Warning:
      1 ItemDef carries more than one `def:Origin`.
      x In 'two-origins.xml', only the first is read: "IT.DM.USUBJID".
      i Writing this spec back will not reproduce the others.

