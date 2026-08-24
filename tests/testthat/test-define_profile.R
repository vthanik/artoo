# The version profiles: how a target version is chosen, and how a closed
# vocabulary is enforced.

test_that("an explicit version wins over the spec's own", {
  spec <- read_define("define20-sdtm.xml")
  expect_identical(artoo:::.dx_target_version("2.1", spec), "2.1")
})

test_that("the spec's define_version picks the target when none is given", {
  v20 <- read_define("define20-sdtm.xml")
  v21 <- read_define("define21-sdtm.xml")
  expect_identical(artoo:::.dx_target_version(NULL, v20), "2.0")
  expect_identical(artoo:::.dx_target_version(NULL, v21), "2.1")
})

test_that("a spec that names no version targets 2.1", {
  spec <- artoo_spec(
    datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  expect_identical(artoo:::.dx_target_version(NULL, spec), "2.1")
  # ...and so does one whose define_version is blank rather than absent.
  blank <- artoo_spec(
    study = data.frame(
      define_version = NA_character_,
      stringsAsFactors = FALSE
    ),
    datasets = data.frame(dataset = "DM", stringsAsFactors = FALSE),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  expect_identical(artoo:::.dx_target_version(NULL, blank), "2.1")
})

test_that("an unknown version is refused by name", {
  expect_error(artoo:::.define_profile("1.0"), class = "artoo_error_input")
  expect_error(
    artoo:::.define_profile(c("2.0", "2.1")),
    class = "artoo_error_input"
  )
  expect_snapshot(artoo:::.define_profile("1.0"), error = TRUE)
})

test_that("a value outside a closed vocabulary is refused", {
  p <- artoo:::.define_profile("2.1")
  expect_error(
    artoo:::.dx_enum("Sideways", p$enum$origin_type, "def:Origin Type"),
    class = "artoo_error_define"
  )
  expect_snapshot(
    artoo:::.dx_enum("Sideways", p$enum$origin_type, "def:Origin Type"),
    error = TRUE
  )
})

test_that("a version that does not constrain a value lets it through", {
  p20 <- artoo:::.define_profile("2.0")
  # def:Class is odm:text in 2.0, so the profile carries no vocabulary.
  expect_null(p20$enum$class)
  expect_identical(
    artoo:::.dx_enum("ANYTHING AT ALL", p20$enum$class, "def:Class Name"),
    "ANYTHING AT ALL"
  )
  # NA and empty pass through whatever the vocabulary says.
  p21 <- artoo:::.define_profile("2.1")
  expect_identical(
    artoo:::.dx_enum(NA_character_, p21$enum$origin_type, "x"),
    NA_character_
  )
  expect_identical(artoo:::.dx_enum("", p21$enum$origin_type, "x"), "")
})

test_that("the two profiles differ where the standards differ, and nowhere else", {
  p20 <- artoo:::.define_profile("2.0")
  p21 <- artoo:::.define_profile("2.1")
  expect_identical(p20$class_slot, "attribute")
  expect_identical(p21$class_slot, "element")
  expect_null(p20$order[["def:Standards"]])
  expect_identical(p21$order[["def:Standards"]], "def:Standard")
  expect_null(p20$enum$context)
  expect_null(p20$enum$origin_source)
  # The ODM half is shared, so both must agree on it.
  expect_identical(p20$order$ItemDef, p21$order$ItemDef)
  expect_identical(p20$ns[["odm"]], p21$ns[["odm"]])
})
