# validate_spec(on_error = 'abort') throws on an error-severity finding

    Code
      validate_spec(spec, dataset = "DM", on_error = "abort")
    Condition
      Error:
      ! Spec is not submission-ready, 1 error-severity finding.
      x Dataset 'DM' keys reference variables not in the spec: NOTAVAR.
      i Inspect every finding in the returned artoo_check.

