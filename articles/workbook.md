# Authoring a specification workbook

Most specifications are written in Excel, in a workbook of one sheet per
kind of metadata. artoo reads that workbook and writes the submission’s
define.xml from it. This article is the reference for filling one in:
what each sheet is for, which cells artoo actually reads, and the
handful of places where a plausible-looking entry produces a document
that is not what you meant.

It is written for the person holding the workbook. If you want the R
side — inspecting a spec, repairing it, writing the define.xml — that is
[Specifications](https://vthanik.github.io/artoo/articles/specs.md).

## Start from a blank one

[`write_template()`](https://vthanik.github.io/artoo/reference/write_template.md)
writes an empty workbook whose sheets and headers are artoo’s own
reader, so nothing you fill in can be silently ignored:

``` r

book <- tempfile(fileext = ".xlsx")
write_template(book)
readxl::excel_sheets(book)
#>  [1] "Study"             "Datasets"          "Variables"        
#>  [4] "ValueLevel"        "WhereClauses"      "Codelists"        
#>  [7] "Dictionaries"      "Methods"           "Comments"         
#> [10] "Documents"         "Standards"         "Analysis Displays"
#> [13] "Analysis Results"  "Analysis Criteria"
```

Only **Datasets** and **Variables** are required. Every other sheet may
be left empty and artoo omits what it finds nothing in.

Two things to know before you start. A **column** artoo does not
recognise is kept and written back out, so a sponsor column of your own
survives. A **sheet** artoo does not recognise is not — add rows to the
sheets above rather than a sheet of your own.

## Two shapes, and how to tell them apart

Workbooks come in two generations, and artoo reads both. You will
recognise which one you have from three things:

|  | Older | Newer |
|----|----|----|
| The study sheet is called | `Study` | `Define` |
| Conditions live | on a `WhereClauses` sheet | in the `ValueLevel` cell |
| The label column is called | `Description` | `Label` |

If your workbook came out of a validation tool, it is whichever that
tool writes. If you are starting fresh, use the template above: it names
the study sheet `Study` and keeps conditions on `WhereClauses`, which is
what every generation of tooling reads, while spelling the label column
`Label`. Read on; anywhere the two shapes differ, this article says so.

## Define / Study — the study sheet

Two columns, `Attribute` and `Value`, one row per attribute.

These five are the ones to fill in:

| Attribute | Why it matters |
|----|----|
| `StudyName` | The study’s short name. |
| `StudyDescription` | One line describing the study. |
| `ProtocolName` | The protocol identifier. |
| `StandardName` | `SDTM-IG`, `ADaM-IG`, `SEND-IG`. Unhyphenated spellings are understood too. |
| `StandardVersion` | `3.4`, `1.1`, and so on. |

**`StandardName` and `StandardVersion` are the two that bite.**
Define-XML 2.0 refuses to be written without them; 2.1, which artoo
writes by default, warns and carries on. Fill them in either way —
everything downstream reads better for it. Write the older version with
`write_spec(spec, path, version = "2.0")`.

A workbook artoo wrote from an existing define.xml carries more, because
that document had identifiers this sheet is where to keep:

``` r

book3 <- tempfile(fileext = ".xlsx")
suppressWarnings(write_spec(adam_spec, book3))
readxl::read_excel(book3, sheet = "Study")
#> # A tibble: 13 × 2
#>    Attribute                  Value                                             
#>    <chr>                      <chr>                                             
#>  1 StudyName                  CDISC-Sample                                      
#>  2 StudyDescription           CDISC-Sample Data Definition                      
#>  3 ProtocolName               CDISC-Sample                                      
#>  4 DefineVersion              2.1.10                                            
#>  5 StudyOID                   STDY.www.cdisc.org/CDISC-Sample/ADaM              
#>  6 FileOID                    www.cdisc.org/CDISC-Sample/ADaM/1/Define-XML_2.1.0
#>  7 Context                    Submission                                        
#>  8 MetaDataVersionOID         MDV.CDISC01.ADaMIG.1.1.ADaM.2.1                   
#>  9 MetaDataVersionName        Study CDISC-Sample, Data Definitions              
#> 10 MetaDataVersionDescription Study CDISC-Sample, Data Definitions              
#> 11 Originator                 CDISC Data Exchange Standards Team                
#> 12 StandardName               ADaM-IG                                           
#> 13 StandardVersion            1.1
```

You do not have to supply any of those; artoo mints what a new document
needs. Leave them alone if they are there.

Anything else you put on this sheet is kept and written back out, so a
sponsor field of your own survives a round trip.

## Datasets — one row per dataset

`Dataset` and one of `Description` / `Label` are the minimum.

| Column | Notes |
|----|----|
| `Dataset` | The name, `DM`, `ADSL`. |
| `Description` or `Label` | The dataset label. |
| `Class` | `EVENTS`, `FINDINGS`, `BASIC DATA STRUCTURE`, … |
| `Structure` | Prose: “One record per subject”. **Required** — Define-XML has no default for it. |
| `Key Variables` | Space- or comma-separated. This is where a variable’s key sequence comes from, so you do not fill that in twice. |
| `Purpose` | `Tabulation` or `Analysis`. Derived from the standard when blank. |
| `Repeating`, `Reference Data` | `Yes` / `No`. |
| `Domain` | The two-letter domain, for SDTM. Named in the not-submission-grade warning when blank. |
| `SubClass` | A subclass of `Class`, where the standard defines one. |
| `SAS Dataset Name` | When it differs from `Dataset`. Defaults to it. |
| `Has No Data` | `Yes` when the dataset is empty. Needs a `Comment` explaining why. |
| `Standard` | Which standard this dataset follows, when a study mixes versions. |
| `Comment` | A **Comment ID**, matching a row on the Comments sheet — not free text. |

## Variables — one row per variable per dataset

| Column | Notes |
|----|----|
| `Order` | Position within the dataset. |
| `Dataset`, `Variable` | Together they identify the row. |
| `Label` | The variable label. |
| `Data Type` | `text`, `integer`, `float`, `date`, `datetime`, `time`. |
| `Length` | Expected on text, integer and float. **Leave it blank on dates and times** — a validator flags one there. |
| `Significant Digits` | Only with `float`. |
| `Format` | The display format. |
| `Mandatory` | `Yes` / `No`. |
| `Codelist` | A Codelist ID **or a Dictionary ID** — one column serves both. |
| `Origin` | `Collected`, `Derived`, `Assigned`, `Protocol`, `Predecessor`, `Not Available`, `Other`. **The capitals matter.** |
| `Pages` | CRF page numbers. See *Pages* below. |
| `Method` | A Method ID, for a derived variable. |
| `Predecessor` | Where an ADaM variable came from, e.g. `DM.AGE`. |
| `Role` | `Identifier`, `Topic`, `Timing`, … |
| `Origin Document` | Which document `Pages` refers to. Defaults to the annotated CRF. |
| `Source` | Who provided a collected value: `Investigator`, `Sponsor`, `Subject`, `Vendor`. |
| `Assigned Value` | The value, for an `Assigned` origin. |
| `SAS Field Name` | When it differs from `Variable`. |
| `Has No Data` | `Yes` when the variable is always empty. |
| `Comment` | A Comment ID. |

**Origin decides what else you must fill.** `Derived` wants a `Method`;
`Predecessor` wants a `Predecessor`; `Collected` wants `Pages`. artoo
writes what you give it, and a reviewer reading the rendered document
sees a blank where you left one.

## ValueLevel — when one variable means several things

A `QVAL` in a SUPP dataset, or an `AVAL` that is a different measurement
per `PARAMCD`, needs one row per meaning. The columns are the Variables
ones, plus the one that matters most:

`Where Clause` says **which records this row describes**. In the newer
shape you write the condition itself; in the older shape you write an ID
and define the condition on the WhereClauses sheet.

The condition grammar, written out:

    PARAMCD EQ ACTOT                              a single value
    PARAMCD IN (ACITM01, ACITM02, ACITM03)        a set, in parentheses
    LBTESTCD EQ HCT and LBSPEC EQ BLOOD           several conditions, ANDed
    AVISIT EQ "Week 24"                           quote a value with a space
    LBCAT EQ "CHEMISTRY, LOCAL"                   or with a comma
    DM.COUNTRY EQ USA                             a variable in another dataset

Four rules worth knowing:

- **A value runs to the end of the condition.** `AVISIT EQ Week 24`
  already means the seven characters `Week 24`, and
  `LBCAT EQ CHEMISTRY, LOCAL` already means the sixteen. You do not need
  quotes for a space or a comma after `EQ`.
- **Double quotes are stripped when you use them**, so writing
  `AVISIT EQ "Week 24"` gets the same answer. Single quotes are not:
  they stay in the value.
- **The one place quotes are load-bearing is inside a set.** `IN` splits
  on commas, so a member that contains one has to be quoted:
  `PARAMCD IN ("A, B", C)` is two members, not three. Parentheses round
  a set are optional.
- **Qualify a variable from another dataset**, as `DM.COUNTRY`. Without
  the prefix, the condition is read as naming a variable in the row’s
  own dataset — a different question with a different answer.

**`or` is not a general operator.** Conditions are ANDed. artoo folds an
`or` between values of the *same* variable into a set —
`SEX EQ M or SEX EQ F` becomes `SEX IN (M, F)` — and refuses one across
different variables, because Define-XML has no way to say it. Split
those into separate value-level rows.

**One thing cannot be written inline at all:** a value containing the
word `and` or `or`, because that is what separates conditions.
`ATPT EQ 4 hours and 30 minutes` cannot be parsed. Use a WhereClauses
sheet, which needs no parsing.

## WhereClauses — the older shape only

One row per comparison; several rows sharing an `ID` are ANDed together.

| Column | Notes |
|----|----|
| `ID` | Referenced from the ValueLevel `Where Clause` cell. |
| `Dataset`, `Variable` | What is being tested. |
| `Comparator` | `EQ`, `NE`, `IN`, `NOTIN`, `LT`, `LE`, `GT`, `GE`. |
| `Value` | One value, or a comma-separated list for `IN` / `NOTIN`. |
| `Comment` | A Comment ID, when the condition needs explaining. |

If your workbook has no such sheet, write the condition in the
ValueLevel cell instead; artoo works out which shape you used from
whether the sheet is there.

## Codelists — one row per term

The list-level columns repeat on every term row. That looks redundant
and is how the format works.

| Column | Notes |
|----|----|
| `ID` | The codelist identifier, referenced from `Variables.Codelist`. |
| `Name` | The codelist name. Fill it in — artoo falls back to the ID, which is not a name. |
| `Data Type` | `text`, `integer`, `float`. Should match the variables that use it. |
| `NCI Codelist Code` | The C-code for the list, e.g. `C66731`. |
| `Order` | Position of the term. |
| `Term` | The submitted value. |
| `Decoded Value` | What it means. |
| `NCI Term Code` | The C-code for the term. |
| `Rank` | The term’s rank, where the terminology defines one. |
| `SAS Format Name` | The format name, `$SEX`. |
| `Comment` | A **Comment ID**. |

## Dictionaries — MedDRA, WHODrug, ISO 3166

An external dictionary has no terms to list, so it gets its own sheet:
`ID`, `Name`, `Data Type`, `Dictionary`, `Version`. A variable points at
one from its **`Codelist`** column, exactly as it would an enumerated
codelist — there is one column for both, and artoo resolves against
both.

## Standards

Define-XML 2.1 records every standard the study uses, not just the one
the study sheet names: the implementation guide, the controlled
terminology releases, any prior versions still in play. One row each —
`ID`, `Name`, `Type` (`IG`, `CT`, `MODEL`), `Version`, `Status`,
`Publishing Set` — and the Datasets sheet’s `Standard` column points at
them.

Leave it empty and artoo writes one row from the study sheet’s
`StandardName` and `StandardVersion`, which is enough for a document
that follows a single standard.

## Methods, Comments, Documents

**Methods** — `ID`, `Name`, `Type` (`Computation`, `Imputation`,
`Transpose`, `Other`), and `Description`, the prose a reviewer reads.
`Expression Context` and `Expression Code` carry one formal expression:
the language, and the code. `Document` and `Pages` point at where the
method is written up.

**Comments** — `ID`, `Description`, and a `Document` and `Pages` of
their own. Every `Comment` cell elsewhere in the workbook is an ID
matching a row here. This is the single most common workbook mistake:
writing the comment text into the `Comment` cell of the Variables sheet,
where an ID belongs. artoo reports it as an unresolved reference rather
than guessing.

**Documents** — `ID`, `Title`, `Href`. The `Href` is a filename, and it
is also how artoo knows which document is the annotated CRF: **a
filename ending in `crf`** (`acrf.pdf`, `blankcrf.pdf`,
`oncology-crf.pdf`) is the annotated CRF, and everything else is a
supplemental document. If your CRF is called something else, say so with
a `Role` column of `Annotated CRF`.

## Pages

A page reference means nothing without a document. Write pages as `4 5`,
`4, 5`, or a range `4-5`: all three are understood, commas are
normalised to the spaces Define-XML wants, and a range is written out as
a first and last page rather than a list.

**Which document the pages belong to** comes from one of two places. Set
`Origin Document` on the row to name a specific one; leave it blank and
a `Collected` origin’s pages default to the annotated CRF. Methods and
Comments have their own `Document` column for the same reason. If a row
has pages and there is no document to attach them to, artoo refuses
rather than attaching them to a document nobody named.

## Analysis Displays and Analysis Results

For ADaM specifications with analysis results metadata.

**Analysis Displays** — `ID`, `Title`, and the `Document` and `Pages`
where the display appears.

**Analysis Results** — `Display`, `ID`, `Description`, `Reason`,
`Purpose`, the documentation and the programming code. The column that
carries the selection is:

- newer shape: `Selection Criteria`, one bracket group per analysis
  dataset — `ADAE[AESER EQ Y] ADSL[SAFFL EQ Y]`, and `ADSL[]` for every
  record;
- older shape: an `Analysis Criteria` sheet, one row per analysis
  dataset, keyed by `Display` and `Result`, with its own `Variables` and
  `Where Clause` — the same condition grammar as ValueLevel.

`Variables` names the analysis variables, qualified by dataset when the
result spans more than one: `ADAE.AEBODSYS, ADAE.AEDECOD`.
`Documentation Refs` and `Programming Document` name a Document ID each.
`Join Comment` is a Comment ID explaining how several analysis datasets
relate.

## Fill it in, then check it

Reading tells you what artoo understood. Read the workbook back and look
at the slots before you write anything:

``` r

spec <- read_spec(system.file("extdata", "adam-spec.xlsx", package = "artoo"))
spec
#> <artoo_spec>
#> Study: CDISC-Sample
#> Standard: ADaMIG 1.1
#> Datasets:  2
#> Variables: 104
#> Codelists: 20
#> Methods: 45
#> Comments: 11
#> Documents: 8
#> Spec for: ADSL, ADAE
```

[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md)
checks the spec against itself — every reference resolving, every key
sequence contiguous — without needing the data. It reports notes as well
as errors, so expect to see some on a real spec:

``` r

validate_spec(spec)
#> artoo Spec Check
#> ================
#> 
#> Spec Summary
#> ------------
#> Study: CDISC-Sample
#> Scope: ADSL, ADAE
#> Datasets: 2    Variables: 104
#> Methods referenced: 45    Comments referenced: 7
#> 
#> Findings Summary
#> ----------------
#>   error    0
#>   warning  0
#>   note     10
#> 
#> Notes
#> -----
#> [comment_unused] Comment 'COM.JOIN-ADSL-ADAE' is defined but never referenced.  (COM.JOIN-ADSL-ADAE)
#> [comment_unused] Comment 'COM.STDCT.01' is defined but never referenced.  (COM.STDCT.01)
#> [comment_unused] Comment 'COM.STDCT.02' is defined but never referenced.  (COM.STDCT.02)
#> [comment_unused] Comment 'COM.STD5' is defined but never referenced.  (COM.STD5)
#> [document_unused] Document 'LF.ADSL' is defined but never referenced.  (LF.ADSL)
#> [document_unused] Document 'LF.ADQSADAS' is defined but never referenced.  (LF.ADQSADAS)
#> [document_unused] Document 'LF.ADAE' is defined but never referenced.  (LF.ADAE)
#> [document_unused] Document 'LF.ADRG' is defined but never referenced.  (LF.ADRG)
#> [document_unused] Document 'LF.CSR' is defined but never referenced.  (LF.CSR)
#> [document_unused] Document 'LF.at14-5-02.sas' is defined but never referenced.  (LF.at14-5-02.sas)
```

Then write the define.xml. artoo validates the document against the
CDISC schemas before the file reaches its destination, so an invalid one
never overwrites a good file:

``` r

define <- tempfile(fileext = ".xml")
write_spec(spec, define)
#> Warning: The spec is not submission-grade.
#> ✖ Nothing fills "datasets$archive_location_id".
#> ℹ A conformance report will raise 1 finding; fill them in the source spec.
validate_define(define)
#> artoo Define-XML Schema Check
#> =============================
#> 
#> Summary
#> -------
#> Document: file1f7e19892d66.xml
#> Define-XML version: 2.1
#> Schema valid: yes
#> 
#> No findings.
```

Pass `html = TRUE` to also render the document through the CDISC
stylesheet. One quirk of that stylesheet to not chase: every 2.1 dataset
heading ends `... -` with the class blank, because the heading reads the
2.0 class *attribute* and 2.1 records the class as an *element* —
CDISC’s own published 2.1 examples render the same bare dash, and the
class does appear in the Datasets summary table.

And
[`lint_define()`](https://vthanik.github.io/artoo/reference/lint_define.md)
walks the reference graph the schema cannot see — an OID in Define-XML
is a plain string as far as the schema is concerned, so a reference
pointing at nothing is schema-valid:

``` r

lint_define(define)
#> artoo Define-XML Reference Check
#> ================================
#> 
#> Summary
#> -------
#> Document: file1f7e19892d66.xml
#> Definitions: 198    References: 244
#> External codelists (exempt from the orphan check): 2
#> 
#> Findings Summary
#> ----------------
#>   error    0
#>   warning  4
#>   note     0
#> 
#> Warnings
#> --------
#> [define_orphan_leaf] Document LF.ADQSADAS is defined but nothing references it.
#> [define_orphan_standard] Standard STD.CT.01 is defined but nothing references it.
#> [define_orphan_standard] Standard STD.CT.02 is defined but nothing references it.
#> [define_orphan_standard] Standard STD.5 is defined but nothing references it.
```

Read the severities, not the count. An **error** is a reference pointing
at nothing, and it means the document is wrong. A **warning** is usually
an orphan — something defined that nothing uses — which a valid document
may well have, and this bundled spec does: it is scoped to two datasets
and still names documents and standards the others used. Nothing here is
dangling, which is the line that matters.

## What a workbook cannot carry

A workbook is an interchange format, not a lossless one. A spec that
came from a define.xml knows things no sheet has a column for — the OIDs
the sponsor chose, which standard each dataset follows, whether a
codelist was extended. artoo names them rather than dropping them
quietly:

``` r

book2 <- tempfile(fileext = ".xlsx")
write_spec(adam_spec, book2)
#> Warning: A Pinnacle 21 workbook cannot carry all of this spec.
#> ✖ datasets: "itemgroupoid" and "archive_location_id"
#> ✖ variables: "itemoid" and "origin_description"
#> ✖ where_clauses: "itemoid"
#> ✖ codelists: "extended", "standard_id", and "is_non_standard"
#> ✖ standards: "is_primary" and "order"
#> ✖ arm_displays: "page_type", "page_title", and "order"
#> ✖ arm_results: "documentation_pages", "documentation_page_type",
#>   "documentation_page_title", and "order"
#> ℹ That is dropped here; write ".json" to keep the spec whole.
```

Each line names the columns that sheet has no place for. Write a `.json`
path instead when you need the spec back exactly — that format is
lossless by construction, and it is the one to archive.

## Where to next

- [Specifications](https://vthanik.github.io/artoo/articles/specs.md) —
  the same workbook from the R side: read, inspect, repair, and write.
- [Conform &
  validate](https://vthanik.github.io/artoo/articles/conform.md) — apply
  the spec to data and see every finding.
- [Get started](https://vthanik.github.io/artoo/articles/artoo.md) — the
  whole round trip.
