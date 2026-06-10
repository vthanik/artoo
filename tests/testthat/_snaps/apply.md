# apply_spec rejects an unknown step

    Code
      apply_spec(cdisc_adsl, spec, "ADSL", steps = "nope")
    Condition
      Error:
      ! Unknown `steps` value: "nope".
      i Available: "scaffold", "drop", "coerce", "decode", "order", "sort", and "stamp".

# apply_spec validates x and dataset

    Code
      apply_spec(list(1), spec, "ADSL")
    Condition
      Error:
      ! `x` must be a data frame.
      x You supplied a list.

---

    Code
      apply_spec(cdisc_adsl, spec, "NOPE")
    Condition
      Error:
      ! `dataset` must be one of the spec's datasets.
      x "NOPE" is not in the spec.
      i Available: "ADSL" and "DM".

