# repair_spec() aborts on a non-findings input

    Code
      repair_spec(adam_spec, list(a = 1))
    Condition
      Error:
      ! `findings` must be a findings data frame.
      x You supplied a list.
      i Pass the result of `check_spec()` or `check_study()`.

