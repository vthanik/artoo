# Write a specification to native JSON or a P21 Excel workbook

Serialise a `artoo_spec`, dispatching on the file extension: a `.json`
path writes artoo's native, lossless JSON; a `.xlsx` path writes a
Pinnacle 21 (P21) style Excel workbook. Both are inverses of
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
on their format, which makes the spec converters free compositions:
`read_spec("define.xml") |> write_spec("spec.xlsx")` is a Define-XML to
P21 bridge in one line.

## Usage

``` r
write_spec(spec, path)
```

## Arguments

- spec:

  *The specification to serialise.* `<artoo_spec>: required`. Build one
  with
  [`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md)
  or
  [`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md).

- path:

  *Destination file.* `<character(1)>: required`. The extension picks
  the format: `.json` (native, lossless) or `.xlsx` (P21 interchange;
  needs the `writexl` package). Any other extension aborts with
  `artoo_error_input`.

## Value

*The output `path`, invisibly.* Read it back with
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md).

## Details

**Native JSON is the lossless format.** Each slot is written as an array
of row objects, with `NA` encoded as JSON `null` and numbers at full
precision, so
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
rebuilds an identical `artoo_spec` through
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md).
Object keys are emitted in a fixed order, so writing the same spec twice
yields byte-identical output.

**P21 xlsx is the interchange format.** Sheets are emitted with the
headers the P21 reader recognises (Define, Datasets, Variables,
ValueLevel, Codelists, Methods, Comments, Documents; empty optional
sheets are omitted), foreign keys repeated on every row (no merged
cells), and the spec's
[`spec_standard()`](https://vthanik.github.io/artoo/reference/spec_standard.md)
as the Datasets sheet's `Standard` column. The study row writes back as
the Define sheet's Attribute/Value pairs (`StudyName`,
`StudyDescription`, `ProtocolName`). The `Data Type` column is written
in the Define-XML / ODM vocabulary the workbook expects: a character
variable is `text` (not the Dataset-JSON `string`), and `decimal` /
`double` collapse to `float`, `boolean` / `URI` to `text`.

Columns the P21 vocabulary does not model are not lost: a foreign column
carried on a slot is re-emitted verbatim under its own header, so an
xlsx round-trip keeps user columns.

**Note:** fields with no P21 column (`itemoid`, `target_data_type`,
per-variable `key_sequence`) do not survive an xlsx round-trip; persist
to JSON when you need the spec back exactly. The `Data Type` re-encoding
is also non-injective: `decimal`, `double`, `boolean`, and `URI` fold to
`float` or `text` on a read-back. A Define-XML `partialDate` /
`partialDatetime` (and the other partial / incomplete subtypes) is read
as the base `date` / `datetime` – CDISC Dataset-JSON v1.1 has no partial
dataType – so it is written back as the base type.

## See also

**Inverse:**
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
reads native JSON, a P21 Excel workbook, or Define-XML back into a
`artoo_spec`.

**Build / inspect:**
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md),
[`spec_datasets()`](https://vthanik.github.io/artoo/reference/spec_datasets.md),
[`spec_variables()`](https://vthanik.github.io/artoo/reference/spec_variables.md),
[`spec_standard()`](https://vthanik.github.io/artoo/reference/spec_standard.md).

## Examples

``` r
# ---- Example 1: persist a spec to JSON, then read it back ----
#
# Build a spec from the bundled CDISC-pilot tables, write it to a temp
# JSON file, and confirm read_spec() reconstructs it intact.
spec <- artoo_spec(
  cdisc_adam_datasets, cdisc_adam_variables,
  codelists = cdisc_codelists
)
path <- tempfile(fileext = ".json")
write_spec(spec, path)
identical(read_spec(path), spec)
#> [1] TRUE

# ---- Example 2: the same spec as a P21 workbook ----
#
# The .xlsx path emits P21-shaped sheets; reading the workbook back
# recovers the P21-representable surface (here: the dataset names).
if (requireNamespace("writexl", quietly = TRUE)) {
  xlsx <- tempfile(fileext = ".xlsx")
  write_spec(spec, xlsx)
  spec_datasets(read_spec(xlsx))
}
#> [1] "ADSL"
```
