# spec_codelists() rejects an unknown codelist

    Code
      spec_codelists(demo_spec(), "C00000")
    Condition
      Error:
      ! `codelist_id` must be a codelist in the spec.
      x "C00000" is not present.
      i Available: "C66731".

# spec_study() rejects an unknown field

    Code
      spec_study(demo_spec(), "nope")
    Condition
      Error:
      ! `field` must be a study-level field.
      x "nope" is not present.
      i Available: "studyid".

