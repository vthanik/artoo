# Tests for where-clause reading, from both workbook generations.
#
# A where clause decides which rows a value-level definition applies to, so a
# mis-parse silently changes the meaning of the metadata rather than failing.
# That is why the free-text grammar is restricted and refuses what it does not
# understand, and why these tests lean on the refusals as much as the parses.

test_that("a set comparator splits its value list; a scalar one does not", {
  f <- artoo:::.wc_split_values
  expect_identical(f("CAN, MEX", "IN"), c("CAN", "MEX"))
  expect_identical(f("(CAN, MEX)", "IN"), c("CAN", "MEX"))
  expect_identical(f("(A, B)", "NOTIN"), c("A", "B"))

  # EQ against a value containing a comma is ONE value. Splitting it would
  # silently widen the condition.
  expect_identical(f("One, Two", "EQ"), "One, Two")
})

test_that("quoting lets a value contain a comma", {
  # The CDISC examples carry values like "LOCAL LAB"; a naive split on comma
  # corrupts real data.
  expect_identical(
    artoo:::.wc_split_values('"One, Two", Three', "IN"),
    c("One, Two", "Three")
  )
})

test_that("the free-text form strips parentheses for EVERY comparator", {
  # The rendered form parenthesises even a scalar: "VSTESTCD EQ (HEIGHT)".
  # Stripping only for IN -- as the prior art did -- emits "(HEIGHT)" as the
  # check value and corrupts every scalar comparison in the document.
  rows <- artoo:::.wc_parse_text("VSTESTCD EQ (HEIGHT)", "WC.1")
  expect_identical(rows$value, "HEIGHT")

  rows <- artoo:::.wc_parse_text("COUNTRY IN (CAN, MEX)", "WC.2")
  expect_identical(rows$value, c("CAN", "MEX"))
})

test_that("AND becomes multiple range checks in one clause", {
  rows <- artoo:::.wc_parse_text(
    "LBTESTCD IN (BILI, GLUC) AND LBSPEC EQ (BLOOD)",
    "WC.3"
  )
  expect_identical(sort(unique(rows$check_order)), c(1L, 2L))
  expect_identical(rows$value, c("BILI", "GLUC", "BLOOD"))
  expect_identical(unique(rows$where_clause_id), "WC.3")
  # Define-XML constrains a value-level where clause to Soft.
  expect_identical(unique(rows$soft_hard), "Soft")
})

test_that("OR over one variable is rewritten to IN", {
  # Define-XML has no disjunction: the checks in a clause are ANDed. An OR
  # over a single variable is exactly what IN means, so it is expressible.
  rows <- artoo:::.wc_parse_text("SEX EQ (F) OR SEX EQ (M)", "WC.4")
  expect_identical(unique(rows$comparator), "IN")
  expect_identical(rows$value, c("F", "M"))
  expect_identical(unique(rows$check_order), 1L)
})

test_that("OR across different variables is refused, not silently narrowed", {
  # Rewriting it to AND would change which rows the definition applies to,
  # which is worse than refusing to read the file.
  expect_error(
    artoo:::.wc_parse_text("SEX EQ (F) OR RACE EQ (WHITE)", "WC.5"),
    class = "artoo_error_p21_sheet"
  )
  expect_snapshot(
    artoo:::.wc_parse_text("SEX EQ (F) OR RACE EQ (WHITE)", "WC.5"),
    error = TRUE
  )
})

test_that("an unknown comparator is refused", {
  # Pinnacle 21 does not validate comparators at all; the schema enumeration
  # is closed, so catching it at read time gives a far better message than a
  # schema error much later.
  expect_error(
    artoo:::.wc_parse_text("SEX LIKE (F)", "WC.6"),
    class = "artoo_error_p21_sheet"
  )
  expect_snapshot(
    artoo:::.wc_parse_text("SEX LIKE (F)", "WC.6"),
    error = TRUE
  )
})

test_that("unparseable free text is refused with a route out", {
  expect_error(
    artoo:::.wc_parse_text("this is not a condition", "WC.7"),
    class = "artoo_error_p21_sheet"
  )
})

