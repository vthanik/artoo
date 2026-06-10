# read_spec() rejects bad paths and unsupported extensions

    Code
      read_spec(tmp)
    Condition
      Error:
      ! Unsupported spec file type "csv".
      i read_spec() reads ".json" and Pinnacle 21 ".xlsx".

# .match_p21_sheet informs when several sheets match one role

    Code
      invisible(vport:::.match_p21_sheet(c("Datasets", "datasets "), "datasets"))
    Message
      Several sheets match one Pinnacle 21 role.
      i Using "Datasets"; ignoring "datasets ".

