# conformance() aborts with a hint when no findings are attached

    Code
      conformance(off)
    Condition
      Error:
      ! `x` carries no conformance findings.
      x No vport.conformance attribute was found.
      i Run `apply_spec()` with `conformance = "warn"` or `"abort"`, or call `check_spec()` directly.

# the vport_findings print renders a sectioned report

    Code
      print(conformance(dm))
    Output
      <vport_findings>: 0 errors, 0 warnings, 0 notes
      No findings. The data conforms to the spec.

---

    Code
      print(check_spec(clean, spec, "ADSL"))
    Output
      <vport_findings>: 0 errors, 0 warnings, 0 notes
      No findings. The data conforms to the spec.

