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
      i Pass `data_format` to name one, as `data_format = "json"`.

# partial coverage is reported once, both directions

    Code
      resolved <- artoo:::.dx_resolve_data_dir(d, spec)
    Message
      Read 1 of 2 datasets from '<dir>'.
      i Used 'dm.json'.
      i No file for "VS".
      i Not named by the spec: 'demo.json'.
    Condition
      Warning:
      1 archive location names a file the folder does not hold.
      x dm.json -> dm.xpt.
      i Set `datasets$archive_location_id` if the submission ships something else.

# a path that is not a directory is refused by what it is

    Code
      artoo:::.dx_resolve_data_dir(f, spec)
    Condition
      Error:
      ! `data` must be a directory.
      x '<tmp>/dm.json' is not one.
      i Pass the folder holding the datasets, or a named list of frames.

# data_format without a folder is refused, not ignored

    Code
      artoo:::.dx_check_data(folder_frames(), spec, data_format = "json")
    Condition
      Error:
      ! `data_format` applies only when `data` is a folder.
      x You supplied `data` as a list.
      i Drop `data_format`, or pass the folder holding the datasets.

