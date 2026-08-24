# the data argument is checked before anything is built

    Code
      write_spec(spec, path, created = FROZEN_DATA, data = list(vs_data()))
    Condition
      Error:
      ! `data` must be a named list of data frames.
      x You supplied a list.
      i Name each element for the dataset it holds, as `list(DM = dm, AE = ae)`.

