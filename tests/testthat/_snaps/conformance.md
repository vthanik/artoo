# conformance() aborts with a hint when no findings are attached

    Code
      conformance(off)
    Condition
      Error:
      ! `x` carries no conformance findings.
      x No artoo.conformance attribute was found.
      i Run `apply_spec()` with `conformance = "warn"` or `"abort"`, or call `check_spec()` directly.

# the artoo_findings print renders a sectioned report

    Code
      print(conformance(dm))
    Output
      <artoo_findings>: 0 errors, 0 warnings, 0 notes
      No findings. The data conforms to the spec.

---

    Code
      print(check_spec(clean, spec, "ADSL"))
    Output
      <artoo_findings>: 0 errors, 0 warnings, 0 notes
      No findings. The data conforms to the spec.

# print renders sections when findings exist, and falls back on subsets

    Code
      print(f)
    Output
      <artoo_findings> DM: 1 error, 1 warning, 0 notes
      Errors
      ------
      [codelist_membership] 'SEX' has 1 value(s) outside codelist 'C66731': X.  (DM.SEX)
      
      Warnings
      --------
      [extra_variable] Column 'NOTSPEC' is not declared in the spec.  (DM.NOTSPEC)
      
      

