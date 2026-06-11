# .format_spec renders counts and a dataset preview

    Code
      cat(artoo:::.format_spec(demo_adam_spec()), sep = "\n")
    Output
      <artoo_spec>
      Study: (unspecified)
      Standard: ADaMIG 1.1
      Datasets:  1
      Variables: 48
      Codelists: 1
      Spec for: ADSL

# .format_meta renders dataset, records, columns, keys, preview

    Code
      cat(artoo:::.format_meta(get_meta(adsl)), sep = "\n")
    Output
      <artoo_meta>
      Dataset: ADSL (Subject-Level Analysis Dataset)
      Records: 60
      Columns: 48
        STUDYID  string
        USUBJID  string
        SUBJID   string
        SITEID   string
        SITEGR1  string
        ARM      string
        ... (+42 more)

