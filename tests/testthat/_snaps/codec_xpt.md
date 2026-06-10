# a factor column aborts with vport_error_type

    Code
      write_xpt(df, p)
    Condition
      Error in `write_dataset()`:
      ! Column `F` is a factor.
      i Convert it with `as.character()` before writing.

