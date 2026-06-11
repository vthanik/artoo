# decode_column validates its inputs loudly

    Code
      decode_column(cdisc_dm, spec, "DM", from = "USUBJID", to = "USUBJ2")
    Condition
      Error:
      ! Neither "USUBJ2" nor "USUBJID" references a codelist in dataset "DM".
      i Add a codelist_id to one of them in the spec.

