# Letting the data the define describes inform what it says.
#
# artoo can read the files a define.xml describes, which a spec-only tool
# cannot. The rule that keeps that honest is in the source header and every
# test here checks one half of it: the data may correct the spec where the
# spec would produce a wrong document, and may fill what the spec leaves
# blank, but it never overwrites an author's assertion silently.

FROZEN_DATA <- "2020-01-01 00:00:00"

data_spec <- function(...) {
  artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "VS",
      label = "Vital Signs",
      class = "FINDINGS",
      domain = "VS",
      purpose = "Tabulation",
      repeating = TRUE,
      structure = "One record per subject per test",
      stringsAsFactors = FALSE
    ),
    ...
  )
}

vs_data <- function() {
  data.frame(
    USUBJID = c("01-001", "01-001", "01-002", "01-002"),
    VSTESTCD = c("HEIGHT", "WEIGHT", "HEIGHT", "WEIGHT"),
    VSORRES = c("162.6", "78.5", "170.0", "91.2"),
    VSORRESU = c("cm", "kg", "cm", "kg"),
    stringsAsFactors = FALSE
  )
}

test_that("a blank length is filled from the real maximum byte width", {
  skip_if_not_installed("xml2")
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("USUBJID", "VSTESTCD", "VSORRES", "VSORRESU"),
      label = "x",
      data_type = "string",
      length = NA_integer_,
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = vs_data()))
  ))
  items <- xml2::xml_find_all(
    xml2::read_xml(path),
    "//*[local-name()='ItemDef']"
  )
  widths <- stats::setNames(
    as.integer(xml2::xml_attr(items, "Length")),
    xml2::xml_attr(items, "Name")
  )
  # "01-001" is six bytes, "HEIGHT" six, "162.6" five, "cm" two.
  expect_identical(widths[["USUBJID"]], 6L)
  expect_identical(widths[["VSTESTCD"]], 6L)
  expect_identical(widths[["VSORRES"]], 5L)
  expect_identical(widths[["VSORRESU"]], 2L)
})

test_that("a length shorter than the data is widened, and said so", {
  skip_if_not_installed("xml2")
  # A Length below the real maximum is a conformance finding, so the document
  # would be wrong. The data wins, and the write names the variable.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("VSTESTCD", "VSORRES"),
      label = "x",
      data_type = "string",
      length = c(4L, 5L),
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_warning(
    suppressMessages(
      write_spec(spec, path, created = FROZEN_DATA, data = list(VS = vs_data()))
    ),
    class = "artoo_warning_spec"
  )
  item <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='ItemDef'][@Name='VSTESTCD']"
  )
  expect_identical(xml2::xml_attr(item, "Length"), "6")
})

test_that("a length longer than the data is left exactly as declared", {
  skip_if_not_installed("xml2")
  # A length is a claim about the domain, not about one extract. Narrowing it
  # would let a snapshot of data overwrite the author.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      label = "x",
      data_type = "string",
      length = 200L,
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = vs_data()))
  ))
  item <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='ItemDef'][@Name='VSORRES']"
  )
  expect_identical(xml2::xml_attr(item, "Length"), "200")
  # ...and it is reported, so the discrepancy is not invisible.
  expect_message(
    suppressWarnings(
      write_spec(spec, path, created = FROZEN_DATA, data = list(VS = vs_data()))
    ),
    class = "artoo_message_spec"
  )
})

test_that("derived value-level metadata has zero dangling references", {
  skip_if_not_installed("xml2")
  # The check the prior art's equivalent would have failed: every derived
  # def:ValueListDef, def:WhereClauseDef and value-level ItemDef has to
  # resolve, or the document is worse than one with no VLM at all.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("USUBJID", "VSTESTCD", "VSORRES", "VSORRESU"),
      label = "x",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = vs_data()))
  ))
  expect_true(validate_define(path)@summary$valid)
  expect_false(any(grepl("dangling", lint_define(path)@findings$check)))

  doc <- xml2::read_xml(path)
  # One value list per result variable, one entry per test code present.
  expect_length(xml2::xml_find_all(doc, "//*[local-name()='ValueListDef']"), 2L)
  refs <- xml2::xml_find_all(
    doc,
    "//*[local-name()='ValueListDef']/*[local-name()='ItemRef']"
  )
  expect_length(refs, 4L)
  clauses <- xml2::xml_find_all(doc, "//*[local-name()='WhereClauseDef']")
  expect_length(clauses, 4L)
  # ...and each condition names the key variable, not the result.
  checks <- xml2::xml_find_all(doc, "//*[local-name()='RangeCheck']")
  expect_identical(
    unique(xml2::xml_attr(checks, "ItemOID")),
    "IT.VS.VSTESTCD"
  )
  expect_setequal(
    xml2::xml_text(xml2::xml_find_all(doc, "//*[local-name()='CheckValue']")),
    c("HEIGHT", "WEIGHT")
  )
})

