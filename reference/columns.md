# View a dataset's variable attributes, SAS-style

Return a one-row-per-variable attribute table – the pane a SAS
programmer reads in `PROC CONTENTS` or the Universal Viewer: position,
name, Char/Num type, length, format, informat, label, and the CDISC key
sequence. This is the quick look after
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
stamps a frame, or on any dataset file artoo can read.

## Usage

``` r
columns(x, member = NULL)
```

## Arguments

- x:

  *What to describe.* `<data.frame> | <character(1)>: required`. A
  stamped frame (carries `artoo_meta`), any plain data frame, or a path
  to a dataset file (`.xpt`, `.json`, `.ndjson`, `.parquet`, `.rds`).

- member:

  *XPORT member to describe.* `<character(1)> | NULL`. Only meaningful
  when `x` is a path to a multi-member `.xpt` file.

## Value

*A `<artoo_columns>` data frame* with columns `#`, `Variable`, `Type`,
`Len`, `Format`, `Informat`, `Label`, `Key`, printed left-aligned. It is
an ordinary data frame underneath – filter or inspect it like one.

## Details

**Every real column shows.** The table covers the *frame's* columns: a
column the spec never declared (which
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
keeps, never drops) still appears, its attributes inferred from the R
class. A plain, never-stamped data frame works the same way – every
attribute is inferred.

