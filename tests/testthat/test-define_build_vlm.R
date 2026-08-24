# Value-level metadata, where clauses, and the pooled ItemDef frame.

p21 <- function() artoo:::.define_profile("2.1")

vlm_spec <- function(values = NULL, where_clauses = NULL, variables = NULL) {
  artoo_spec(
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per subject per test",
      stringsAsFactors = FALSE
    ),
    variables = variables %||%
      data.frame(
        dataset = "VS",
        variable = c("VSTESTCD", "VSORRES"),
        data_type = "string",
        stringsAsFactors = FALSE
      ),
    values = values,
    where_clauses = where_clauses
  )
}

test_that("two rows sharing an ItemDef OID must agree", {
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = c("DM", "SUPPDM"),
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = c("DM", "SUPPDM"),
      variable = "USUBJID",
      itemoid = "IT.SHARED",
      data_type = "string",
      # The definitions disagree: one document cannot say both.
      length = c(20L, 30L),
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = "2020-01-01 00:00:00"),
    class = "artoo_error_define"
  )
  expect_snapshot(
    write_spec(spec, path, created = "2020-01-01 00:00:00"),
    error = TRUE
  )
})

test_that("two rows sharing an ItemDef OID and agreeing emit one ItemDef", {
  skip_if_not_installed("xml2")
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = c("DM", "SUPPDM"),
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = c("DM", "SUPPDM"),
      variable = "USUBJID",
      itemoid = "IT.SHARED",
      data_type = "string",
      length = 20L,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = "2020-01-01 00:00:00")
  doc <- xml2::read_xml(path)
  expect_length(xml2::xml_find_all(doc, "//*[local-name()='ItemDef']"), 1L)
  expect_length(xml2::xml_find_all(doc, "//*[local-name()='ItemRef']"), 2L)
})

test_that("a where clause that names no resolvable variable is refused", {
  spec <- vlm_spec(
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause_id = "WC.1",
      data_type = "float",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.1",
      check_order = 1L,
      dataset = NA_character_,
      variable = NA_character_,
      comparator = "EQ",
      value = "HEIGHT",
      value_order = 1L,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = "2020-01-01 00:00:00"),
    class = "artoo_error_define"
  )
  expect_snapshot(
    write_spec(spec, path, created = "2020-01-01 00:00:00"),
    error = TRUE
  )
})

test_that("a where clause resolves its target from itemoid when it has one", {
  skip_if_not_installed("xml2")
  spec <- vlm_spec(
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause_id = "WC.1",
      data_type = "float",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.1",
      check_order = 1L,
      dataset = NA_character_,
      variable = NA_character_,
      itemoid = "IT.VS.VSTESTCD",
      comparator = "EQ",
      value = "HEIGHT",
      value_order = 1L,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = "2020-01-01 00:00:00")
  rc <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='RangeCheck']"
  )
  expect_identical(xml2::xml_attr(rc, "ItemOID"), "IT.VS.VSTESTCD")
})

test_that("the where-clause key is read from where_clause when the id is blank", {
  skip_if_not_installed("xml2")
  # The workbook readers converge on `where_clause` holding the foreign key;
  # the Define-XML reader fills `where_clause_id`. The writer accepts both,
  # but only when the value names a DEFINED clause -- rendered display text
  # must never become a dangling reference.
  spec <- vlm_spec(
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause = c("WC.1", "VSTESTCD EQ (WEIGHT)"),
      data_type = "float",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.1",
      check_order = 1L,
      dataset = "VS",
      variable = "VSTESTCD",
      comparator = "EQ",
      value = "HEIGHT",
      value_order = 1L,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = "2020-01-01 00:00:00")
  refs <- xml2::xml_find_all(
    xml2::read_xml(path),
    "//*[local-name()='ValueListDef']/*[local-name()='ItemRef']"
  )
  expect_length(refs, 2L)
  wc <- lapply(refs, function(r) {
    xml2::xml_find_first(r, "./*[local-name()='WhereClauseRef']")
  })
  expect_identical(xml2::xml_attr(wc[[1]], "WhereClauseOID"), "WC.1")
  expect_true(is.na(wc[[2]]))
})

test_that("a multi-value IN keeps every CheckValue, in value order", {
  skip_if_not_installed("xml2")
  spec <- vlm_spec(
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause_id = "WC.1",
      data_type = "float",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.1",
      check_order = 1L,
      dataset = "VS",
      variable = "VSTESTCD",
      comparator = "IN",
      # A CheckValue is free text and can contain a comma and a space.
      value = c("LOCAL LAB", "HEIGHT", "WEIGHT"),
      value_order = c(3L, 1L, 2L),
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = "2020-01-01 00:00:00")
  vals <- xml2::xml_text(xml2::xml_find_all(
    xml2::read_xml(path),
    "//*[local-name()='CheckValue']"
  ))
  expect_identical(vals, c("HEIGHT", "WEIGHT", "LOCAL LAB"))
})

test_that("an unknown SoftHard is refused and a blank one defaults to Soft", {
  skip_if_not_installed("xml2")
  make <- function(sh) {
    vlm_spec(
      values = data.frame(
        dataset = "VS",
        variable = "VSORRES",
        where_clause_id = "WC.1",
        data_type = "float",
        stringsAsFactors = FALSE
      ),
      where_clauses = data.frame(
        where_clause_id = "WC.1",
        check_order = 1L,
        dataset = "VS",
        variable = "VSTESTCD",
        comparator = "EQ",
        soft_hard = sh,
        value = "HEIGHT",
        value_order = 1L,
        stringsAsFactors = FALSE
      )
    )
  }
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(make(NA_character_), path, created = "2020-01-01 00:00:00")
  rc <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='RangeCheck']"
  )
  expect_identical(xml2::xml_attr(rc, "SoftHard"), "Soft")
  expect_error(
    write_spec(make("Squishy"), path, created = "2020-01-01 00:00:00"),
    class = "artoo_error_define"
  )
})

test_that("a spec with no value-level metadata emits no value list", {
  expect_identical(artoo:::.dx_value_lists(vlm_spec(), list(), p21()), list())
  expect_identical(
    artoo:::.dx_where_clause_defs(vlm_spec(), list(), p21()),
    list()
  )
})

test_that("an orphan where clause is still written, since it is still a definition", {
  skip_if_not_installed("xml2")
  # A def:WhereClauseDef nothing references is schema-valid, and dropping it
  # would lose a definition the spec carries. define_lint() reports it.
  spec <- vlm_spec(
    where_clauses = data.frame(
      where_clause_id = "WC.ORPHAN",
      check_order = 1L,
      dataset = "VS",
      variable = "VSTESTCD",
      comparator = "EQ",
      value = "HEIGHT",
      value_order = 1L,
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  write_spec(spec, path, created = "2020-01-01 00:00:00")
  expect_length(
    xml2::xml_find_all(
      xml2::read_xml(path),
      "//*[local-name()='WhereClauseDef']"
    ),
    1L
  )
  expect_true(any(
    define_lint(path)@findings$check == "define_orphan_where_clause"
  ))
})
