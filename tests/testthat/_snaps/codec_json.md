# NaN and Inf abort the write (C2)

    Code
      write_json(df, tempfile(fileext = ".json"))
    Condition
      Error in `write_json()`:
      ! Column `N` contains "Inf".
      x NaN and infinite values are not valid in CDISC Dataset-JSON.
      i Recode them to NA, or use a string dataType.

# a non-Dataset-JSON file aborts cleanly (E2)

    Code
      read_json(p)
    Condition
      Error in `read_json()`:
      ! '<path>' is not a Dataset-JSON v1.1 file.
      x It lacks the datasetJSONVersion and columns keys.

