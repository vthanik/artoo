# print is the left-aligned members pane (snapshot)

    Code
      print(members(d))
    Output
      <artoo_members> 1 dataset
      file     member  label         records  variables  format
      dm.json  DM      Demographics  60       25         json

# naming a file the restriction excludes aborts

    Code
      members(p, format = "xpt")
    Condition
      Error:
      ! `format` excludes the file `path` names.
      x 'dm.json' is "json"; you asked for "xpt".
      i Drop `format`, or name "json" in it.

# an unusable format restriction aborts

    Code
      members(d, format = character(0))
    Condition
      Error:
      ! `format` must name at least one registered format.
      x You supplied an empty character vector.
      i Registered formats: "json", "ndjson", "parquet", "rds", and "xpt".

