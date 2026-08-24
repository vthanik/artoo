# dropping an external codelist is reported, not silent (#p4-review)

    Code
      spec <- read_spec(test_path("fixtures", "define20-sdtm.xml"))
    Condition
      Warning:
      3 external codelists in 'define20-sdtm.xml' dropped.
      x "MEDDRA", "WHODRUG", and "ISO3166": artoo does not model external dictionaries yet.
      i Their references are dropped too, so writing this spec back will not reproduce them.

# dropping a second def:Origin is reported, not silent (#p4-review)

    Code
      spec <- read_spec(src)
    Condition
      Warning:
      1 ItemDef carries more than one `def:Origin`.
      x In 'two-origins.xml', only the first is read: "IT.DM.USUBJID".
      i Writing this spec back will not reproduce the others.

