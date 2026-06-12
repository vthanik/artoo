# an unknown path extension aborts via the codec registry

    Code
      columns("spec.docx")
    Condition
      Error:
      ! No codec handles the "docx" extension.
      i Known extensions: "json", "jsonl", "ndjson", "parquet", "pq", "rds", "xport", and "xpt".

# print is the left-aligned SAS pane (snapshot)

    Code
      print(columns(dm))
    Output
      <artoo_columns> DM -- 25 variables, 60 obs
      #   Variable  Type  Len  Format  Label                               Key
      1   STUDYID   Char  12           Study Identifier
      2   DOMAIN    Char  2            Domain Abbreviation
      3   USUBJID   Char  11           Unique Subject Identifier
      4   SUBJID    Char  4            Subject Identifier for the Study
      5   RFSTDTC   Char  10           Subject Reference Start Date/Time
      6   RFENDTC   Char  10           Subject Reference End Date/Time
      7   RFXSTDTC  Char  10           Date/Time of First Study Treatment
      8   RFXENDTC  Char  10           Date/Time of Last Study Treatment
      9   RFICDTC   Char  1            Date/Time of Informed Consent
      10  RFPENDTC  Char  16           Date/Time of End of Participation
      11  DTHDTC    Char  10           Date/Time of Death
      12  DTHFL     Char  1            Subject Death Flag
      13  SITEID    Char  3            Study Site Identifier
      14  AGE       Num                Age
      15  AGEU      Char  5            Age Units
      16  SEX       Char  1            Sex
      17  RACE      Char  32           Race
      18  ETHNIC    Char  22           Ethnicity
      19  ARMCD     Char  8            Planned Arm Code
      20  ARM       Char  20           Description of Planned Arm
      21  ACTARMCD  Char  8            Actual Arm Code
      22  ACTARM    Char  20           Description of Actual Arm
      23  COUNTRY   Char  3            Country
      24  DMDTC     Char  10           Date/Time of Collection
      25  DMDY      Num                Study Day of Collection

