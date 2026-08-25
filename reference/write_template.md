# Write a blank Pinnacle 21 workbook to fill in

Emit an empty Excel workbook with the sheets and column headers
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
recognises, so a specification can be authored from the shape the reader
wants rather than guessed at. Fill it in, read it back with
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md),
and write a define.xml with
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md).

## Usage

``` r
write_template(path, version = "2.1")
```

## Arguments

- path:

  *Destination workbook.* `<character(1)>: required`. An `.xlsx` path.
  Needs the `writexl` package.

- version:

  *Define-XML version the workbook is for.*
  `<character(1)>: default "2.1"`.

  - `"2.1"` (default)

  - `"2.0"` – omits the columns 2.1 introduced.

## Value

*The output `path`, invisibly.* Fill it in, then read it with
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md).

## Details

**The headers are the reader's own.** Every sheet name and every column
comes from the same maps
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
matches against, so a template cannot offer a column that would be
silently ignored, and a column added to the reader appears here without
a second list to maintain.

**A 2.0 template is narrower.** Columns Define-XML 2.1 introduced
(`SubClass` and `Has No Data` on Datasets, `Source` and `Has No Data` on
Variables) are omitted from a 2.0 template, because a column no 2.0
document can carry is one an author fills for nothing.

**Only Datasets and Variables are required.** Every other sheet may be
left empty;
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
omits what it finds nothing in.

**Conditions live on the `WhereClauses` sheet.** A value-level row names
a condition by its `ID` and the `WhereClauses` sheet defines it, one row
per comparison, rows sharing an `ID` being ANDed together. This is the
shape the widest range of tools import.
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
also reads the newer shape, which drops that sheet and writes the
condition into the `Where Clause` cell as an expression.

**`Standards` is an artoo extension.** Define-XML 2.1 carries a
`def:Standards` block that the workbook format has no sheet for, so
artoo offers one rather than lose it.

## See also

**Fill it in:**
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
reads the completed workbook.

**Then write:**
[`write_spec()`](https://vthanik.github.io/artoo/reference/write_spec.md)
turns the spec into a define.xml,
[`validate_define()`](https://vthanik.github.io/artoo/reference/validate_define.md)
and
[`lint_define()`](https://vthanik.github.io/artoo/reference/lint_define.md)
check the result.

## Examples

``` r
# ---- Example 1: a blank workbook, and what it offers ----
#
# The template carries every sheet read_spec() recognises. Datasets and
# Variables are the two it requires; the rest may be left empty.
path <- tempfile(fileext = ".xlsx")
write_template(path)
if (requireNamespace("readxl", quietly = TRUE)) {
  readxl::excel_sheets(path)
}
#>  [1] "Study"             "Datasets"          "Variables"        
#>  [4] "ValueLevel"        "WhereClauses"      "Codelists"        
#>  [7] "Dictionaries"      "Methods"           "Comments"         
#> [10] "Documents"         "Standards"         "Analysis Displays"
#> [13] "Analysis Results"  "Analysis Criteria"

# ---- Example 2: the 2.0 template omits what 2.0 cannot carry ----
#
# `Source` records who collected a value, which Define-XML 2.1 added. A
# 2.0 workbook has no column for it, so the template does not offer one.
old <- tempfile(fileext = ".xlsx")
write_template(old, version = "2.0")
if (requireNamespace("readxl", quietly = TRUE)) {
  setdiff(
    names(readxl::read_excel(path, sheet = "Variables")),
    names(readxl::read_excel(old, sheet = "Variables"))
  )
}
#> [1] "Source"      "Has No Data"
```
