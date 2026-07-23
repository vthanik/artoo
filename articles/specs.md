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
    Codelists: 30
    Methods: 54
    Comments: 22
    Documents: 9
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

      codelist_id order  term decode extended comment_id
    1   CL.AGEGR1    NA   <65   <NA>       NA       <NA>
    2   CL.AGEGR1    NA 65-80   <NA>       NA       <NA>
    3   CL.AGEGR1    NA   >80   <NA>       NA       <NA>
    4  CL.AGEGR1N     1     1    <65       NA       <NA>
    5  CL.AGEGR1N     2     2  65-80       NA       <NA>
    6  CL.AGEGR1N     3     3    >80       NA       <NA>

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
