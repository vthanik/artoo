# Check the reference integrity of a Define-XML document

Reports OID references that resolve to nothing, and definitions that
nothing references. Neither is expressible in XML Schema, so a document
can pass
[`validate_define()`](https://vthanik.github.io/artoo/reference/validate_define.md)
and still fail here.

## Usage

``` r
lint_define(path)
```

## Arguments

- path:

  *Define-XML document to check.* `<character(1)>: required`.

## Value

*An `artoo_check` object.* Its `@findings` data frame has columns
`check`, `dimension`, `severity`, `dataset`, `variable`, `message`, and
is empty when every reference resolves and every definition is used.

## Details

**Findings are directional.** A dangling reference and an orphan
definition have different causes and different consequences, so they are
separate conditions. Dangling references are errors. Orphans are
warnings, except for an orphaned value list: a `def:ValueListDef` that
no `def:ValueListRef` points at means every value-level definition it
holds renders nowhere, which is a silent loss of submission metadata
rather than untidiness.

**Two exemptions prevent false positives.** A `CodeList` backed by an
`ExternalCodeList` (MedDRA, WHODrug, ISO 3166) is a dictionary reference
and is not expected to be referenced by a `CodeListRef`. A `CodeList`
reached through `ItemRef/@RoleCodeListOID` counts as referenced. Without
these, every real adverse-event or medication define reports spurious
orphans.

## See also

**Validate first:**
[`validate_define()`](https://vthanik.github.io/artoo/reference/validate_define.md)
for schema conformance, which this complements rather than repeats.

## Examples

``` r
# ---- Example 1: a sound document ----
#
# The bundled minimal example resolves cleanly, so the findings table is
# empty and the summary counts what was inspected.
minimal <- system.file("extdata", "define-minimal.xml", package = "artoo")
report <- lint_define(minimal)
nrow(report@findings)
#> [1] 0
report@summary$n_definitions
#> [1] 9

# ---- Example 2: a reference that resolves to nothing ----
#
# Point a variable's codelist reference at an OID no CodeList defines. The
# document still passes schema validation; only the lint sees it.
broken <- tempfile(fileext = ".xml")
writeLines(
  sub('CodeListOID="CL.SEX"', 'CodeListOID="CL.MISSING"',
    readLines(minimal),
    fixed = TRUE
  ),
  broken
)
validate_define(broken)@summary$valid
#> [1] TRUE
lint_define(broken)@findings[, c("check", "severity", "message")]
#>                      check severity
#> 1 define_dangling_codelist    error
#> 2   define_orphan_codelist  warning
#>                                                                            message
#> 1 A codelist reference on CodeListRef references CL.MISSING, which is not defined.
#> 2                            Codelist CL.SEX is defined but nothing references it.
```