test_that("a derived value-level row carries the type and width of its subset", {
  skip_if_not_installed("xml2")
  # The point of deriving from data rather than defaulting: HEIGHT's unit is
  # two bytes and WEIGHT's is two, but their results differ in width, and a
  # numeric-looking result is a number.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("VSTESTCD", "VSORRES"),
      label = "x",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
  frame <- data.frame(
    VSTESTCD = c("HEIGHT", "PULSE", "PULSE"),
    VSORRES = c("162.6", "72", "68"),
    stringsAsFactors = FALSE
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = frame))
  ))
  doc <- xml2::read_xml(path)
  items <- xml2::xml_find_all(
    doc,
    "//*[local-name()='ItemDef'][starts-with(@OID, 'IT.VS.VSORRES.')]"
  )
  types <- stats::setNames(
    xml2::xml_attr(items, "DataType"),
    xml2::xml_attr(items, "OID")
  )
  lengths <- stats::setNames(
    xml2::xml_attr(items, "Length"),
    xml2::xml_attr(items, "OID")
  )
  expect_identical(unname(types[grepl("HEIGHT", names(types))]), "float")
  expect_identical(unname(types[grepl("PULSE", names(types))]), "integer")
  expect_identical(unname(lengths[grepl("HEIGHT", names(lengths))]), "5")
  expect_identical(unname(lengths[grepl("PULSE", names(lengths))]), "2")
})

test_that("value-level rows the author wrote are never overwritten", {
  skip_if_not_installed("xml2")
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("VSTESTCD", "VSORRES"),
      label = "x",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause_id = "WC.MINE",
      label = "The author's own row",
      data_type = "text",
      length = 40L,
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.MINE",
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
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = vs_data()))
  ))
  doc <- xml2::read_xml(path)
  clauses <- xml2::xml_attr(
    xml2::xml_find_all(doc, "//*[local-name()='WhereClauseDef']"),
    "OID"
  )
  # The author's clause, and nothing derived for the variable it covers.
  expect_identical(clauses, "WC.MINE")
})

test_that("too many distinct key values stops rather than guessing", {
  skip_if_not_installed("xml2")
  # A findings domain with hundreds of test codes would otherwise produce
  # hundreds of value lists nobody asked for.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("VSTESTCD", "VSORRES"),
      label = "x",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
  n <- artoo:::.dx_vlm_limit + 1L
  frame <- data.frame(
    VSTESTCD = sprintf("T%04d", seq_len(n)),
    VSORRES = as.character(seq_len(n)),
    stringsAsFactors = FALSE
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_warning(
    suppressMessages(
      write_spec(spec, path, created = FROZEN_DATA, data = list(VS = frame))
    ),
    "distinct values"
  )
  expect_length(
    xml2::xml_find_all(
      xml2::read_xml(path),
      "//*[local-name()='ValueListDef']"
    ),
    0L
  )
})

test_that("an empty dataset is flagged only when it explains itself", {
  skip_if_not_installed("xml2")
  # def:HasNoData needs a def:CommentOID (Pinnacle 21 the empty-dataset comment rule): a dataset that
  # is empty needs an explanation, and artoo will not write one.
  build <- function(comment_id) {
    artoo_spec(
      standard = "SDTMIG 3.4",
      datasets = data.frame(
        dataset = "VS",
        label = "Vital Signs",
        class = "FINDINGS",
        domain = "VS",
        purpose = "Tabulation",
        repeating = TRUE,
        structure = "One record per subject per test",
        comment_id = comment_id,
        stringsAsFactors = FALSE
      ),
      variables = data.frame(
        dataset = "VS",
        variable = "USUBJID",
        label = "x",
        data_type = "string",
        length = 20L,
        origin = "Collected",
        stringsAsFactors = FALSE
      ),
      comments = if (is.na(comment_id)) {
        NULL
      } else {
        data.frame(
          comment_id = comment_id,
          description = "No vital signs were collected in this study.",
          stringsAsFactors = FALSE
        )
      }
    )
  }
  empty <- list(VS = vs_data()[0, , drop = FALSE])

  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(build("COM.EMPTY"), path, created = FROZEN_DATA, data = empty)
  ))
  group <- xml2::xml_find_first(
    xml2::read_xml(path),
    "//*[local-name()='ItemGroupDef']"
  )
  expect_identical(xml2::xml_attr(group, "HasNoData"), "Yes")
  expect_identical(xml2::xml_attr(group, "CommentOID"), "COM.EMPTY")

  # Without a comment: not flagged, and the reason is named.
  bare <- file.path(withr::local_tempdir(), "bare.xml")
  expect_warning(
    suppressMessages(
      write_spec(
        build(NA_character_),
        bare,
        created = FROZEN_DATA,
        data = empty
      )
    ),
    "no records and no comment"
  )
  expect_true(is.na(xml2::xml_attr(
    xml2::xml_find_first(
      xml2::read_xml(bare),
      "//*[local-name()='ItemGroupDef']"
    ),
    "HasNoData"
  )))
})

test_that("Define-XML 2.0 never gets def:HasNoData, however empty the data", {
  skip_if_not_installed("xml2")
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = "USUBJID",
      label = "x",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "COM.EMPTY",
      description = "Nothing was collected.",
      stringsAsFactors = FALSE
    )
  )
  spec@datasets$comment_id <- "COM.EMPTY"
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(
      spec,
      path,
      version = "2.0",
      created = FROZEN_DATA,
      data = list(VS = vs_data()[0, , drop = FALSE])
    )
  ))
  expect_true(validate_define(path)@summary$valid)
  expect_length(
    xml2::xml_find_all(
      xml2::read_xml(path),
      "//*[local-name()='ItemGroupDef'][@HasNoData]"
    ),
    0L
  )
})

