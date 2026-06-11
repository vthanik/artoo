# read_spec() rejects bad paths and unsupported extensions

    Code
      read_spec(tmp)
    Condition
      Error:
      ! Unsupported spec file type "csv".
      i read_spec() reads ".json", Pinnacle 21 ".xlsx", and Define-XML 2.x ".xml".

# .match_p21_sheet informs when several sheets match one role

    Code
      invisible(artoo:::.match_p21_sheet(c("Datasets", "datasets "), "datasets"))
    Message
      Several sheets match one Pinnacle 21 role.
      i Using "Datasets"; ignoring "datasets ".

# read_spec(datasets=) rejects an unknown dataset, listing what exists

    Code
      read_spec(p, datasets = "ADAE")
    Condition
      Error:
      ! Unknown dataset in `datasets`: "ADAE".
      i The spec defines: "DM".

