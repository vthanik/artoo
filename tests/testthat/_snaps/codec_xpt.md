# a factor column aborts with artoo_error_type

    Code
      write_xpt(df, p)
    Condition
      Error in `write_xpt()`:
      ! Column `F` is a factor.
      i Convert it with `as.character()` before writing.

# write_xpt warns when data widens a spec-declared length

    Code
      out <- write_xpt(x, f)
    Condition
      Warning in `write_xpt()`:
      Widened 1 column past the declared spec length: "INVNAM (6 -> 8)".
      i Values need more bytes than the spec length; data was kept whole.
      i Update the spec length, or shorten the data, so the file matches its declared metadata.