test_that("the data argument is checked before anything is built", {
  skip_if_not_installed("xml2")
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = "USUBJID",
      label = "x",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    write_spec(spec, path, created = FROZEN_DATA, data = list(vs_data())),
    class = "artoo_error_input"
  )
  expect_snapshot(
    write_spec(spec, path, created = FROZEN_DATA, data = list(vs_data())),
    error = TRUE
  )
  expect_error(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = 1:3)),
    class = "artoo_error_input"
  )
  # A dataset the spec does not describe is a warning, not a refusal: a study
  # directory holds more than a partial spec covers.
  expect_warning(
    suppressMessages(
      write_spec(
        spec,
        path,
        created = FROZEN_DATA,
        data = list(VS = vs_data(), AE = vs_data())
      )
    ),
    "not in the spec"
  )
  expect_false(file.exists(file.path(dirname(path), "AE.xml")))
})

test_that("the whole demo study writes with zero dangling references", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("readxl")
  # The end-to-end shape this exists for: a real workbook, the real data it
  # describes, and a document that resolves.
  book <- system.file("extdata", "sdtm-spec.xlsx", package = "artoo")
  skip_if(!nzchar(book), "workbook not bundled")
  spec <- suppressWarnings(read_spec(book))
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(
      spec,
      path,
      created = FROZEN_DATA,
      data = list(
        TS = cdisc_ts,
        DM = cdisc_dm,
        VS = cdisc_vs,
        SUPPDM = cdisc_suppdm
      )
    )
  ))
  expect_true(validate_define(path)@summary$valid)
  expect_false(any(grepl("dangling", lint_define(path)@findings$check)))
  # VSSTRESU has no author rows, so it gains one per test code in the data.
  derived <- xml2::xml_find_all(
    xml2::read_xml(path),
    "//*[local-name()='WhereClauseDef'][starts-with(@OID, 'WC.VS.VSSTRESU.')]"
  )
  expect_gt(length(derived), 0L)
})

test_that(".dx_vlm_pairs finds a key by its suffix, not by a table of domains", {
  # LB, VS and a sponsor's own findings domain all pair without being named.
  pairs <- artoo:::.dx_vlm_pairs(c("LBTESTCD", "LBORRES", "LBSTRESC", "LBSEQ"))
  expect_setequal(
    vapply(pairs, function(p) unname(p[["value"]]), character(1)),
    c("LBORRES", "LBSTRESC")
  )
  expect_setequal(
    vapply(pairs, function(p) unname(p[["key"]]), character(1)),
    "LBTESTCD"
  )
  # The exact rules pair a key with values that share no stem.
  expect_setequal(
    vapply(
      artoo:::.dx_vlm_pairs(c("PARAMCD", "AVAL", "AVALC", "USUBJID")),
      function(p) unname(p[["value"]]),
      character(1)
    ),
    c("AVAL", "AVALC")
  )
  expect_identical(artoo:::.dx_vlm_pairs(c("USUBJID", "AGE")), list())
})

test_that("a blank value-level type is filled from the rows its clause selects", {
  skip_if_not_installed("xml2")
  # The only live direction of the type backfill: artoo_spec() already
  # refuses a blank variable-level type, so a value-level row is the one
  # place the data can supply one.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("VSTESTCD", "VSORRES"),
      label = "x",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      where_clause_id = c("WC.HEIGHT", "WC.PULSE"),
      data_type = NA_character_,
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = c("WC.HEIGHT", "WC.PULSE"),
      check_order = 1L,
      dataset = "VS",
      variable = "VSTESTCD",
      comparator = "EQ",
      value = c("HEIGHT", "PULSE"),
      value_order = 1L,
      stringsAsFactors = FALSE
    )
  )
  frame <- data.frame(
    VSTESTCD = c("HEIGHT", "PULSE", "PULSE"),
    VSORRES = c("162.6", "72", "68"),
    stringsAsFactors = FALSE
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = frame))
  ))
  items <- xml2::xml_find_all(
    xml2::read_xml(path),
    "//*[local-name()='ItemDef'][starts-with(@OID, 'IT.VS.VSORRES.')]"
  )
  types <- stats::setNames(
    xml2::xml_attr(items, "DataType"),
    xml2::xml_attr(items, "OID")
  )
  expect_identical(unname(types[grepl("HEIGHT", names(types))]), "float")
  expect_identical(unname(types[grepl("PULSE", names(types))]), "integer")
})

test_that("a condition artoo cannot evaluate leaves the type alone", {
  # Guessing which rows a compound or non-equality condition covers is how a
  # derived type ends up describing the wrong values.
  frame <- data.frame(
    VSTESTCD = c("HEIGHT", "PULSE"),
    VSORRES = c("162.6", "72"),
    stringsAsFactors = FALSE
  )
  clauses <- data.frame(
    where_clause_id = c("WC.IN", "WC.AND", "WC.AND", "WC.NOKEY"),
    check_order = c(1L, 1L, 2L, 1L),
    dataset = "VS",
    variable = c("VSTESTCD", "VSTESTCD", "VSPOS", "NOSUCH"),
    comparator = c("IN", "EQ", "EQ", "EQ"),
    value = c("HEIGHT", "HEIGHT", "SITTING", "X"),
    value_order = 1L,
    stringsAsFactors = FALSE
  )
  # A set comparator, a two-condition clause, and a key the data lacks.
  expect_null(artoo:::.dx_data_subset(frame, clauses, "WC.IN"))
  expect_null(artoo:::.dx_data_subset(frame, clauses, "WC.AND"))
  expect_null(artoo:::.dx_data_subset(frame, clauses, "WC.NOKEY"))
  expect_null(artoo:::.dx_data_subset(frame, clauses, NA_character_))
  expect_null(artoo:::.dx_data_subset(frame, clauses[0, ], "WC.IN"))
  # ...and the one shape it can evaluate.
  expect_identical(
    artoo:::.dx_data_subset(
      frame,
      clauses[clauses$where_clause_id == "WC.AND", ][1, ],
      "WC.AND"
    ),
    1L
  )
})

