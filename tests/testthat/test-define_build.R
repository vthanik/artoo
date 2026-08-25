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
  # ...and a page number with NO document is refused rather than dropped: it
  # is the commonest workbook shape, and losing it left every collected
  # variable with no CRF link at all.
  expect_null(artoo:::.dx_docref(NA, NA, "PhysicalRef", p21()))
  expect_error(
    artoo:::.dx_docref(NA, "11", "PhysicalRef", p21()),
    class = "artoo_error_define"
  )
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

test_that("the origin vocabulary is translated in both directions", {
  # CDISC renamed the collection origins between the versions, so a spec read
  # from one and written as the other dies on the first collected variable
  # unless the rename is applied.
  expect_identical(artoo:::.dx_origin_type("CRF", p21()), "Collected")
  expect_identical(artoo:::.dx_origin_type("eDT", p21()), "Collected")
  expect_identical(artoo:::.dx_origin_type("Collected", p20()), "CRF")
  # Everything else is spelled the same in both.
  for (v in c("Derived", "Assigned", "Protocol", "Predecessor")) {
    expect_identical(artoo:::.dx_origin_type(v, p21()), v)
    expect_identical(artoo:::.dx_origin_type(v, p20()), v)
  }
})

test_that("a 2.1 origin with no 2.0 spelling is refused, not approximated", {
  # "Not Available" and "Other" have no 2.0 equivalent. Writing either as
  # something else would record a provenance the sponsor never claimed.
  for (v in c("Not Available", "Other")) {
    expect_error(
      artoo:::.dx_origin_type(v, p20()),
      class = "artoo_error_define"
    )
  }
  expect_snapshot(
    artoo:::.dx_origin_type("Not Available", p20()),
    error = TRUE
  )
})

test_that("def:Origin/@Source is emitted only where the version has it", {
  row <- list(
    origin = "Collected",
    source = "Investigator",
    origin_description = NA_character_,
    origin_document_id = NA_character_,
    pages = NA_character_,
    page_type = NA_character_
  )
  expect_identical(
    artoo:::.dx_origin(row, p21(), "x")$attrs$Source,
    "Investigator"
  )
  # A LOCAL attribute, so the emitter's def: guard cannot see it: the builder
  # gates it on the profile carrying no @Source vocabulary.
  expect_null(artoo:::.dx_origin(row, p20(), "x")$attrs$Source)
  expect_identical(artoo:::.dx_origin(row, p20(), "x")$attrs$Type, "CRF")
})

test_that("a MethodDef type outside Define-XML's vocabulary is refused", {
  # ODM's own schema accepts Transpose and Other; Define-XML forbids them, so
  # the schema gate cannot catch a wrong one.
  md <- data.frame(
    method_id = "MT.1",
    name = "x",
    description = "y",
    type = "Transpose",
    stringsAsFactors = FALSE
  )
  expect_error(
    artoo:::.dx_method(md, 1L, data.frame(), p21()),
    class = "artoo_error_define"
  )
  # Both versions close it to the same pair.
  expect_identical(p20()$enum$method_type, p21()$enum$method_type)
})

test_that("an EMPTY decode is a decoded term, not an absent one", {
  # <Decode><TranslatedText/></Decode> is schema-valid and means "decoded,
  # nothing to say". Treating it as absent refused a document that had
  # round-tripped before.
  cl <- data.frame(
    codelist_id = "CL.1",
    term = c("A", "B"),
    decode = c("Alpha", ""),
    name = "One",
    data_type = "text",
    stringsAsFactors = FALSE
  )
  expect_no_error(artoo:::.dx_codelist(cl, p21()))
  # A term the author left blank in an otherwise decoded list is a
  # CodeListItem with an empty Decode -- never the string "NA", and never a
  # refusal: partly-decoded lists are ordinary sponsor input.
  cl$decode <- c("Alpha", NA)
  node <- artoo:::.dx_codelist(cl, p21())
  terms <- node$kids$CodeListItem
  expect_length(terms, 2L)
  expect_identical(
    terms[[2L]]$kids$Decode$kids$TranslatedText$text,
    ""
  )
})

