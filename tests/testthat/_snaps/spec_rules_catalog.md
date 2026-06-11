# .check_rules_df names the offending value in each integrity error

    Code
      artoo:::.check_rules_df(bad_sev)
    Condition
      Error in `artoo:::.check_rules_df()`:
      ! Rule catalog has unknown severity: "fatal".

---

    Code
      artoo:::.check_rules_df(bad_data)
    Condition
      Error in `artoo:::.check_rules_df()`:
      ! Rule catalog data-engine rule "no_data_rule" must require data.

---

    Code
      artoo:::.check_rules_df(dup)
    Condition
      Error in `artoo:::.check_rules_df()`:
      ! Rule catalog has duplicate id: "x".