test_that("blank free text yields nothing rather than an empty clause", {
  expect_null(artoo:::.wc_parse_text(NA_character_, "WC.8"))
  expect_null(artoo:::.wc_parse_text("   ", "WC.9"))
})

test_that("a tabular WhereClauses sheet groups rows by id into one clause", {
  sheet <- data.frame(
    where_clause_id = c("WC.A", "WC.A", "WC.B"),
    dataset = c("LB", "LB", "VS"),
    variable = c("LBTESTCD", "LBSPEC", "VSTESTCD"),
    comparator = c("IN", "EQ", "EQ"),
    value = c("BILI, GLUC", "BLOOD", "HEIGHT"),
    stringsAsFactors = FALSE
  )
  rows <- artoo:::.wc_from_sheet(sheet)

  expect_identical(sum(rows$where_clause_id == "WC.A"), 3L)
  expect_identical(
    unique(rows$check_order[rows$where_clause_id == "WC.A"]),
    c(1L, 2L)
  )
  expect_identical(rows$value[rows$where_clause_id == "WC.B"], "HEIGHT")
  expect_identical(unique(rows$soft_hard), "Soft")
})

test_that("a tabular sheet missing a required column is refused", {
  sheet <- data.frame(where_clause_id = "WC.A", stringsAsFactors = FALSE)
  expect_error(artoo:::.wc_from_sheet(sheet), class = "artoo_error_p21_sheet")
})

test_that("an empty or absent WhereClauses sheet is not an error", {
  expect_null(artoo:::.wc_from_sheet(NULL))
  expect_null(artoo:::.wc_from_sheet(data.frame()))
})

test_that("a comparator cell that is blank is refused", {
  sheet <- data.frame(
    where_clause_id = "WC.A",
    dataset = "LB",
    variable = "LBTESTCD",
    comparator = NA_character_,
    value = "X",
    stringsAsFactors = FALSE
  )
  expect_error(artoo:::.wc_from_sheet(sheet), class = "artoo_error_p21_sheet")
})

test_that("a workbook with no WhereClauses sheet derives them from free text", {
  skip_if_not_installed("readxl")
  spec <- read_spec(
    system.file("extdata", "sdtm-spec.xlsx", package = "artoo")
  )
  expect_gt(nrow(spec@where_clauses), 0L)
  # Parentheses must be gone: the source cells read "QNAM EQ (RACE1)".
  expect_false(any(grepl("[()]", spec@where_clauses$value)))
  expect_true(all(spec@where_clauses$comparator %in% artoo:::.wc_comparators))
})

test_that("free text with too few tokens is refused as unreadable", {
  # "SEX" alone is not VARIABLE COMPARATOR value. This is a different refusal
  # from an unknown comparator, and it points the user at the tabular sheet,
  # which needs no parsing at all.
  expect_error(
    artoo:::.wc_parse_text("SEX", "WC.10"),
    class = "artoo_error_p21_sheet"
  )
  expect_snapshot(artoo:::.wc_parse_text("SEX", "WC.10"), error = TRUE)
})

test_that("an empty value cell splits to a single empty value", {
  expect_identical(artoo:::.wc_split_outside_quotes(""), "")
  expect_identical(artoo:::.wc_split_values(NA_character_, "IN"), "")
})

test_that("a WhereClauses sheet with no Value column is read, not refused", {
  # Value is optional: a comparator that needs no operand is legal.
  sheet <- data.frame(
    where_clause_id = "WC.A",
    dataset = "LB",
    variable = "LBTESTCD",
    comparator = "EQ",
    stringsAsFactors = FALSE
  )
  rows <- artoo:::.wc_from_sheet(sheet)
  expect_identical(nrow(rows), 1L)
  expect_identical(rows$value, "")
})

test_that("values with no derivable clause yield nothing", {
  expect_null(artoo:::.wc_from_values(NULL))
  expect_null(artoo:::.wc_from_values(data.frame()))
  expect_null(
    artoo:::.wc_from_values(
      data.frame(dataset = "LB", variable = "X", stringsAsFactors = FALSE)
    )
  )
  expect_null(
    artoo:::.wc_from_values(
      data.frame(
        dataset = "LB",
        variable = "X",
        where_clause = NA_character_,
        stringsAsFactors = FALSE
      )
    )
  )
})
