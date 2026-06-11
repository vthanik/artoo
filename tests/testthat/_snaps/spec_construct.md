# mixing standards aborts at construction

    Code
      artoo_spec(data.frame(dataset = c("ADSL", "DM"), standard = c("ADaMIG 1.1",
        "SDTMIG 3.2")), data.frame(dataset = c("ADSL", "DM"), variable = c("AGE",
        "USUBJID"), data_type = c("integer", "string")))
    Condition
      Error:
      ! A <artoo_spec> carries exactly one CDISC standard.
      x Found 2 distinct standards: "ADaMIG 1.1" and "SDTMIG 3.2".
      i Split the source by standard, or scope the read to one standard's datasets with `read_spec(path, datasets = ...)`.

