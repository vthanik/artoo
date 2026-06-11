# write_spec rejects an unknown extension

    Code
      write_spec(spec, p)
    Condition
      Error:
      ! Unsupported spec file type "csv".
      i write_spec() writes native ".json" (lossless) and Pinnacle 21 ".xlsx" (interchange).

