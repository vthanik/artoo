# a value-level row with no parent variable is refused

    Code
      artoo:::.dx_oids(spec)
    Condition
      Error:
      ! 1 value-level row qualifies a variable the spec does not carry.
      x "VS.NOSUCHVAR".
      i A def:ValueListDef hangs off its parent ItemDef, so the variable must be in the spec.

