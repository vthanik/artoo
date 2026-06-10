# print.vport_checks renders the toggle grid

    Code
      print(vport_checks())
    Output
      <vport_checks>
        [x] missing_variable
        [x] missing_permissible
        [x] extra_variable
        [x] type_mismatch
        [x] length_overflow
        [x] char_length_limit
        [x] codelist_membership
        [x] label_match
        [x] key_uniqueness
        [x] display_format

---

    Code
      print(vport_checks(length_overflow = FALSE))
    Output
      <vport_checks>
        [x] missing_variable
        [x] missing_permissible
        [x] extra_variable
        [x] type_mismatch
        [ ] length_overflow
        [x] char_length_limit
        [x] codelist_membership
        [x] label_match
        [x] key_uniqueness
        [x] display_format

