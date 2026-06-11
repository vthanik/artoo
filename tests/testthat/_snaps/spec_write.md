# write_spec() rejects a non-spec input

    Code
      write_spec(mtcars, p)
    Condition
      Error:
      ! `spec` must be a <artoo_spec>.
      x You supplied a data frame.
      i Build one with `artoo_spec()`.