test_that(".dx_infer_type reads a column the way CDISC types it", {
  expect_identical(artoo:::.dx_infer_type(c(1L, 2L, NA)), "integer")
  expect_identical(artoo:::.dx_infer_type(c(1.5, 2)), "float")
  expect_identical(artoo:::.dx_infer_type(c("1", "2")), "integer")
  expect_identical(artoo:::.dx_infer_type(c("1.5", "2")), "float")
  expect_identical(artoo:::.dx_infer_type(c("HEIGHT", "1")), "text")
  expect_identical(artoo:::.dx_infer_type(c(NA, NA)), NA_character_)
})

test_that("data with no bearing on the spec changes nothing", {
  # A dataset the spec does not name, a column the spec does not name, and a
  # non-character column all leave the spec exactly as it was.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = "VSSEQ",
      label = "x",
      data_type = "integer",
      length = 8L,
      origin = "Derived",
      stringsAsFactors = FALSE
    )
  )
  frame <- data.frame(VSSEQ = 1:3, OTHER = c("a", "bb", "ccc"))
  expect_identical(
    artoo:::.dx_apply_data(
      spec,
      list(VS = frame),
      artoo:::.define_profile("2.1")
    ),
    spec
  )
  # NULL data is a no-op, and a bare data frame is accepted as one dataset.
  expect_identical(
    artoo:::.dx_apply_data(spec, NULL, artoo:::.define_profile("2.1")),
    spec
  )
})

test_that(".dx_data_width counts bytes, and only for text", {
  expect_identical(artoo:::.dx_data_width(c("ab", "abcd")), 4L)
  # A multi-byte character counts its bytes: a Length is a byte width, and
  # counting characters would declare a truncating length.
  expect_identical(artoo:::.dx_data_width("é"), 2L)
  expect_identical(artoo:::.dx_data_width(1:3), NA_integer_)
  expect_identical(artoo:::.dx_data_width(c(NA_character_)), NA_integer_)
  expect_identical(artoo:::.dx_data_width(factor(c("a", "bbb"))), 3L)
})

test_that("no Length is filled on a date or time typed item (#p10-review)", {
  skip_if_not_installed("xml2")
  # A Define-XML Length applies to text, integer and float. The official
  # examples carry none on a date-typed item, and P21 flags one.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("VSDTC", "VSORRES"),
      label = "x",
      data_type = c("datetime", "string"),
      length = NA_integer_,
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
  frame <- data.frame(
    VSDTC = c("2020-01-01T09:00", "2020-01-02T10:30"),
    VSORRES = c("162.6", "170.0"),
    stringsAsFactors = FALSE
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = frame))
  ))
  items <- xml2::xml_find_all(
    xml2::read_xml(path),
    "//*[local-name()='ItemDef']"
  )
  lengths <- stats::setNames(
    xml2::xml_attr(items, "Length"),
    xml2::xml_attr(items, "Name")
  )
  expect_true(is.na(lengths[["VSDTC"]]))
  expect_identical(lengths[["VSORRES"]], "5")
})

test_that("data that contradicts def:HasNoData is reported (#p10-review)", {
  skip_if_not_installed("xml2")
  # The pass's contract is that it never contradicts the spec silently, and a
  # conformance run cross-checks the flag against the actual dataset.
  spec <- artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = "VS",
      structure = "One record per test",
      has_no_data = TRUE,
      comment_id = "COM.EMPTY",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "COM.EMPTY",
      description = "Nothing was collected.",
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_warning(
    suppressMessages(
      write_spec(spec, path, created = FROZEN_DATA, data = list(VS = vs_data()))
    ),
    "the data has rows"
  )
  # The flag is left as the spec set it; artoo reports rather than decides.
  expect_identical(
    xml2::xml_attr(
      xml2::xml_find_first(
        xml2::read_xml(path),
        "//*[local-name()='ItemGroupDef']"
      ),
      "HasNoData"
    ),
    "Yes"
  )
})

test_that("derived rows stack onto a spec carrying a foreign column (#p10-review)", {
  skip_if_not_installed("xml2")
  # The constructor deliberately preserves columns artoo does not model, and
  # indexing the derived rows by the existing names failed with a bare
  # "undefined columns selected" in the middle of a write.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = c("VSTESTCD", "VSORRES", "VSORRESU"),
      label = "x",
      data_type = "string",
      length = 20L,
      origin = "Collected",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = "VS",
      variable = "VSORRESU",
      where_clause_id = "WC.MINE",
      data_type = "text",
      reviewer_note = "checked 2026-08",
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = "WC.MINE",
      check_order = 1L,
      dataset = "VS",
      variable = "VSTESTCD",
      comparator = "EQ",
      value = "HEIGHT",
      value_order = 1L,
      stringsAsFactors = FALSE
    )
  )
  expect_true("reviewer_note" %in% names(spec@values))
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_no_error(suppressMessages(suppressWarnings(
    write_spec(spec, path, created = FROZEN_DATA, data = list(VS = vs_data()))
  )))
  expect_true(validate_define(path)@summary$valid)
  # The author's row survives alongside the derived ones.
  expect_gt(
    length(xml2::xml_find_all(
      xml2::read_xml(path),
      "//*[local-name()='WhereClauseDef']"
    )),
    1L
  )
})

