# a duplicated spec variable aborts at construction, with the rows

    Code
      artoo_spec(cdisc_datasets, vars2, codelists = cdisc_codelists)
    Condition
      Error:
      ! `variables` defines 1 variable more than once.
      x Rows 64 and 74 of `variables` all define DM.SEX.
      i Remove the duplicate rows, or read the file with `read_spec(path, on_duplicate = "first")`.

