# Validate a Define-XML document against its CDISC schema

Schema-validates a `define.xml` against the Clinical Data Interchange
Standards Consortium (CDISC) XML Schema that artoo bundles, offline. Use
it on a document from any source, whether or not artoo wrote it, as the
first gate before a submission package leaves your hands.

## Usage

``` r
validate_define(path, version = NULL)
```

## Arguments

- path:

  *Define-XML document to validate.* `<character(1)>: required`.

- version:

  *Define-XML version to validate against.* `<character(1)> | NULL`.
  `NULL` (default) reads it from the document's `def` namespace. Supply
  `"2.0"` or `"2.1"` to assert a version instead, which turns a version
  mismatch into findings rather than silent success.

## Value

*An `artoo_check` object.* Its `@findings` data frame has columns
`check`, `dimension`, `severity`, `dataset`, `variable`, `message`, and
is empty when the document is valid. Print it for the sectioned report.

## Details

**The version is detected, not assumed.** Define-XML 2.0 and 2.1 declare
different `def` namespaces, so the document says which schema applies.
Passing `version` overrides that, which is how you confirm a file really
is the version it claims.

**Schema validity is a floor, not a ceiling.** A document can satisfy
the schema and still be unfit to submit. Two whole classes of defect are
invisible here: a reference that points at nothing, and a definition
that nothing points at. Neither is expressible in XML Schema. Use
[`lint_define()`](https://vthanik.github.io/artoo/reference/lint_define.md)
for those.

## See also

**Check further:**
[`lint_define()`](https://vthanik.github.io/artoo/reference/lint_define.md)
for reference integrity, which schema validation cannot see.

**Specs:**
[`read_spec()`](https://vthanik.github.io/artoo/reference/read_spec.md)
reads a Define-XML document into an
[`artoo_spec()`](https://vthanik.github.io/artoo/reference/artoo_spec.md).

## Examples

``` r
# ---- Example 1: a conforming document ----
#
# artoo bundles both CDISC schema trees, so validation runs offline. The
# bundled minimal example conforms, so the findings table comes back empty
# and the summary records which version was detected.
minimal <- system.file("extdata", "define-minimal.xml", package = "artoo")
report <- validate_define(minimal)
nrow(report@findings)
#> [1] 0
report@summary[c("define_version", "valid")]
#> $define_version
#> [1] "2.1"
#> 
#> $valid
#> [1] TRUE
#> 

# ---- Example 2: a document that breaks the schema ----
#
# Give ItemGroupDef/@Repeating a value outside its enumeration. The schema
# catches it, and each violation becomes one finding naming the element and
# the line it sits on.
broken <- tempfile(fileext = ".xml")
writeLines(
  sub('Repeating="No"', 'Repeating="Maybe"', readLines(minimal), fixed = TRUE),
  broken
)
bad <- validate_define(broken)
bad@summary$valid
#> [1] FALSE
substr(bad@findings$message[1], 1, 60)
#> [1] "Element '{http://www.cdisc.org/ns/odm/v1.3}ItemGroupDef', at"
```
