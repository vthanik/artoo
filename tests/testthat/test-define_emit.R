# The emitter's two guards and its one guarantee.
#
# The guarantee is why the emitter exists: a builder never chooses element
# order, so assigning children in any order produces identical bytes. The
# prior art emitted def:Class before ItemRef, which is invalid, and shipped
# it through 116 tests because the order lived in a function's statement
# sequence where nothing could check it.

p21 <- function() artoo:::.define_profile("2.1")

emit_to_text <- function(node) {
  doc <- xml2::xml_new_root(
    "ODM",
    "xmlns" = "http://www.cdisc.org/ns/odm/v1.3",
    "xmlns:def" = "http://www.cdisc.org/ns/def/v2.1"
  )
  artoo:::.dx_emit(doc, node, p21())
  as.character(doc)
}

test_that("child order comes from the profile, not from the builder", {
  skip_if_not_installed("xml2")
  kids <- list(
    Description = artoo:::.dx_desc("Demographics"),
    ItemRef = artoo:::.dx_node("ItemRef", attrs = list(ItemOID = "IT.1")),
    `def:leaf` = artoo:::.dx_node("def:leaf", attrs = list(ID = "LF.1")),
    `def:Class` = artoo:::.dx_node("def:Class", attrs = list(Name = "EVENTS"))
  )
  forward <- artoo:::.dx_node("ItemGroupDef", kids = kids)
  backward <- artoo:::.dx_node("ItemGroupDef", kids = rev(kids))
  expect_identical(emit_to_text(forward), emit_to_text(backward))
  # ...and the order is the schema's, not either assignment's.
  txt <- emit_to_text(forward)
  expect_lt(regexpr("<ItemRef", txt), regexpr("def:Class", txt))
  expect_lt(regexpr("def:Class", txt), regexpr("def:leaf", txt))
})

test_that("an element with no declared order is refused", {
  skip_if_not_installed("xml2")
  node <- artoo:::.dx_node(
    "MadeUpElement",
    kids = list(Description = artoo:::.dx_desc("x"))
  )
  expect_error(emit_to_text(node), class = "artoo_error_define")
  expect_snapshot(emit_to_text(node), error = TRUE)
})

test_that("a child the version's sequence does not allow is refused", {
  skip_if_not_installed("xml2")
  # def:Standards exists in 2.1 but not in 2.0, so a 2.1-only child cannot
  # leak into a 2.0 document even if a builder assigns it.
  node <- artoo:::.dx_node(
    "ItemGroupDef",
    kids = list(`def:Standards` = artoo:::.dx_node("def:Standards"))
  )
  expect_error(emit_to_text(node), class = "artoo_error_define")
  expect_snapshot(emit_to_text(node), error = TRUE)
})

test_that(".dx_attrs drops NA and empty values but keeps a literal zero", {
  expect_identical(
    artoo:::.dx_attrs(a = "x", b = NA_character_, c = "", d = 0L),
    list(a = "x", d = "0")
  )
})

test_that(".dx_desc returns NULL for nothing to say", {
  expect_null(artoo:::.dx_desc(NA_character_))
  expect_null(artoo:::.dx_desc(""))
  expect_null(artoo:::.dx_desc(NULL))
})

test_that("serialising without an XML declaration is refused", {
  skip_if_not_installed("xml2")
  doc <- xml2::xml_new_root("ODM")
  # A NODE, not a document: as.character() gives no <?xml ...?> to splice
  # the stylesheet reference after.
  node <- xml2::xml_add_child(doc, "Study")
  expect_error(
    artoo:::.dx_serialise(node, "define2-1.xsl"),
    class = "artoo_error_define"
  )
  expect_snapshot(
    artoo:::.dx_serialise(node, "define2-1.xsl"),
    error = TRUE
  )
  # NULL href short-circuits before the check.
  expect_false(grepl("xml-stylesheet", artoo:::.dx_serialise(node, NULL)))
})
