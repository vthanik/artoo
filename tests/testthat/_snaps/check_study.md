# check_study() prints the dataset-by-check matrix

    Code
      print(check_study(adam_spec, list(ADSL = adsl)))
    Output
      <artoo_study_findings> 1 dataset: 1 error, 11 warnings, 15 notes
      
           codelist_membership_extensible extra_variable integer_fraction label_match
      ADSL                              1              5                1           3
           missing_permissible type_mismatch
      ADSL                   6            11
      
      i Treat this as a findings frame: filter by severity, or pass it to repair_spec().

# check_study() aborts on a bad data argument

    Code
      check_study(adam_spec, cdisc_adsl)
    Condition
      Error:
      ! `data` must be a non-empty named list of data frames.
      x You supplied a single data frame.
      i Name each element by its dataset, e.g. `list(ADSL = adsl, ADAE = adae)`.

# check_study() aborts on an unknown dataset

    Code
      check_study(adam_spec, list(NOPE = cdisc_adsl))
    Condition
      Error:
      ! Dataset "NOPE" is not in the spec.
      i Spec datasets: "ADSL" and "ADAE".

