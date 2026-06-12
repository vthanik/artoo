# set_type() aborts on an unknown dataset

    Code
      set_type(adam_spec, "NOPE", AGE = "float")
    Condition
      Error:
      ! `dataset` must be one of the spec's datasets.
      x "NOPE" is not in the spec.
      i Available: "ADSL" and "ADAE".

# set_type() aborts on an unknown variable

    Code
      set_type(adam_spec, "ADSL", NOPE = "float")
    Condition
      Error:
      ! Variable "NOPE" is not in dataset "ADSL".
      i Variables in "ADSL": "STUDYID", "USUBJID", "SUBJID", "SITEID", "SITEGR1", "ARM", "TRT01P", "TRT01PN", "TRT01A", "TRT01AN", "TRTSDT", "TRTEDT", "TRTDURD", "AVGDD", "CUMDOSE", "AGE", "AGEGR1", "AGEGR1N", ..., "EOSDISP", and "MMS1TSBL".

# set_type() aborts on an unnamed or empty override

    Code
      set_type(adam_spec, "ADSL", "float")
    Condition
      Error:
      ! Every type override must be a named `variable = type` pair.
      x  Argument in position 1 is unnamed.
      i For example `set_type(spec, "ADSL", AGE = "float")`.

---

    Code
      set_type(adam_spec, "ADSL")
    Condition
      Error:
      ! `set_type()` needs at least one `variable = type` pair.
      i For example `set_type(spec, "ADSL", AGE = "float")`.

# set_type() aborts on an unknown type token

    Code
      set_type(adam_spec, "ADSL", AGE = "frobnicate")
    Condition
      Error:
      ! Unknown variable type "frobnicate" for AGE.
      x artoo maps types to the closed CDISC set: "string", "integer", "decimal", "float", "double", "boolean", "date", "datetime", "time", and "URI".
      i Edit the spec's type column, or file an issue if "frobnicate" is a standard token.

