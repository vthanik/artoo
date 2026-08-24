# conflicting study-name fields abort at construction

    Code
      artoo_spec(data.frame(dataset = "DM"), data.frame(dataset = "DM", variable = "USUBJID",
        data_type = "string"), study = data.frame(studyid = "CDISC01", StudyName = "OTHER",
        stringsAsFactors = FALSE, check.names = FALSE))
    Condition
      Error:
      ! Study fields that name the study_name disagree.
      x "studyid" and "StudyName" carry 2 distinct values: "CDISC01" and "OTHER".
      i Reconcile them to one value, or drop the stale field.

# an explicit standard contradicting the source aborts (D10)

    Code
      artoo_spec(data.frame(dataset = "ADSL", standard = "ADaMIG 1.1"), data.frame(
        dataset = "ADSL", variable = "AGE", data_type = "integer"), standard = "SDTMIG 3.2")
    Condition
      Error:
      ! `standard` contradicts the source.
      x "SDTMIG 3.2" was given; the source names "ADaMIG 1.1".
      i Drop the argument, or pass one of the source's values.

