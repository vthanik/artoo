# .format_spec renders counts and a dataset preview

    Code
      cat(vport:::.format_spec(demo_spec()), sep = "\n")
    Output
      <vport_spec>
      Study: (unspecified)
      Datasets:  2
      Variables: 73
      Codelists: 1
      Spec for: ADSL, DM

# .format_meta renders dataset, records, columns, keys, preview

    Code
      cat(vport:::.format_meta(get_meta(adsl)), sep = "\n")
    Output
      <vport_meta>
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

