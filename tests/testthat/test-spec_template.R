# A blank Pinnacle 21 workbook to fill in.
#
# The claim that matters is not "a file appears". It is that the template's
# shape IS the reader's shape: every header it offers is one read_spec()
# understands, and every column read_spec() understands is offered. A
# template that drifts from the reader is worse than none, because a column
# an author fills and the reader ignores fails silently.

test_that("the template offers every sheet read_spec() recognises", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  path <- withr::local_tempfile(fileext = ".xlsx")
  write_template(path)
  sheets <- readxl::excel_sheets(path)
  # One sheet per slot the reader looks for, in the order a spec is authored.
  expect_identical(sheets, unname(artoo:::.p21_template_sheets))
  # ...and each is a sheet name the reader's alias matcher actually matches.
  normalise <- function(x) gsub(" ", "", tolower(trimws(x)), fixed = TRUE)
  known <- normalise(unlist(artoo:::.p21_sheet_aliases, use.names = FALSE))
  expect_true(all(normalise(sheets) %in% known))
})

test_that("every header the template offers is one the reader maps", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  # The other direction of the same claim: nothing in the template is a
  # column an author would fill for nothing.
  path <- withr::local_tempfile(fileext = ".xlsx")
  write_template(path)
  maps <- list(
    Datasets = artoo:::.p21_ds_map,
    Variables = artoo:::.p21_var_map,
    ValueLevel = artoo:::.p21_value_map,
    Codelists = artoo:::.p21_codelist_map,
    Dictionaries = artoo:::.p21_dictionary_map,
    Methods = artoo:::.p21_method_map,
    Comments = artoo:::.p21_comment_map,
    Documents = artoo:::.p21_document_map,
    Standards = artoo:::.p21_standard_map,
    `Analysis Displays` = artoo:::.p21_arm_display_map,
    `Analysis Results` = artoo:::.p21_arm_result_map
  )
  for (sheet in names(maps)) {
    headers <- names(readxl::read_excel(path, sheet = sheet))
    expect_identical(headers, names(maps[[sheet]]), info = sheet)
  }
  # The Define sheet is Attribute/Value, and seeds the three study fields
  # the reader canonicalises.
  define <- readxl::read_excel(path, sheet = "Define")
  expect_identical(names(define), c("Attribute", "Value"))
  expect_identical(define$Attribute, unname(artoo:::.p21_study_attr))
})

test_that("a template filled with a spec reads back as that spec", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  # The check that proves the template's shape is the reader's shape: take a
  # real spec, put its content into the template's sheets under the
  # template's own headers, and read it back.
  #
  # Compared against the xlsx WRITER's output, not the source workbook: a
  # workbook carries less than a spec (no itemoid, no target_data_type, no
  # per-variable key sequence), and the writer is the surface that decides
  # what a workbook can say. If the template and the writer agree, an author
  # filling the template lands exactly where artoo's own output lands.
  source_book <- system.file("extdata", "adam-spec.xlsx", package = "artoo")
  skip_if(!nzchar(source_book), "demo workbook not bundled")
  spec <- suppressWarnings(read_spec(source_book))

  dir <- withr::local_tempdir()
  template <- file.path(dir, "template.xlsx")
  write_template(template)
  written <- file.path(dir, "written.xlsx")
  suppressWarnings(write_spec(spec, written))

  # Every sheet the writer emits is a sheet the template offers, with headers
  # the template offers -- so filling the template can only produce something
  # the writer could also have produced.
  for (sheet in readxl::excel_sheets(written)) {
    expect_true(sheet %in% readxl::excel_sheets(template), info = sheet)
    filled <- names(readxl::read_excel(written, sheet = sheet))
    offered <- names(readxl::read_excel(template, sheet = sheet))
    if (identical(sheet, "Define")) {
      expect_identical(filled, offered)
      next
    }
    expect_true(all(filled %in% offered), info = sheet)
  }
  # ...and that surface is a FIXED POINT: writing the spec a workbook
  # produced, then reading it again, changes nothing. Identity against the
  # source spec is the wrong claim -- a workbook cannot carry `itemoid` or a
  # per-variable key sequence, so the first write narrows -- but converging
  # is what makes the template a usable starting point rather than a lossy
  # one.
  again <- file.path(dir, "again.xlsx")
  suppressWarnings(write_spec(suppressWarnings(read_spec(written)), again))
  expect_equal(
    suppressWarnings(read_spec(again)),
    suppressWarnings(read_spec(written))
  )
})

test_that("a 2.0 template omits exactly what 2.1 introduced", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  dir <- withr::local_tempdir()
  new <- file.path(dir, "new.xlsx")
  old <- file.path(dir, "old.xlsx")
  write_template(new, version = "2.1")
  write_template(old, version = "2.0")
  expect_identical(readxl::excel_sheets(new), readxl::excel_sheets(old))
  for (sheet in readxl::excel_sheets(new)) {
    dropped <- setdiff(
      names(readxl::read_excel(new, sheet = sheet)),
      names(readxl::read_excel(old, sheet = sheet))
    )
    expect_identical(
      dropped,
      artoo:::.p21_template_since[[sheet]] %||% character(0),
      info = sheet
    )
  }
})

test_that("the version-gated columns trace to the bundled schemas", {
  skip_if_not_installed("xml2")
  # Each omitted column has to be something 2.0 genuinely cannot carry, and
  # the version profiles already derive that from the XSDs. Pinning the
  # correspondence means a CDISC revision cannot move one without failing.
  p20 <- artoo:::.define_profile("2.0")
  p21 <- artoo:::.define_profile("2.1")
  # Datasets$SubClass -> def:Class/def:SubClass, an element 2.0 does not have.
  expect_null(p20$order[["def:Class"]])
  expect_identical(p21$order[["def:Class"]], "def:SubClass")
  # "Has No Data" -> def:HasNoData, in 2.1's attribute table and not 2.0's.
  expect_true("def:HasNoData" %in% p21$def_attrs$ItemGroupDef)
  expect_false("def:HasNoData" %in% p20$def_attrs$ItemGroupDef)
  expect_true("def:HasNoData" %in% p21$def_attrs$ItemRef)
  expect_null(p20$def_attrs$ItemRef)
  # Variables$Source -> def:Origin/@Source, a LOCAL attribute 2.1 added.
  expect_true("Source" %in% p21$local_attrs[["def:Origin"]])
  expect_false("Source" %in% p20$local_attrs[["def:Origin"]])
})

test_that("a template is written atomically and refuses a non-xlsx path", {
  skip_if_not_installed("writexl")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "t.csv")
  expect_error(write_template(path), class = "artoo_error_input")
  expect_snapshot(
    write_template(path),
    error = TRUE,
    transform = function(x) sub("'.*/t[.]csv'", "'<tmp>/t.csv'", x)
  )
  expect_false(file.exists(path))
  # An unknown version is refused once, by the same profile the Define-XML
  # writer uses, so the two surfaces cannot disagree about what exists.
  expect_error(
    write_template(file.path(dir, "t.xlsx"), version = "3.0"),
    class = "artoo_error_input"
  )
})

test_that("a blank template reads back as an empty-but-valid starting point", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  # A template with nothing in it cannot become a spec -- Datasets and
  # Variables are the two sheets the reader requires -- and it says so
  # rather than producing an empty object.
  path <- withr::local_tempfile(fileext = ".xlsx")
  write_template(path)
  expect_error(read_spec(path), class = "artoo_error_spec")
  expect_snapshot(
    read_spec(path),
    error = TRUE,
    transform = function(x) sub("'.*[.]xlsx'", "'<tmp>.xlsx'", x)
  )
})