test_that("a widened length carries across a shared ItemDef OID (#p12-review-B1)", {
  skip_if_not_installed("xml2")
  # Define-XML allows one ItemDef per OID, and the bundled SDTM spec gives
  # STUDYID a single IT.STUDYID across four datasets. Widening is measured
  # per dataset, so supplying data for some of them -- the natural call, you
  # pass what is on disk -- left one OID defined two ways and aborted,
  # blaming the author for a state the write had just created.
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_no_error(suppressMessages(suppressWarnings(
    write_spec(
      sdtm_spec,
      path,
      created = FROZEN_DATA,
      data = list(VS = cdisc_vs, DM = cdisc_dm)
    )
  )))
  expect_true(validate_define(path)@summary$valid)
  # One definition, and it is the widest measurement, not the last one seen.
  studyid <- xml2::xml_find_all(
    xml2::read_xml(path),
    "//*[local-name()='ItemDef'][@OID='IT.STUDYID']"
  )
  expect_length(studyid, 1L)
  expect_identical(
    xml2::xml_attr(studyid, "Length"),
    as.character(max(nchar(c(cdisc_vs$STUDYID, cdisc_dm$STUDYID))))
  )
})

test_that("a pre-existing shared-OID conflict still aborts (#p12-review-B1)", {
  skip_if_not_installed("xml2")
  # Pooling only groups the data pass touched: two rows that disagreed before
  # any data arrived are the author's conflict, and keep their own message.
  spec <- artoo_spec(
    data.frame(dataset = c("DM", "VS"), stringsAsFactors = FALSE),
    data.frame(
      dataset = c("DM", "VS"),
      variable = "STUDYID",
      itemoid = "IT.STUDYID",
      data_type = "string",
      length = c(8L, 12L),
      stringsAsFactors = FALSE
    )
  )
  path <- file.path(withr::local_tempdir(), "d.xml")
  expect_error(
    suppressMessages(suppressWarnings(
      write_spec(spec, path, created = FROZEN_DATA, data = list(VS = cdisc_vs))
    )),
    class = "artoo_error_define"
  )
})

test_that("a bare data frame is refused by what it is, not by its columns", {
  # A data frame IS a named list, so it reached the per-element check and was
  # refused for a COLUMN not being a data frame -- the message named "A" and
  # left the reader hunting a dataset by that name.
  expect_snapshot(
    artoo:::.dx_check_data(data.frame(A = 1), NULL),
    error = TRUE
  )
  expect_error(
    artoo:::.dx_check_data(data.frame(A = 1), NULL),
    class = "artoo_error_input"
  )
})

test_that("nothing to fill leaves the spec alone", {
  # The three early exits on the data path. Each one is a spec the data
  # cannot inform, and each has to return the spec untouched rather than
  # rebuild it -- a rebuild would drop slots the caller still holds.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      length = 8L,
      stringsAsFactors = FALSE
    )
  )
  bare <- S7::set_props(spec, variables = spec@variables[0L, ])
  expect_identical(artoo:::.dx_data_lengths(bare, list(VS = vs_data())), bare)

  # No value-level row's type is blank, so nothing is inferred.
  expect_identical(artoo:::.dx_data_values(spec, list(VS = vs_data())), spec)
})

test_that("pooling skips a spec where nothing was touched", {
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      length = 8L,
      stringsAsFactors = FALSE
    )
  )
  lengths <- 8L
  expect_identical(
    artoo:::.dx_pool_lengths(spec, lengths, touched = FALSE),
    lengths
  )
  # And when the OID count and the length vector disagree, which means the
  # spec changed shape underneath: leave the lengths as they are rather than
  # pair them up by position.
  expect_identical(
    artoo:::.dx_pool_lengths(spec, c(8L, 12L), touched = c(TRUE, TRUE)),
    c(8L, 12L)
  )
})

