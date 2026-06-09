# validate_spec(strict = TRUE) throws on an error-severity finding

    Code
      validate_spec(spec, dataset = "DM", strict = TRUE)
    Condition
      Error:
      ! Spec is not submission-ready, 1 error-severity finding.
      x Dataset 'DM' keys reference variables not in the spec: NOTAVAR.
      i Inspect every finding in the returned vport_check.

