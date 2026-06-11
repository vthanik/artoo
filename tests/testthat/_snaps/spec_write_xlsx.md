# write_spec rejects an unknown extension

    Code
      write_spec(spec, p)
    Condition
      Error:
      ! Unsupported spec file type "csv".
      i write_spec() writes native ".json" (lossless) and Pinnacle 21 ".xlsx" (interchange).

# an empty spec cannot become a P21 workbook

    Code
      write_spec(empty, p)
    Condition
      Error:
      ! Cannot write a Pinnacle 21 workbook from an empty spec.
      x The "Datasets" and "Variables" sheets have no rows.

