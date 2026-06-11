# make-p21-fixture.R -- build the P21 Excel test fixture for read_spec().
#
# Reproducible, public, hand-authored from standard CDISC metadata (no
# study/patient data, nothing copied from a private archive). Re-run with:
#   Rscript data-raw/make-p21-fixture.R
# Output is committed at tests/testthat/fixtures/p21_adam_spec.xlsx.
#
# Authoring-time only: uses openxlsx2 to write the workbook (and to MERGE
# the Dataset / codelist-ID columns). openxlsx2 is NOT a package
# dependency -- artoo ships with no xlsx-writing dependency.

stopifnot(requireNamespace("openxlsx2", quietly = TRUE))

out <- file.path("tests", "testthat", "fixtures", "p21_adam_spec.xlsx")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)

# ---- Define (study) sheet: Attribute / Value key-value pairs -------------
define <- data.frame(
  Attribute = c(
    "StudyName",
    "StudyDescription",
    "StandardName",
    "StandardVersion"
  ),
  Value = c("CDISCPILOT01", "CDISC Pilot Study", "ADaMIG", "1.1"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# ---- Datasets sheet ------------------------------------------------------
datasets <- data.frame(
  Dataset = c("ADSL", "DM"),
  Label = c("Subject-Level Analysis Dataset", "Demographics"),
  Class = c("ADAM OTHER", "SPECIAL PURPOSE"),
  Structure = c("One record per subject", "One record per subject"),
  `Key Variables` = c("STUDYID USUBJID", "STUDYID USUBJID"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# ---- Variables sheet -----------------------------------------------------
# Dataset is given ONLY on each group's first row (NA elsewhere) and then
# merged, reproducing a real P21 export where readxl returns NA on the
# continuation rows. SEX carries a deliberately space-padded codelist id
# (whitespace-trim test) and Mandatory = "Yes"; TRTSDTM is a
# partialDatetime (Define-XML date-subtype canonicalisation test).
# Crafted defects for the validation tests, kept DISTINCT per dataset so
# scoping isolation is provable:
#   ADSL: AGE is Origin=Derived with NO Method  -> derived-has-method warning
#         TRTSDTM references MT.TRTSDTM (resolves, clean)
#   DM:   USUBJID references MT.DM (a method with a BLANK description)
#         SEX references comment C.BLANK (a comment with a blank body)
variables <- data.frame(
  Order = as.character(1:8),
  Dataset = c("ADSL", NA, NA, NA, NA, "DM", NA, NA),
  Variable = c(
    "STUDYID",
    "USUBJID",
    "AGE",
    "SEX",
    "TRTSDTM",
    "STUDYID",
    "USUBJID",
    "SEX"
  ),
  Label = c(
    "Study Identifier",
    "Unique Subject Identifier",
    "Age",
    "Sex",
    "Datetime of First Exposure to Treatment",
    "Study Identifier",
    "Unique Subject Identifier",
    "Sex"
  ),
  `Data Type` = c(
    "text",
    "text",
    "integer",
    "text",
    "partialDatetime",
    "text",
    "text",
    "text"
  ),
  Length = c("12", "40", "8", "1", "19", "12", "40", "1"),
  `Significant Digits` = c(NA, NA, NA, NA, NA, NA, NA, NA),
  Format = c(NA, NA, NA, NA, "E8601DT", NA, NA, NA),
  Mandatory = c("Yes", "Yes", "Yes", "Yes", "No", "Yes", "Yes", "Yes"),
  Codelist = c(NA, NA, NA, " C66731 ", NA, NA, NA, "C66731"),
  Origin = c(
    "Predecessor",
    "Predecessor",
    "Derived",
    "Predecessor",
    "Derived",
    "Collected",
    "Derived",
    "Collected"
  ),
  Method = c(NA, NA, NA, NA, "MT.TRTSDTM", NA, "MT.DM", NA),
  Comment = c(NA, NA, NA, NA, NA, NA, NA, "C.BLANK"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# ---- Codelists sheet -----------------------------------------------------
# C66731 (SEX). ID is given only on the header row + first term and merged;
# the header row carries a Name but no Term (dropped on read).
codelists <- data.frame(
  ID = c("C66731", NA, NA, NA),
  Name = c("Sex", NA, NA, NA),
  `NCI Codelist Code` = c("C66731", NA, NA, NA),
  `Data Type` = c("text", NA, NA, NA),
  Order = c(NA, "1", "2", "3"),
  Term = c(NA, "F", "M", "U"),
  `Decoded Value` = c(NA, "Female", "Male", "Unknown"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# ---- Methods sheet -------------------------------------------------------
# MT.TRTSDTM is complete; MT.DM has a BLANK Description (defect, DM-scoped).
# A trailing all-but-id-blank row is dropped on read.
methods <- data.frame(
  ID = c("MT.TRTSDTM", "MT.DM", NA),
  Name = c("MT.TRTSDTM", "MT.DM", NA),
  Type = c("Computation", "Computation", NA),
  Description = c(
    "Datetime of first exposure, derived from EX.",
    NA, # blank description -> defect
    NA
  ),
  Document = c("DOC.SAP", NA, NA),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# ---- Comments sheet ------------------------------------------------------
# C.BLANK has a blank Description (defect, DM-scoped).
comments <- data.frame(
  ID = c("C.BLANK"),
  Description = c(NA_character_),
  Document = c(NA_character_),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# ---- Documents sheet -----------------------------------------------------
documents <- data.frame(
  ID = c("DOC.SAP"),
  Title = c("Statistical Analysis Plan"),
  Href = c("sap.pdf"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

wb <- openxlsx2::wb_workbook()
wb$add_worksheet("Define")$add_data(sheet = "Define", x = define)
wb$add_worksheet("Datasets")$add_data(sheet = "Datasets", x = datasets)
wb$add_worksheet("Variables")$add_data(sheet = "Variables", x = variables)
wb$add_worksheet("Codelists")$add_data(sheet = "Codelists", x = codelists)
wb$add_worksheet("Methods")$add_data(sheet = "Methods", x = methods)
wb$add_worksheet("Comments")$add_data(sheet = "Comments", x = comments)
wb$add_worksheet("Documents")$add_data(sheet = "Documents", x = documents)

# Merge the Dataset column across each group (data starts at row 2).
wb$merge_cells(sheet = "Variables", dims = "B2:B6") # ADSL rows
wb$merge_cells(sheet = "Variables", dims = "B7:B9") # DM rows
# Merge the codelist ID across its rows (header + 3 terms).
wb$merge_cells(sheet = "Codelists", dims = "A2:A5")

wb$save(out)
message("Wrote ", out)
