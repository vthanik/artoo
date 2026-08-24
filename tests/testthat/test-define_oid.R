# The OID symbol table.
#
# Two properties carry the whole design: a supplied OID survives verbatim
# (an external reference into the document keeps working), and a minted one
# is derived from content rather than position (it survives filtering).

mini_spec <- function(...) {
  artoo_spec(
    datasets = data.frame(
      dataset = "DM",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = c("USUBJID", "AGE"),
      data_type = c("string", "integer"),
      stringsAsFactors = FALSE
    ),
    ...
  )
}

test_that("a minted OID is readable and derived from the name", {
  oids <- artoo:::.dx_oids(mini_spec())
  expect_identical(unname(oids$dataset[["DM"]]), "IG.DM")
  expect_identical(
    unname(artoo:::.dx_get(oids$variable, artoo:::.dx_key("DM", "USUBJID"))),
    "IT.DM.USUBJID"
  )
})

test_that("a supplied OID wins verbatim", {
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "DM",
      itemgroupoid = "SPONSOR.DM.001",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "DM",
      variable = "USUBJID",
      itemoid = "SPONSOR.DM.USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  oids <- artoo:::.dx_oids(spec)
  expect_identical(unname(oids$dataset[["DM"]]), "SPONSOR.DM.001")
  expect_identical(
    unname(artoo:::.dx_get(oids$variable, artoo:::.dx_key("DM", "USUBJID"))),
    "SPONSOR.DM.USUBJID"
  )
})

test_that("value-level OIDs are numbered per parent variable, not globally", {
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = c("VSORRES", "VSORRESU"),
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = c("VSORRES", "VSORRESU", "VSORRES"),
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  oids <- artoo:::.dx_oids(spec)
  expect_identical(
    oids$value_item,
    c("IT.VS.VSORRES.1", "IT.VS.VSORRESU.1", "IT.VS.VSORRES.2")
  )
  # The value list is keyed by the PARENT ItemDef OID, because Define-XML
  # hangs def:ValueListRef off the ItemDef and two datasets may share one.
  expect_identical(
    unname(artoo:::.dx_get(oids$value_list, "IT.VS.VSORRES")),
    "VL.VS.VSORRES"
  )
})

test_that("datasets sharing an ItemDef share its value list", {
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = c("QSCG", "QSCS"),
      structure = "One record per question",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = c("QSCG", "QSCS"),
      variable = "QSORRES",
      itemoid = "IT.QS.QSORRES",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = c("QSCG", "QSCS"),
      variable = "QSORRES",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  oids <- artoo:::.dx_oids(spec)
  expect_identical(unname(oids$value_list), "VL.QS.QSORRES")
  expect_identical(
    oids$value_item,
    c("IT.QS.QSORRES.1", "IT.QS.QSORRES.2")
  )
})

test_that("a value-level row with no parent variable is refused", {
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "NOSUCHVAR",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  expect_error(artoo:::.dx_oids(spec), class = "artoo_error_define")
  expect_snapshot(artoo:::.dx_oids(spec), error = TRUE)
})

test_that("the value list OID comes from the parent variable when it has one", {
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      value_list_id = "SPONSOR.VL.1",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "float",
      stringsAsFactors = FALSE
    )
  )
  oids <- artoo:::.dx_oids(spec)
  expect_identical(
    unname(artoo:::.dx_get(oids$value_list, "IT.VS.VSORRES")),
    "SPONSOR.VL.1"
  )
})

test_that(".dx_get never throws on a name that is not there", {
  # `[[` would raise "subscript out of bounds"; these keys come from user data.
  map <- c(a = "1", b = "2")
  expect_identical(artoo:::.dx_get(map, "zzz"), NA_character_)
  expect_identical(artoo:::.dx_get(map, character(0)), character(0))
  expect_identical(artoo:::.dx_get(character(0), "a"), NA_character_)
  expect_identical(artoo:::.dx_get(map, c("b", NA)), c("2", NA))
})

test_that(".dx_fill takes the minted value only where none is supplied", {
  expect_identical(
    artoo:::.dx_fill(c("A", NA, "  "), c("x", "y", "z")),
    c("A", "y", "z")
  )
  expect_identical(artoo:::.dx_fill(character(0), character(0)), character(0))
})

test_that(".dx_slug keeps an OID free of characters that break parsers", {
  expect_identical(artoo:::.dx_slug("A B/C"), "A_B_C")
  expect_identical(artoo:::.dx_slug(NA), "")
  expect_identical(artoo:::.dx_slug("ADSL.1-x_y"), "ADSL.1-x_y")
})

test_that("the study and MetaDataVersion OIDs follow the study name", {
  spec <- mini_spec(
    study = data.frame(study_name = "ARTOO 01", stringsAsFactors = FALSE)
  )
  oids <- artoo:::.dx_oids(spec)
  expect_identical(oids$study, "STDY.ARTOO_01")
  expect_identical(oids$mdv, "MDV.ARTOO_01")
})

test_that("a spec with no study name still gets stable identifiers", {
  oids <- artoo:::.dx_oids(mini_spec())
  expect_identical(oids$study, "STDY.1")
  expect_identical(oids$mdv, "MDV.1")
})

test_that("a supplied metadata_version_oid wins", {
  spec <- mini_spec(
    study = data.frame(
      study_name = "ARTOO01",
      metadata_version_oid = "MDV.SPONSOR.7",
      stringsAsFactors = FALSE
    )
  )
  expect_identical(artoo:::.dx_oids(spec)$mdv, "MDV.SPONSOR.7")
})

test_that(".dx_map de-duplicates repeated keys, first occurrence winning", {
  expect_identical(
    artoo:::.dx_map(c("a", "a", "b"), c("1", "2", "3")),
    c(a = "1", b = "3")
  )
})