test_that("a value-level type stays blank when the data cannot answer it", {
  # Three ways the data declines to fill a blank value-level type: the
  # dataset is not among the frames, and the where clause selects no rows.
  # Inferring from an absent or empty selection would invent a type.
  spec <- data_spec(
    variables = data.frame(
      dataset = "VS",
      variable = "VSORRES",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    values = data.frame(
      dataset = c("AE", "VS"),
      variable = c("AEDECOD", "VSORRES"),
      data_type = NA_character_,
      where_clause_id = c("WC.1", "WC.2"),
      stringsAsFactors = FALSE
    ),
    where_clauses = data.frame(
      where_clause_id = c("WC.1", "WC.2"),
      check_order = 1L,
      value_order = 1L,
      dataset = c("AE", "VS"),
      variable = c("AESER", "VSTESTCD"),
      comparator = "EQ",
      value = c("Y", "NOSUCHTEST"),
      stringsAsFactors = FALSE
    )
  )
  # Same object back: nothing was inferred, so nothing is rebuilt.
  expect_identical(artoo:::.dx_data_values(spec, list(VS = vs_data())), spec)
})

# ---- data = a folder -------------------------------------------------------

folder_spec <- function() {
  artoo_spec(
    standard = "SDTMIG 3.4",
    datasets = data.frame(
      dataset = c("DM", "VS"),
      label = c("Demographics", "Vital Signs"),
      class = c("SPECIAL PURPOSE", "FINDINGS"),
      domain = c("DM", "VS"),
      purpose = "Tabulation",
      repeating = c(FALSE, TRUE),
      structure = c("One record per subject", "One record per test"),
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = c("DM", "DM", "VS", "VS"),
      variable = c("USUBJID", "SEX", "USUBJID", "VSORRES"),
      label = "x",
      data_type = "string",
      length = NA_integer_,
      origin = "Collected",
      stringsAsFactors = FALSE
    )
  )
}

folder_frames <- function() {
  list(
    DM = data.frame(
      USUBJID = c("01-001", "01-002"),
      SEX = c("F", "M"),
      stringsAsFactors = FALSE
    ),
    VS = data.frame(
      USUBJID = c("01-001", "01-002"),
      VSORRES = c("162.6", "170.0"),
      stringsAsFactors = FALSE
    )
  )
}

test_that("a folder of datasets writes the same define as the named list", {
  skip_if_not_installed("xml2")
  # The whole point of the feature: the folder carries what the list makes
  # the caller retype, so the two calls must be indistinguishable downstream.
  spec <- folder_spec()
  frames <- folder_frames()
  d <- withr::local_tempdir()
  write_json(frames$DM, file.path(d, "dm.json"))
  write_json(frames$VS, file.path(d, "vs.json"))

  a <- file.path(withr::local_tempdir(), "a.xml")
  b <- file.path(withr::local_tempdir(), "b.xml")
  suppressMessages(
    suppressWarnings(write_spec(spec, a, data = d, created = FROZEN_DATA))
  )
  suppressWarnings(write_spec(spec, b, data = frames, created = FROZEN_DATA))

  expect_identical(readLines(a, warn = FALSE), readLines(b, warn = FALSE))
  # ...and the data actually changed the document, so the equality above is
  # not two identical no-ops.
  bare <- file.path(withr::local_tempdir(), "bare.xml")
  suppressWarnings(write_spec(spec, bare, created = FROZEN_DATA))
  expect_false(
    identical(readLines(a, warn = FALSE), readLines(bare, warn = FALSE))
  )
})

test_that("case does not matter when matching a file to a dataset", {
  skip_if_not_installed("xml2")
  spec <- folder_spec()
  frames <- folder_frames()
  d <- withr::local_tempdir()
  write_json(frames$DM, file.path(d, "DM.json"))
  write_json(frames$VS, file.path(d, "Vs.json"))
  resolved <- suppressMessages(
    artoo:::.dx_resolve_data_dir(d, spec)
  )
  expect_setequal(names(resolved), c("DM", "VS"))
})

test_that("one dataset matching two files aborts instead of choosing", {
  # Two formats can disagree about byte width, so a silent pick changes the
  # document artoo writes.
  spec <- folder_spec()
  frames <- folder_frames()
  d <- withr::local_tempdir()
  write_json(frames$DM, file.path(d, "dm.json"))
  write_rds(frames$DM, file.path(d, "dm.rds"))
  write_json(frames$VS, file.path(d, "vs.json"))

  expect_snapshot(artoo:::.dx_resolve_data_dir(d, spec), error = TRUE)
  expect_error(
    artoo:::.dx_resolve_data_dir(d, spec),
    class = "artoo_error_input"
  )
  # ...and data_format is the way out.
  resolved <- suppressMessages(
    artoo:::.dx_resolve_data_dir(d, spec, data_format = "json")
  )
  expect_setequal(names(resolved), c("DM", "VS"))
})

test_that("a folder matching nothing warns and leaves the spec alone", {
  # It must NOT hit the empty-list abort: the resolver has already said what
  # is wrong, and a second message blaming the caller's list would be false.
  spec <- folder_spec()
  d <- withr::local_tempdir()
  write_json(folder_frames()$DM, file.path(d, "unrelated.json"))

  expect_warning(
    resolved <- artoo:::.dx_resolve_data_dir(d, spec),
    "matches a dataset the spec names"
  )
  expect_identical(resolved, list())
  expect_no_error(
    suppressWarnings(artoo:::.dx_check_data(d, spec))
  )
})

test_that("partial coverage is reported once, both directions", {
  spec <- folder_spec()
  d <- withr::local_tempdir()
  write_json(folder_frames()$DM, file.path(d, "dm.json"))
  write_json(folder_frames()$VS, file.path(d, "demo.json"))
  # The temp path is machine-specific; redact it or the snapshot churns on
  # every run and differs across CI runners.
  expect_snapshot(
    resolved <- artoo:::.dx_resolve_data_dir(d, spec),
    transform = function(x) gsub("'[^']*[/\\\\][^'/\\\\]*'", "'<dir>'", x)
  )
  expect_identical(names(resolved), "DM")
})

test_that("a folder is inventoried, not descended", {
  spec <- folder_spec()
  d <- withr::local_tempdir()
  dir.create(file.path(d, "nested"))
  write_json(folder_frames()$DM, file.path(d, "nested", "dm.json"))
  write_json(folder_frames()$VS, file.path(d, "vs.json"))
  resolved <- suppressMessages(artoo:::.dx_resolve_data_dir(d, spec))
  expect_identical(names(resolved), "VS")
})

test_that("a path that is not a directory is refused by what it is", {
  spec <- folder_spec()
  # Fixed basename: the scrubber keeps it, and a random one would churn the
  # snapshot on every run.
  f <- file.path(withr::local_tempdir(), "dm.json")
  write_json(folder_frames()$DM, f)
  expect_snapshot(
    artoo:::.dx_resolve_data_dir(f, spec),
    error = TRUE,
    transform = function(x) gsub("'[^']*[/\\\\]([^'/\\\\]+)'", "'<tmp>/\\1'", x)
  )
  expect_error(
    artoo:::.dx_resolve_data_dir(f, spec),
    class = "artoo_error_input"
  )
  expect_error(
    artoo:::.dx_resolve_data_dir(file.path(tempdir(), "nope"), spec),
    class = "artoo_error_input"
  )
})

test_that("dataset names differing only in case refuse a folder", {
  # artoo_spec() permits them and matching is case-insensitive, so neither
  # answer would be right. Measured, not assumed: the constructor accepts it.
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = c("DM", "dm"),
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = c("DM", "dm"),
      variable = c("USUBJID", "SEX"),
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  d <- withr::local_tempdir()
  expect_error(
    artoo:::.dx_resolve_data_dir(d, spec),
    class = "artoo_error_spec"
  )
})

test_that("a file recording a different dataset than its name is reported", {
  # The failure this exists for: copy vs.json to dm.json and DM's lengths get
  # widened from VS bytes, silently. The define then asserts a measurement of
  # a dataset it never saw. Every format artoo reads records the real name,
  # and the frame is already in hand, so the check is free.
  spec <- folder_spec()
  vs <- apply_spec(cdisc_vs, sdtm_spec, "VS", conformance = "off")
  d <- withr::local_tempdir()
  write_json(vs, file.path(d, "dm.json"))

  expect_warning(
    suppressMessages(artoo:::.dx_resolve_data_dir(d, spec)),
    "records VS, matched to DM"
  )
})

test_that("a file that records no name of its own is not accused", {
  # A frame that never carried `dataset_name` writes the placeholder. It is
  # saying "I do not know", not "I am DATA", and warning on it would fire on
  # every hand-built file.
  spec <- folder_spec()
  d <- withr::local_tempdir()
  # xpt, so the unrelated archive-shape warning stays out of the way and this
  # asserts only what it is about.
  write_xpt(folder_frames()$DM, file.path(d, "dm.xpt"))
  expect_no_warning(suppressMessages(artoo:::.dx_resolve_data_dir(d, spec)))
})

test_that("a non-xpt folder warns that the derived archive location is not there", {
  # artoo derives `<dataset>.xpt` for a dataset stating no archive location.
  # The folder has just shown the dataset is not stored that way, so the
  # derived reference points at a file nobody has seen -- and this is the one
  # caller holding evidence about it.
  spec <- folder_spec()
  d <- withr::local_tempdir()
  write_json(folder_frames()$DM, file.path(d, "dm.json"))
  write_json(folder_frames()$VS, file.path(d, "vs.json"))
  expect_warning(
    suppressMessages(artoo:::.dx_resolve_data_dir(d, spec)),
    "name a file the folder does not hold"
  )

  # An xpt folder is what the derivation already assumes, so it says nothing.
  x <- withr::local_tempdir()
  write_xpt(folder_frames()$DM, file.path(x, "dm.xpt"))
  write_xpt(folder_frames()$VS, file.path(x, "vs.xpt"))
  expect_no_warning(suppressMessages(artoo:::.dx_resolve_data_dir(x, spec)))
})

test_that("coverage is reported even when every dataset was found", {
  # The complete case is the one a real build hits, and which files informed
  # a submission document is the thing a reader cannot recover afterwards.
  spec <- folder_spec()
  d <- withr::local_tempdir()
  write_xpt(folder_frames()$DM, file.path(d, "dm.xpt"))
  write_xpt(folder_frames()$VS, file.path(d, "vs.xpt"))
  expect_message(artoo:::.dx_resolve_data_dir(d, spec), "Read 2 of 2 datasets")
  expect_message(artoo:::.dx_resolve_data_dir(d, spec), "dm.xpt")
})

test_that("data_format without a folder is refused, not ignored", {
  spec <- folder_spec()
  expect_snapshot(
    artoo:::.dx_check_data(folder_frames(), spec, data_format = "json"),
    error = TRUE
  )
  expect_error(
    artoo:::.dx_check_data(folder_frames(), spec, data_format = "json"),
    class = "artoo_error_input"
  )
})

test_that("data_format reaches the resolver through write_spec()", {
  skip_if_not_installed("xml2")
  # Every other test for this argument calls the resolver directly. Severing
  # the threading in .dx_check_data() left the whole suite green while the
  # feature's only escape hatch died through the public API -- the same class
  # of defect as a new formal silently shifting a positional argument.
  spec <- folder_spec()
  frames <- folder_frames()
  d <- withr::local_tempdir()
  write_json(frames$DM, file.path(d, "dm.json"))
  write_rds(frames$DM, file.path(d, "dm.rds"))
  write_json(frames$VS, file.path(d, "vs.json"))

  out <- file.path(withr::local_tempdir(), "d.xml")
  # Ambiguous without the restriction...
  expect_error(
    write_spec(spec, out, data = d, created = FROZEN_DATA),
    class = "artoo_error_input"
  )
  # ...and resolved with it, all the way from the exported function.
  expect_no_error(
    suppressMessages(
      suppressWarnings(
        write_spec(
          spec,
          out,
          data = d,
          data_format = "json",
          created = FROZEN_DATA
        )
      )
    )
  )
})

test_that("two extensions of one format do not point at data_format", {
  # `data_format = "parquet"` cannot separate dm.parquet from dm.pq, so
  # naming the argument there sends the reader in a circle.
  spec <- folder_spec()
  d <- withr::local_tempdir()
  write_parquet(folder_frames()$DM, file.path(d, "dm.parquet"))
  file.copy(file.path(d, "dm.parquet"), file.path(d, "dm.pq"))
  expect_error(
    artoo:::.dx_resolve_data_dir(d, spec),
    "remove or rename one"
  )
})

test_that("a colliding dataset group is named in full, and duplicates are called duplicates", {
  # `unique(datasets[duplicated(...)])` kept only the LATER members, so
  # c("DM", "dm") showed one name and left the reader to guess the other.
  # And two identical names do not "differ only in case".
  twin_spec <- function(names) {
    artoo_spec(
      datasets = data.frame(
        dataset = names,
        structure = "One record per subject",
        stringsAsFactors = FALSE
      ),
      variables = data.frame(
        dataset = names,
        variable = paste0("V", seq_along(names)),
        data_type = "string",
        stringsAsFactors = FALSE
      )
    )
  }
  d <- withr::local_tempdir()

  expect_error(
    artoo:::.dx_resolve_data_dir(d, twin_spec(c("DM", "dm"))),
    "DM"
  )
  expect_error(
    artoo:::.dx_resolve_data_dir(d, twin_spec(c("DM", "dm"))),
    "differ only in case"
  )
  expect_error(
    artoo:::.dx_resolve_data_dir(d, twin_spec(c("DM", "DM"))),
    "same dataset more than once"
  )
})

test_that("a spec naming no datasets says so, rather than blaming the folder", {
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = character(0),
      structure = character(0),
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = character(0),
      variable = character(0),
      data_type = character(0),
      stringsAsFactors = FALSE
    )
  )
  d <- withr::local_tempdir()
  expect_warning(
    artoo:::.dx_resolve_data_dir(d, spec),
    "spec names no datasets"
  )
})