test_that("a duplicated coded value collapses only when its rows agree (#p12-final-2)", {
  # A sponsor sheet re-lists UNSCHEDULED under each visit block. The schema
  # allows a CodedValue once per list (UC-CL-3), so agreeing repeats keep
  # the first row, out loud; repeats that disagree are refused HERE, where
  # the codelist and values can be named, not at the schema gate, which
  # blames artoo for sponsor input.
  cl <- data.frame(
    codelist_id = "CL.AVISIT",
    term = c("Visit 1", "UNSCHEDULED", "Visit 2", "UNSCHEDULED"),
    decode = NA_character_,
    name = "Visit",
    data_type = "text",
    order = c(1L, 2L, 3L, 4L),
    stringsAsFactors = FALSE
  )
  expect_warning(
    node <- artoo:::.dx_codelist(cl, p21()),
    class = "artoo_warning_codelist"
  )
  terms <- vapply(
    node$kids$EnumeratedItem,
    function(n) n$attrs$CodedValue,
    character(1)
  )
  expect_identical(terms, c("Visit 1", "UNSCHEDULED", "Visit 2"))

  cl$decode <- c(NA, "Unscheduled visit", NA, "Extra visit")
  expect_error(
    suppressWarnings(artoo:::.dx_codelist(cl, p21())),
    class = "artoo_error_codelist"
  )
  expect_snapshot(
    suppressWarnings(artoo:::.dx_codelist(cl, p21())),
    error = TRUE
  )
})

test_that("colliding OrderNumbers are dropped rather than emitted (#p12-final-2)", {
  # UC-CL-4 keys EnumeratedItem on OrderNumber, so two terms seated at one
  # number cannot both keep it, and keeping half a numbering (or inventing
  # a new one) misstates the sheet. The attribute is optional; the terms
  # still emit in the order the sheet gave them, which is what
  # .dx_row_order() already falls back to for a collided column.
  cl <- data.frame(
    codelist_id = "CL.AVISIT",
    term = c("Visit 3", "UNSCHEDULED"),
    decode = NA_character_,
    name = "Visit",
    data_type = "text",
    order = c(3L, 3L),
    stringsAsFactors = FALSE
  )
  expect_warning(
    node <- artoo:::.dx_codelist(cl, p21()),
    class = "artoo_warning_codelist"
  )
  items <- node$kids$EnumeratedItem
  expect_identical(
    vapply(items, function(n) n$attrs$CodedValue, character(1)),
    c("Visit 3", "UNSCHEDULED")
  )
  expect_false(any(vapply(
    items,
    function(n) "OrderNumber" %in% names(n$attrs),
    logical(1)
  )))
})

test_that("a repeated definition row collapses only when identical (#p12-final-2)", {
  # Comments and methods emit one element per row, and their OIDs share the
  # document-wide UC-MDV-OID-unique constraint. A sponsor sheet stating one
  # comment twice, identically, is one definition; stating it two ways is a
  # contradiction artoo must not resolve silently.
  cm <- data.frame(
    comment_id = c("COM.1", "COM.1", "COM.2"),
    description = c("Same text", "Same text", "Other"),
    stringsAsFactors = FALSE
  )
  out <- artoo:::.dx_unique_defs(cm, "comment_id", "comment")
  expect_identical(out$comment_id, c("COM.1", "COM.2"))

  cm$description[2] <- "Different text"
  expect_error(
    artoo:::.dx_unique_defs(cm, "comment_id", "comment"),
    class = "artoo_error_define"
  )
  expect_snapshot(
    artoo:::.dx_unique_defs(cm, "comment_id", "comment"),
    error = TRUE
  )
})
