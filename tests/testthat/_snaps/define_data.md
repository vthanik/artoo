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

# one dataset matching two files aborts instead of choosing

    Code
      artoo:::.dx_resolve_data_dir(d, spec)
    Condition
      Error:
      ! 1 dataset matches more than one file.
      x "DM": 'dm.json' and 'dm.rds'.
      i Pass `data_format` to name the format to read.

# partial coverage is reported once, both directions

    Code
      resolved <- artoo:::.dx_resolve_data_dir(d, spec)
    Message
      Read 1 of 2 datasets from '<dir>'.
      i No file for "VS".
      i Not named by the spec: 'demo.json'.

# a path that is not a directory is refused by what it is

    Code
      artoo:::.dx_resolve_data_dir(f, spec)
    Condition
      Error:
      ! `data` must be a directory.
      x '<path>' is not one.
      i Pass the folder holding the datasets, or a named list of frames.