test_that("an unusable data path says what was wrong with it", {
  spec <- folder_spec()
  expect_error(
    artoo:::.dx_resolve_data_dir(NA_character_, spec),
    "NA",
    class = "artoo_error_input"
  )
  expect_error(
    artoo:::.dx_resolve_data_dir("", spec),
    "empty string",
    class = "artoo_error_input"
  )
  expect_error(
    artoo:::.dx_resolve_data_dir(c("a", "b"), spec),
    "2 values",
    class = "artoo_error_input"
  )
})

test_that("the folder is inventoried, and non-dataset files are skipped", {
  # Both guards were unasserted: a subdirectory named like a dataset file, and
  # a file whose extension no codec claims.
  spec <- folder_spec()
  d <- withr::local_tempdir()
  dir.create(file.path(d, "dm.json"))
  writeLines("not a dataset", file.path(d, "vs.txt"))
  write_xpt(folder_frames()$VS, file.path(d, "vs.xpt"))

  resolved <- suppressMessages(artoo:::.dx_resolve_data_dir(d, spec))
  expect_identical(names(resolved), "VS")
})

test_that("the ambiguity abort keeps the dataset-to-files pairing", {
  # Flattening every candidate into one list loses the pairing exactly when
  # there is more than one dataset to pair, which is when it is needed.
  many <- c("DM", "VS", "AE")
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = many,
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = many,
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  d <- withr::local_tempdir()
  f <- data.frame(USUBJID = "01-001", stringsAsFactors = FALSE)
  for (n in tolower(many)) {
    write_json(f, file.path(d, paste0(n, ".json")))
    write_rds(f, file.path(d, paste0(n, ".rds")))
  }
  expect_snapshot(artoo:::.dx_resolve_data_dir(d, spec), error = TRUE)
})

test_that("a braced dataset name survives the message intact", {
  # .cli_escape() is load-bearing: unescaped, cli reads `D{1}` as
  # interpolation and prints `D1`, naming a dataset that does not exist.
  spec <- artoo_spec(
    datasets = data.frame(
      dataset = "D{1}",
      structure = "One record per subject",
      stringsAsFactors = FALSE
    ),
    variables = data.frame(
      dataset = "D{1}",
      variable = "USUBJID",
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  d <- withr::local_tempdir()
  f <- data.frame(USUBJID = "01-001", stringsAsFactors = FALSE)
  write_json(f, file.path(d, "d{1}.json"))
  write_rds(f, file.path(d, "d{1}.rds"))
  expect_error(artoo:::.dx_resolve_data_dir(d, spec), "D\\{1\\}")
})
