# The structural builders, at the level the writer's round-trip tests cannot
# reach: the version branches, the derived defaults, and the refusals.

p21 <- function() artoo:::.define_profile("2.1")
p20 <- function() artoo:::.define_profile("2.0")

test_that("def:Class is an element in 2.1 and an attribute in 2.0", {
  el <- artoo:::.dx_class("FINDINGS", "TIME-TO-EVENT", p21())
  expect_identical(el$name, "def:Class")
  expect_identical(el$attrs$Name, "FINDINGS")
  expect_identical(el$kids[["def:SubClass"]]$attrs$Name, "TIME-TO-EVENT")

  attr20 <- artoo:::.dx_class("FINDINGS", "TIME-TO-EVENT", p20())
  expect_type(attr20, "character")
  expect_identical(attr20, "FINDINGS")

  expect_null(artoo:::.dx_class(NA_character_, NA_character_, p21()))
})

test_that("a class outside the 2.1 vocabulary is refused", {
  expect_error(
    artoo:::.dx_class("MADE UP CLASS", NA_character_, p21()),
    class = "artoo_error_define"
  )
})

test_that("def:Context exists in 2.1 and not in 2.0", {
  expect_identical(
    artoo:::.dx_context("Submission", p21()),
    list(`def:Context` = "Submission")
  )
  expect_identical(artoo:::.dx_context("Submission", p20()), list())
})

test_that("Purpose follows the CDISC standard when the spec is silent", {
  expect_identical(
    artoo:::.dx_purpose(NA_character_, "ADaMIG 1.1", p21()),
    "Analysis"
  )
  expect_identical(
    artoo:::.dx_purpose(NA_character_, "SDTMIG 3.4", p21()),
    "Tabulation"
  )
  expect_identical(artoo:::.dx_purpose(NA_character_, NA, p21()), "Tabulation")
  # An explicit value is honoured, and checked.
  expect_identical(
    artoo:::.dx_purpose("Analysis", "SDTMIG 3.4", p21()),
    "Analysis"
  )
  expect_error(
    artoo:::.dx_purpose("Whatever", NA, p21()),
    class = "artoo_error_define"
  )
})

test_that("def:Structure falls back to the keys, then refuses", {
  expect_identical(
    artoo:::.dx_structure("One record per subject", NA, "DM"),
    "One record per subject"
  )
  expect_identical(
    artoo:::.dx_structure(NA, "STUDYID  USUBJID", "DM"),
    "One record per STUDYID, USUBJID"
  )
  expect_error(
    artoo:::.dx_structure(NA, NA, "DM"),
    class = "artoo_error_define"
  )
})

test_that("origin detail with no origin type is refused, not emitted untyped", {
  row <- list(
    origin = NA_character_,
    source = NA_character_,
    origin_description = "Collected on the CRF",
    origin_document_id = NA_character_,
    pages = NA_character_,
    page_type = NA_character_
  )
  expect_error(
    artoo:::.dx_origin(row, p21(), "ItemDef IT.DM.SEX"),
    class = "artoo_error_define"
  )
  expect_snapshot(
    artoo:::.dx_origin(row, p21(), "ItemDef IT.DM.SEX"),
    error = TRUE
  )
  # Nothing to say at all is not an error, it is no def:Origin.
  row$origin_description <- NA_character_
  expect_null(artoo:::.dx_origin(row, p21(), "ItemDef IT.DM.SEX"))
})

test_that("a page reference with no type gets the schema-required default", {
  ref <- artoo:::.dx_docref("LF.acrf", "11", NA_character_, p21())
  expect_identical(ref$kids[["def:PDFPageRef"]]$attrs$Type, "PhysicalRef")
  # A document with no pages carries no page reference at all.
  bare <- artoo:::.dx_docref("LF.acrf", NA, NA, p21())
  expect_null(bare$kids[["def:PDFPageRef"]])
  expect_null(artoo:::.dx_docref(NA, "11", "PhysicalRef", p21()))
})

test_that("def:Standards is 2.1-only and absent when the spec has none", {
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  expect_null(artoo:::.dx_standards(spec, p21()))
  # ...and never emitted for 2.0, whatever the spec carries.
  with_std <- read_define("define21-sdtm.xml")
  expect_null(artoo:::.dx_standards(with_std, p20()))
  expect_false(is.null(artoo:::.dx_standards(with_std, p21())))
})

test_that("a YesOnly flag is emitted only when TRUE, and reduces a vector", {
  expect_identical(artoo:::.dx_yesonly(TRUE), "Yes")
  expect_identical(artoo:::.dx_yesonly(FALSE), NA_character_)
  expect_identical(artoo:::.dx_yesonly(NA), NA_character_)
  # A repeated list-level flag: isTRUE() on a vector is FALSE whatever it
  # holds, which once silently dropped every non-standard codelist flag.
  expect_identical(artoo:::.dx_yesonly(c(TRUE, TRUE, NA)), "Yes")
  expect_identical(artoo:::.dx_yesonly(c(NA, NA)), NA_character_)
  expect_identical(artoo:::.dx_yesonly(logical(0)), NA_character_)
})

test_that("a Yes/No attribute takes its default only when unset", {
  expect_identical(artoo:::.dx_yesno(TRUE), "Yes")
  expect_identical(artoo:::.dx_yesno(FALSE), "No")
  expect_identical(artoo:::.dx_yesno(NA, default = FALSE), "No")
  expect_identical(artoo:::.dx_yesno(NA), NA_character_)
})

test_that(".dx_one takes the unique non-blank value, not the first row", {
  expect_identical(artoo:::.dx_one(c(NA, "", "Sex", "Sex")), "Sex")
  expect_identical(artoo:::.dx_one(c(NA, NA)), NA_character_)
})

test_that("a column that is absent reads as NA of the right length", {
  df <- data.frame(a = 1:3)
  expect_identical(artoo:::.dx_chr(df, "nope"), rep(NA_character_, 3L))
  expect_identical(artoo:::.dx_lgl(df, "nope"), rep(NA, 3L))
  expect_identical(artoo:::.dx_chr(NULL, "a"), character(0))
  expect_identical(artoo:::.dx_lgl(NULL, "a"), logical(0))
})

test_that("a method with no description falls back rather than emitting empty", {
  md <- data.frame(
    method_id = "MT.1",
    name = c(NA_character_),
    description = NA_character_,
    type = NA_character_,
    stringsAsFactors = FALSE
  )
  node <- artoo:::.dx_method(md, 1L, data.frame(), p21())
  expect_identical(node$attrs$Name, "MT.1")
  expect_identical(node$attrs$Type, "Computation")
  expect_identical(
    node$kids$Description$kids$TranslatedText$text,
    "MT.1"
  )
})

test_that("an emission order is used only when it is complete and unique", {
  expect_identical(
    artoo:::.dx_row_order(data.frame(order = c(3L, 1L, 2L))),
    c(2L, 3L, 1L)
  )
  # A partial order would interleave unpredictably; source order wins.
  expect_identical(
    artoo:::.dx_row_order(data.frame(order = c(1L, NA, 2L))),
    1:3
  )
  expect_identical(artoo:::.dx_row_order(data.frame(order = c(1L, 1L))), 1:2)
  expect_identical(artoo:::.dx_row_order(data.frame(x = 1:2)), 1:2)
  expect_identical(artoo:::.dx_row_order(NULL), integer(0))
})
