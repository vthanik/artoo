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

# truncating integer coercion always aborts (lossless or abort)

    Code
      apply_spec(raw, spec, "DM", conformance = "off")
    Condition
      Error:
      ! Coercion to the spec dataTypes would lose data.
      x Integer coercion would truncate fractional values in: AGE (1).
      i Fix the spec: dataType "float" or "decimal" keeps fractions; a wider type avoids overflow.

