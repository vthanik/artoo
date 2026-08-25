# print is the left-aligned members pane (snapshot)

    Code
      print(members(d))
    Output
      <artoo_members> 1 dataset
      file     member  label         records  variables  format
      dm.json  DM      Demographics  60       25         json

# an unusable format restriction aborts

    Code
      members(d, format = character(0))
    Condition
      Error:
      ! `format` must name at least one registered format.
      x You supplied an empty character vector.
      i Registered formats: "json", "ndjson", "parquet", "rds", and "xpt".

