# read_spec() rejects bad paths and unsupported extensions

    Code
      read_spec(tmp)
    Condition
      Error:
      ! Unsupported spec file type "csv".
      i read_spec() reads ".json" and Pinnacle 21 ".xlsx".

