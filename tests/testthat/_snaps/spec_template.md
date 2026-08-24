# a template is written atomically and refuses a non-xlsx path

    Code
      write_template(path)
    Condition
      Error in `write_template()`:
      ! A workbook template is written as ".xlsx".
      x You gave '<tmp>/t.csv'.

# a blank template reads back as an empty-but-valid starting point

    Code
      read_spec(path)
    Condition
      Error:
      ! Required sheet "Datasets" is missing or has no data rows.
      i Available sheets: "Define", "Datasets", "Variables", "ValueLevel", "WhereClauses", "Codelists", "Dictionaries", "Methods", "Comments", "Documents", "Standards", "Analysis Displays", and "Analysis Results".

