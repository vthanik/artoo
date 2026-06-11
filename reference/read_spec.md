# Read a specification from JSON, Excel, or Define-XML

Read a clinical-dataset specification into a validated `artoo_spec`,
dispatching on the file extension: artoo's native JSON (the inverse of
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md)),
a Pinnacle 21 (P21) Excel workbook, or a native Define-XML 2.0/2.1
document. The returned spec is the lingua franca the rest of artoo
applies and serialises.

## Usage

``` r
read_spec(path, datasets = NULL, on_duplicate = c("error", "first", "warn"))
```

## Arguments

- path:

  *The specification file to read.* `<character(1)>: required`. A
  `.json` (native) or `.xlsx` / `.xls` (P21) file.

  **Requirement:** reading a P21 workbook needs the `readxl` package.

- datasets:

  *Read only these datasets.* `<character> | NULL`. `NULL` (default)
  reads the whole spec. Otherwise the spec is scoped to the named
  datasets before validation, so one broken sheet elsewhere in a
  workbook cannot block the dataset you are working on. An unknown name
  aborts listing what the file defines.

- on_duplicate:

  *Policy for a variable defined more than once.* `<character(1)>`. A
  workbook row duplicated within one dataset makes the spec ambiguous;
  the finding is reported with its source location (sheet and row
  numbers for Excel). One of:

  - `"error"` (default) abort, naming each duplicate's rows.

  - `"first"` keep the first definition of each, dropping the rest with
    a message.

  - `"warn"` keep the first definition and warn (`artoo_warning_spec`).

## Value

*A validated `artoo_spec`.* Inspect it with
[`spec_datasets()`](https://vthanik.github.io/artoo/reference/spec_datasets.md)
/
[`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md),
check it with
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md),
or persist it with
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md).

## Details

**Three formats, one validator.** A `.json` file is read as artoo native
JSON; a `.xlsx` / `.xls` file is read as a P21 workbook; a `.xml` file
is read as Define-XML 2.x. Either way the result is built through
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md),
so type canonicalisation and cross-slot integrity checks are identical
regardless of source.

**Define-XML ingestion** (needs the `xml2` package). ItemGroupDefs
become datasets (keys derived from the ItemRef KeySequence), ItemRef +
ItemDef pairs become variables, CodeLists become codelists
(`def:ExtendedValue = "Yes"` marks an extended term), MethodDefs /
CommentDefs / leaves become the supporting slots, and ValueListDefs land
in the value-level slot with their where-clauses rendered as readable
text.

**Note:** an `ExternalCodeList` (MedDRA, ISO-3166) names a dictionary,
not an enumerable membership list; it is dropped, and variables that
referenced it carry no codelist. Define-XML v1.0 (the 2005 model) is
refused with guidance.

**P21 ingestion.** Sheets are located by a tolerant alias match (case-,
space-, and spelling-variant insensitive). Datasets and Variables are
required; Codelists and ValueLevel are optional (the latter becomes the
spec's value-level slot). Every cell is read as text, then the dataset
and codelist foreign keys are forward-filled to recover merged cells
(which the Excel reader returns as `NA` on continuation rows). A key
that cannot be resolved aborts with `artoo_error_spec` rather than being
silently dropped.

## See also

**Inverse:**
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md)
serialises a spec to native JSON.

**Build / inspect:**
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md),
[`spec_datasets()`](https://vthanik.github.io/artoo/reference/spec_datasets.md),
[`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md),
[`validate_spec()`](https://vthanik.github.io/artoo/reference/validate_spec.md).

## Examples

``` r
# ---- Example 1: round-trip a spec through native JSON ----
#
# write_spec() and read_spec() are inverses on the JSON path: the spec
# that comes back is identical to the one written.
spec <- artoo_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
path <- tempfile(fileext = ".json")
write_spec(spec, path)
back <- read_spec(path)
identical(back, spec)
#> [1] TRUE

# ---- Example 2: scope the read to one dataset ----
#
# `datasets =` reads just the domain you are working on -- validation is
# scoped with it, so a problem elsewhere in the workbook cannot block
# this dataset.
dm_spec <- read_spec(path, datasets = "DM")
spec_datasets(dm_spec)
#> [1] "DM"
head(spec_variables(dm_spec, "DM")[, c("variable", "label", "data_type")])
#>    variable                             label data_type
#> 49  STUDYID                  Study Identifier    string
#> 50   DOMAIN               Domain Abbreviation    string
#> 51  USUBJID         Unique Subject Identifier    string
#> 52   SUBJID  Subject Identifier for the Study    string
#> 53  RFSTDTC Subject Reference Start Date/Time    string
#> 54  RFENDTC   Subject Reference End Date/Time    string
```
