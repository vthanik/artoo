# the data argument is checked before anything is built

    Code
      write_spec(spec, path, created = FROZEN_DATA, data = list(vs_data()))
    Condition
      Error:
      ! `data` must be a named list of data frames.
      x You supplied a list.
      i Name each element for the dataset it holds, as `list(DM = dm, AE = ae)`.

# a bare data frame is refused by what it is, not by its columns

    Code
      artoo:::.dx_check_data(data.frame(A = 1), NULL)
    Condition
      Error:
      ! `data` must be a named list of data frames.
      x You supplied a bare data frame.
      i Name it for the dataset it holds, as `list(DM = dm)`.

