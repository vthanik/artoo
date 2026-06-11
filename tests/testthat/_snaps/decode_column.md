# decode_column chains two hops when from and to codelists share no values

    Code
      decode_column(cdisc_dm, spec, "DM", from = "SEX", to = "SEXN", direction = "to_code")
    Condition
      Error:
      ! Values in `SEX` are not in codelist "SEXN".
      x Unmatched: "F" and "M".
      i Set `no_match = "keep"` or `"na"` to allow them.

# decode_column validates its inputs loudly

    Code
      decode_column(cdisc_dm, spec, "DM", from = "USUBJID", to = "USUBJ2")
    Condition
      Error:
      ! Neither "USUBJ2" nor "USUBJID" references a codelist in dataset "DM".
      i Add a codelist_id to one of them in the spec.