**A path reads through the codec.** A file path is dispatched by
extension through the same registry as
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md),
so the attributes come from the one lossless reader (an unknown
extension aborts with the registry's known-extensions message).

**Tip:** a multi-member XPORT file needs `member =`; without one the xpt
reader aborts and points at
[`xpt_members()`](https://vthanik.github.io/artoo/reference/xpt_members.md)
for the listing.

**Note:** an `.xpt` path shows a blank `Key`: the XPORT byte layout
stores only name, label, length, and formats, so `keySequence` (like
codelist and origin) cannot ride in the file. The metadata-carrying
formats (`.json`, `.ndjson`, `.parquet`, `.rds`) and the in-session
conformed frame show it; re-apply the spec after an xpt read to restore
it.

## See also

**Members:**
[`xpt_members()`](https://vthanik.github.io/artoo/reference/xpt_members.md)
lists a multi-member XPORT file.

**Metadata:**
[`get_meta()`](https://vthanik.github.io/artoo/reference/get_meta.md)
for the full `artoo_meta`;
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
which stamps it.

## Examples

``` r
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)

# ---- Example 1: the column pane of a conformed frame ----
#
# apply_spec() stamps ADSL with its metadata; columns() reads it back as
# the SAS-style attribute table.
adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
columns(adsl)
#> <artoo_columns> ADSL -- 48 variables, 60 obs
#> #   Variable  Type  Len  Format  Informat  Label                                     Key
#> 1   STUDYID   Char  12                     Study Identifier
#> 2   USUBJID   Char  11                     Unique Subject Identifier
#> 3   SUBJID    Char  4                      Subject Identifier for the Study
#> 4   SITEID    Char  3                      Study Site Identifier
#> 5   SITEGR1   Char  3                      Pooled Site Group 1
#> 6   ARM       Char  20                     Description of Planned Arm
#> 7   TRT01P    Char  20                     Planned Treatment for Period 01
#> 8   TRT01PN   Num   8                      Planned Treatment for Period 01 (N)
#> 9   TRT01A    Char  20                     Actual Treatment for Period 01
#> 10  TRT01AN   Num   8                      Actual Treatment for Period 01 (N)
#> 11  TRTSDT    Num   8                      Date of First Exposure to Treatment
#> 12  TRTEDT    Num   8                      Date of Last Exposure to Treatment
#> 13  TRTDUR    Num   8                      Duration of Treatment (days)
#> 14  AVGDD     Num   8                      Avg Daily Dose (as planned)
#> 15  CUMDOSE   Num   8                      Cumulative Dose (as planned)
#> 16  AGE       Num   8                      Age
#> 17  AGEGR1    Char  5                      Pooled Age Group 1
#> 18  AGEGR1N   Num   8                      Pooled Age Group 1 (N)
#> 19  AGEU      Char  5                      Age Units
#> 20  RACE      Char  32                     Race
#> 21  RACEN     Num   8                      Race (N)
#> 22  SEX       Char  1                      Sex
#> 23  ETHNIC    Char  22                     Ethnicity
#> 24  SAFFL     Char  1                      Safety Population Flag
#> 25  ITTFL     Char  1                      Intent-To-Treat Population Flag
#> 26  EFFFL     Char  1                      Efficacy Population Flag
#> 27  COMP8FL   Char  1                      Completers of Week 8 Population Flag
#> 28  COMP16FL  Char  1                      Completers of Week 16 Population Flag
#> 29  COMP24FL  Char  1                      Completers of Week 24 Population Flag
#> 30  DISCONFL  Char  1                      Did the Subject Discontinue the Study?
#> 31  DSRAEFL   Char  1                      Discontinued due to AE?
#> 32  DTHFL     Char  1                      Subject Died?
#> 33  BMIBL     Num   8                      Baseline BMI (kg/m^2)
#> 34  BMIBLGR1  Char  6                      Pooled Baseline BMI Group 1
#> 35  HEIGHTBL  Num   8                      Baseline Height (cm)
#> 36  WEIGHTBL  Num   8                      Baseline Weight (kg)
#> 37  EDUCLVL   Num   8                      Years of Education
#> 38  DISONSDT  Num   8                      Date of Onset of Disease
#> 39  DURDIS    Num   8                      Duration of Disease (Months)
#> 40  DURDSGR1  Char  4                      Pooled Disease Duration Group 1
#> 41  VISIT1DT  Num   8                      Date of Visit 1
#> 42  RFSTDTC   Char  10                     Subject Reference Start Date/Time
#> 43  RFENDTC   Char  10                     Subject Reference End Date/Time
#> 44  VISNUMEN  Num   8                      End of Trt Visit (Vis 12 or Early Term.)
#> 45  RFENDT    Num   8                      Date of Discontinuation/Completion
#> 46  DCDECOD   Char  27                     Standardized Disposition Term
#> 47  DCREASCD  Char  18                     Reason for Discontinuation
#> 48  MMSETOT   Num   8                      MMSE Total

# ---- Example 2: straight off a file ----
#
# Write the conformed frame to any format and point columns() at the
# path; the codec reads it back and the attributes are identical.
p <- tempfile(fileext = ".json")
write_json(adsl, p)
columns(p)
#> <artoo_columns> ADSL -- 48 variables, 60 obs
#> #   Variable  Type  Len  Format  Informat  Label                                     Key
#> 1   STUDYID   Char  12                     Study Identifier
#> 2   USUBJID   Char  11                     Unique Subject Identifier
#> 3   SUBJID    Char  4                      Subject Identifier for the Study
#> 4   SITEID    Char  3                      Study Site Identifier
#> 5   SITEGR1   Char  3                      Pooled Site Group 1
#> 6   ARM       Char  20                     Description of Planned Arm
#> 7   TRT01P    Char  20                     Planned Treatment for Period 01
#> 8   TRT01PN   Num   8                      Planned Treatment for Period 01 (N)
#> 9   TRT01A    Char  20                     Actual Treatment for Period 01
#> 10  TRT01AN   Num   8                      Actual Treatment for Period 01 (N)
#> 11  TRTSDT    Num   8                      Date of First Exposure to Treatment
#> 12  TRTEDT    Num   8                      Date of Last Exposure to Treatment
#> 13  TRTDUR    Num   8                      Duration of Treatment (days)
#> 14  AVGDD     Num   8                      Avg Daily Dose (as planned)
#> 15  CUMDOSE   Num   8                      Cumulative Dose (as planned)
#> 16  AGE       Num   8                      Age
#> 17  AGEGR1    Char  5                      Pooled Age Group 1
#> 18  AGEGR1N   Num   8                      Pooled Age Group 1 (N)
#> 19  AGEU      Char  5                      Age Units
#> 20  RACE      Char  32                     Race
#> 21  RACEN     Num   8                      Race (N)
#> 22  SEX       Char  1                      Sex
#> 23  ETHNIC    Char  22                     Ethnicity
#> 24  SAFFL     Char  1                      Safety Population Flag
#> 25  ITTFL     Char  1                      Intent-To-Treat Population Flag
#> 26  EFFFL     Char  1                      Efficacy Population Flag
#> 27  COMP8FL   Char  1                      Completers of Week 8 Population Flag
#> 28  COMP16FL  Char  1                      Completers of Week 16 Population Flag
#> 29  COMP24FL  Char  1                      Completers of Week 24 Population Flag
#> 30  DISCONFL  Char  1                      Did the Subject Discontinue the Study?
#> 31  DSRAEFL   Char  1                      Discontinued due to AE?
#> 32  DTHFL     Char  1                      Subject Died?
#> 33  BMIBL     Num   8                      Baseline BMI (kg/m^2)
#> 34  BMIBLGR1  Char  6                      Pooled Baseline BMI Group 1
#> 35  HEIGHTBL  Num   8                      Baseline Height (cm)
#> 36  WEIGHTBL  Num   8                      Baseline Weight (kg)
#> 37  EDUCLVL   Num   8                      Years of Education
#> 38  DISONSDT  Num   8                      Date of Onset of Disease
#> 39  DURDIS    Num   8                      Duration of Disease (Months)
#> 40  DURDSGR1  Char  4                      Pooled Disease Duration Group 1
#> 41  VISIT1DT  Num   8                      Date of Visit 1
#> 42  RFSTDTC   Char  10                     Subject Reference Start Date/Time
#> 43  RFENDTC   Char  10                     Subject Reference End Date/Time
#> 44  VISNUMEN  Num   8                      End of Trt Visit (Vis 12 or Early Term.)
#> 45  RFENDT    Num   8                      Date of Discontinuation/Completion
#> 46  DCDECOD   Char  27                     Standardized Disposition Term
#> 47  DCREASCD  Char  18                     Reason for Discontinuation
#> 48  MMSETOT   Num   8                      MMSE Total
```
