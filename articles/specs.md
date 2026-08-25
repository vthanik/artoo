# Specifications

A `artoo_spec` is artoo’s single source of truth: the variables, CDISC
data types, lengths, labels, controlled-terminology codelists, and sort
keys for exactly **one** CDISC standard. Read one from the metadata you
already have, inspect it as plain data frames, fix it in R when the data
disagrees, and write it back — the spec is the contract every later step
honors.

## 1. Read a spec

[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
ingests a specification from Define-XML 2.x, a Pinnacle 21 workbook, or
artoo’s own native JSON, and returns a `artoo_spec`. The bundled ADaM
spec also ships as a P21 workbook, so this runs as-is:

``` r

p21 <- system.file("extdata", "adam-spec.xlsx", package = "artoo")
spec <- read_spec(p21)
spec
```

    <artoo_spec>
    Study: CDISC-Sample
    Standard: ADaMIG 1.1
    Datasets:  2
    Variables: 104
    Codelists: 20
    Methods: 45
    Comments: 11
    Documents: 8
    Spec for: ADSL, ADAE

A workbook can carry several standards or duplicate roles; scope the
read when you need just one:

``` r

read_spec("define.xml", datasets = "ADSL", on_duplicate = "first")
```

## 2. Inspect with the `spec_*` accessors

Each accessor returns a plain data frame (or character vector), so the
spec slots straight into ordinary base R work — filter, join, summarise.
The datasets a spec covers:

``` r

spec_datasets(spec)
```

    [1] "ADSL" "ADAE"

The variable table is the one you reach for most; here, four columns of
it:

``` r

spec_variables(spec, "ADSL")[, c("variable", "label", "data_type", "length")] |>
  head()
```

      variable                            label data_type length
    1  STUDYID                 Study Identifier    string     12
    2  USUBJID        Unique Subject Identifier    string     11
    3   SUBJID Subject Identifier for the Study    string      4
    4   SITEID            Study Site Identifier    string      3
    5  SITEGR1              Pooled Site Group 1    string      3
    6      ARM       Description of Planned Arm    string     20

The sort keys that
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
will order by, and the controlled terminology a coded variable is bound
to:

``` r

spec_keys(spec, "ADSL")
```

    [1] "STUDYID" "USUBJID"

``` r

head(spec_codelists(spec))
```

      codelist_id order  term decode          name data_type nci_code
    1   CL.AGEGR1    NA   <65   <NA>     Age Group      text     <NA>
    2   CL.AGEGR1    NA 65-80   <NA>     Age Group      text     <NA>
    3   CL.AGEGR1    NA   >80   <NA>     Age Group      text     <NA>
    4  CL.AGEGR1N     1     1    <65 Age Group (N)   integer     <NA>
    5  CL.AGEGR1N     2     2  65-80 Age Group (N)   integer     <NA>
    6  CL.AGEGR1N     3     3    >80 Age Group (N)   integer     <NA>
      sas_format_name comment_id term_nci_code rank extended standard_id
    1            <NA>       <NA>          <NA>    1       NA        <NA>
    2            <NA>       <NA>          <NA>    2       NA        <NA>
    3            <NA>       <NA>          <NA>    3       NA        <NA>
    4            <NA>       <NA>          <NA>   NA       NA        <NA>
    5            <NA>       <NA>          <NA>   NA       NA        <NA>
    6            <NA>       <NA>          <NA>   NA       NA        <NA>
      is_non_standard term_description
    1              NA             <NA>
    2              NA             <NA>
    3              NA             <NA>
    4              NA             <NA>
    5              NA             <NA>
    6              NA             <NA>

[`spec_standard()`](https://vthanik.github.io/artoo/reference/spec_standard.md),
[`spec_study()`](https://vthanik.github.io/artoo/reference/spec_study.md),
[`spec_methods()`](https://vthanik.github.io/artoo/reference/spec_methods.md),
[`spec_comments()`](https://vthanik.github.io/artoo/reference/spec_comments.md),
and
[`spec_documents()`](https://vthanik.github.io/artoo/reference/spec_documents.md)
expose the remaining slots the same way.

## 3. Fix it in place

When the data disagrees with the spec, fix the spec in one line — never
reach into internals.
[`set_type()`](https://vthanik.github.io/artoo/reference/set_type.md)
retypes a variable; the spec is immutable, so it returns an updated
copy:

``` r

spec <- set_type(spec, "ADSL", AGE = "float")
v <- spec_variables(spec, "ADSL")
v$data_type[v$variable == "AGE"]
```

    [1] "float"

When a check has already found integer-vs-fraction mismatches,
[`repair_spec()`](https://vthanik.github.io/artoo/reference/repair_spec.md)
applies the fix for every one of them at once, from the findings frame:

``` r

findings <- check_spec(cdisc_adsl, spec, "ADSL")
spec <- repair_spec(spec, findings)
```

    No "integer_fraction" or "integer_overflow" findings to repair.
    ℹ The spec is returned unchanged.

## 4. Write it back

[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md)
is the inverse of
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
on each format: native JSON is fully lossless, and the P21 workbook is
the interchange form. Round-trip a corrected spec through JSON:

``` r

out <- tempfile(fileext = ".json")
write_spec(spec, out)
identical(spec_standard(read_spec(out)), spec_standard(spec))
```

    [1] TRUE

Because the two verbs are inverses, format conversion is one
composition:

``` r

read_spec("define.xml") |> write_spec("spec.xlsx")
```

## 5. Write the define.xml

A `.xml` path writes Define-XML. The version follows the spec’s own
`define_version` unless you say otherwise, and both 2.0 and 2.1 are
written, so a spec read from one converts to the other:

``` r

define <- file.path(tempdir(), "define.xml")
write_spec(adam_spec, define)
write_spec(adam_spec, file.path(tempdir(), "define20.xml"), version = "2.0")
```

    Warning: Define-XML 2.0 cannot carry everything this spec holds.
    ✖ Dropped or rewritten: "def:Standards (only the primary standard survives)",
      "def:StandardOID", "def:IsNonStandard", "def:Origin/@Source", "def:SubClass",
      "ODM/@def:Context", and "def:PDFPageRef/@Title".
    ℹ Write the spec as "2.1", or to native JSON, to keep it whole.

artoo schema-validates what it built against the bundled CDISC schemas
*before* the file reaches its destination, so an invalid document never
replaces a good one. Read it back with the two checks —
[`validate_define()`](https://vthanik.github.io/artoo/reference/validate_define.md)
for the schema,
[`lint_define()`](https://vthanik.github.io/artoo/reference/lint_define.md)
for the reference integrity a schema cannot see, because an OID is
`odm:oidref` rather than `xs:ID` and libxml2 never resolves one:

``` r

validate_define(define)
```

    artoo Define-XML Schema Check
    =============================

    Summary
    -------
    Document: define.xml
    Define-XML version: 2.1
    Schema valid: yes

    No findings.

``` r

lint_define(define)
```

    artoo Define-XML Reference Check
    ================================

    Summary
    -------
    Document: define.xml
    Definitions: 198    References: 255
    External codelists (exempt from the orphan check): 2

    Findings Summary
    ----------------
      error    0
      warning  2
      note     0

    Warnings
    --------
    [define_orphan_leaf] Document LF.ADQSADAS is defined but nothing references it.
    [define_orphan_standard] Standard STD.5 is defined but nothing references it.

The two orphan warnings are honest: the bundled pilot spec is scoped to
ADSL and ADAE, and it still names a leaf and a CDISC standard that only
the datasets outside that scope used. An orphan is a warning rather than
an error because a define.xml with one is valid and loads — a *dangling*
reference is the error, and there are none.

The write also says what the document is missing. None of these is
required by the schema — the document validates without them — and every
one draws a conformance finding, so the write names them rather than
refusing:

``` r

sparse <- artoo_spec(
  datasets = data.frame(dataset = "DM", structure = "One record per subject"),
  variables = data.frame(dataset = "DM", variable = "USUBJID", data_type = "string"),
  standard = "SDTMIG 3.4"
)
invisible(write_spec(sparse, file.path(tempdir(), "sparse.xml")))
```

    Warning: The spec is not submission-grade.
    ✖ Nothing fills "datasets$label", "datasets$class", "datasets$domain",
      "datasets$purpose", "datasets$repeating", "datasets$archive_location_id",
      "variables$label", "variables$origin", and "variables$length".
    ℹ A conformance report will raise 9 findings; fill them in the source spec.

    Warning: The `def:Standards` block was not written.
    ✖ The spec names "SDTMIG 3.4" but carries no `standards` table.
    ℹ Define-XML 2.1 needs a name, version, type and status for each standard.

### Let the data fill in what it knows

artoo can read the datasets a define describes, which a spec-only tool
cannot. Pass `data =` and a blank length is filled from the real maximum
byte width, and value-level metadata is derived for the standard
findings shapes — a result keyed by its test code, `AVAL` by `PARAMCD` —
each derived row carrying the type and width of the rows it covers:

``` r

informed <- file.path(tempdir(), "informed.xml")
invisible(
  write_spec(sdtm_spec, informed, data = list(VS = cdisc_vs, DM = cdisc_dm))
)
```

    Warning: 4 declared lengths are shorter than the data.
    ✖ "DM.STUDYID", "VS.STUDYID", "VS.VSPOS", and "VS.VISIT": widened to the real
      maximum.
    ℹ A length below the real maximum is a conformance finding, so the data wins.

    8 declared lengths are longer than this data.
    ℹ Left as declared: a length is a claim about the domain, not about one
      extract.

``` r

lint_define(informed)
```

    artoo Define-XML Reference Check
    ================================

    Summary
    -------
    Document: informed.xml
    Definitions: 198    References: 299
    External codelists (exempt from the orphan check): 1

    Findings Summary
    ----------------
      error    0
      warning  10
      note     0

    Warnings
    --------
    [define_orphan_leaf] Document LF.DI is defined but nothing references it.
    [define_orphan_leaf] Document LF.EC is defined but nothing references it.
    [define_orphan_leaf] Document LF.EX is defined but nothing references it.
    [define_orphan_leaf] Document LF.LB is defined but nothing references it.
    [define_orphan_leaf] Document LF.XS is defined but nothing references it.
    [define_orphan_standard] Standard STD.2 is defined but nothing references it.
    [define_orphan_standard] Standard STD.2_1 is defined but nothing references it.
    [define_orphan_standard] Standard STD.5 is defined but nothing references it.
    [define_missing_origin] Variable IT.VS.VSTPT carries no Origin, and neither do its value-level items.
    [define_missing_origin] Variable IT.VS.VSTPTNUM carries no Origin, and neither do its value-level items.

A stated length shorter than the data is widened, because a length below
the real maximum is a conformance finding. One *longer* is left alone: a
length is a claim about the domain, not about one extract.

### Start from a blank workbook

[`write_template()`](https://vthanik.github.io/artoo/reference/write_template.md)
writes an empty Pinnacle 21 workbook with the sheets and headers
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
recognises, so a spec can be authored from the shape the reader wants
rather than guessed at:

``` r

template <- tempfile(fileext = ".xlsx")
write_template(template)
readxl::excel_sheets(template)
```

     [1] "Study"             "Datasets"          "Variables"
     [4] "ValueLevel"        "WhereClauses"      "Codelists"
     [7] "Dictionaries"      "Methods"           "Comments"
    [10] "Documents"         "Standards"         "Analysis Displays"
    [13] "Analysis Results"  "Analysis Criteria"

## Where to next

- [Conform &
  validate](https://vthanik.github.io/artoo/articles/conform.md) — apply
  this spec to data, then check every finding.
- [Formats & lossless
  conversion](https://vthanik.github.io/artoo/articles/convert.md) —
  move a conformed dataset between formats without loss.
- [Recipes](https://vthanik.github.io/artoo/articles/recipes.md) — the
  spec in an end-to-end ADaM and SDTM build.
- [Get started](https://vthanik.github.io/artoo/articles/artoo.md) — the
  round-trip from the top.
