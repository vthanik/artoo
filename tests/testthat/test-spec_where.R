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

test_that("an empty value cell is refused for a set comparator", {
  expect_identical(artoo:::.wc_split_outside_quotes(""), "")
  # An IN with nothing to match is malformed, not "matches nothing".
  expect_error(
    artoo:::.wc_split_values(NA_character_, "IN"),
    class = "artoo_error_p21_sheet"
  )
  # A scalar comparator keeps an empty cell verbatim; that is the caller's
  # problem to validate, not this splitter's.
  expect_identical(artoo:::.wc_split_values(NA_character_, "EQ"), "")
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
  # Returns both the clauses and the (possibly rewritten) values, so the
  # caller can pick up the foreign key that was written back.
  expect_null(artoo:::.wc_from_values(NULL)$where_clauses)
  expect_null(artoo:::.wc_from_values(data.frame())$where_clauses)
  expect_null(
    artoo:::.wc_from_values(
      data.frame(dataset = "LB", variable = "X", stringsAsFactors = FALSE)
    )$where_clauses
  )
  expect_null(
    artoo:::.wc_from_values(
      data.frame(
        dataset = "LB",
        variable = "X",
        where_clause = NA_character_,
        stringsAsFactors = FALSE
      )
    )$where_clauses
  )
})

# ---- regressions for unsound OR rewrites (review finding, critical) -----

test_that("OR is rewritten to IN only when every operand is EQ or IN", {
  # Each of these was silently rewritten to `IN` before, changing which rows
  # the clause selects with no error at all. "Exactly what IN means" is true
  # only of equality-shaped operands.
  p <- artoo:::.wc_parse_text

  # NE admits every value but one; folding it into IN inverts the meaning.
  expect_error(
    p("SEX EQ (F) OR SEX NE (M)", "WC.A"),
    class = "artoo_error_p21_sheet"
  )
  # An interval complement is not a membership test.
  expect_error(
    p("AGE LT (5) OR AGE GT (10)", "WC.B"),
    class = "artoo_error_p21_sheet"
  )
  # This one folded to nearly its own negation.
  expect_error(
    p("SEX NOTIN (F) OR SEX NOTIN (M)", "WC.C"),
    class = "artoo_error_p21_sheet"
  )

  # The one sound rewrite still works.
  rows <- p("SEX EQ (F) OR SEX EQ (M)", "WC.D")
  expect_identical(unique(rows$comparator), "IN")
  expect_identical(rows$value, c("F", "M"))
})

test_that("a clause mixing AND with OR is refused as ambiguous", {
  # Define-XML defines no precedence, so (A AND B) OR C and A AND (B OR C)
  # are both defensible readings and neither can be chosen safely. The old
  # code folded the AND legs into the OR as well.
  expect_error(
    artoo:::.wc_parse_text("SEX EQ (F) AND SEX EQ (M) OR SEX EQ (U)", "WC.E"),
    class = "artoo_error_p21_sheet"
  )
  expect_snapshot(
    artoo:::.wc_parse_text("SEX EQ (F) AND SEX EQ (M) OR SEX EQ (U)", "WC.E"),
    error = TRUE
  )
})

# ---- tabular-path refusals ---------------------------------------------

test_that("an unbalanced parenthesis pair is not blindly stripped", {
  # "(1), (2)" opens and closes without the first paren matching the last.
  # Trimming both ends yields "1)" and "(2" -- a silent corruption.
  expect_identical(
    artoo:::.wc_split_values("(1), (2)", "IN"),
    c("(1)", "(2)")
  )
  expect_identical(artoo:::.wc_split_values("(A, B)", "IN"), c("A", "B"))
})

test_that("an empty value list is refused, not read as matching nothing", {
  # Every comparator in the closed enumeration takes an operand, so an empty
  # list is malformed rather than meaningful.
  expect_error(
    artoo:::.wc_split_values("()", "IN", id = "WC.F"),
    class = "artoo_error_p21_sheet"
  )
  expect_error(
    artoo:::.wc_split_values("(,)", "IN", id = "WC.G"),
    class = "artoo_error_p21_sheet"
  )
})

test_that("an unbalanced quote is refused rather than kept in the value", {
  expect_error(
    artoo:::.wc_split_values('"A, B', "IN", id = "WC.H"),
    class = "artoo_error_p21_sheet"
  )
})

test_that("a repeated value in a list earns a warning", {
  expect_warning(
    artoo:::.wc_split_values("(A, A, B)", "IN", id = "WC.I"),
    class = "artoo_warning_spec"
  )
  expect_identical(
    suppressWarnings(artoo:::.wc_split_values("(A, A, B)", "IN", id = "WC.I")),
    c("A", "B")
  )
})

test_that("a WhereClauses row with no id is refused", {
  # Rows with no id all group under one key, welding unrelated conditions
  # into a single AND clause.
  sheet <- data.frame(
    where_clause_id = c(NA_character_, NA_character_),
    dataset = c("LB", "VS"),
    variable = c("LBTESTCD", "VSTESTCD"),
    comparator = c("EQ", "EQ"),
    value = c("BILI", "HEIGHT"),
    stringsAsFactors = FALSE
  )
  expect_error(artoo:::.wc_from_sheet(sheet), class = "artoo_error_p21_sheet")
})

# ---- derived ids -------------------------------------------------------

test_that("derived where-clause ids are content-addressed, not positional", {
  # Positional ids shift when the caller scopes the read, so the same
  # condition in the same workbook would get a different id depending on how
  # it was read.
  skip_if_not_installed("readxl")
  path <- system.file("extdata", "sdtm-spec.xlsx", package = "artoo")
  full <- read_spec(path)
  scoped <- read_spec(path, datasets = "SUPPDM")

  from_full <- sort(unique(
    full@where_clauses$where_clause_id[full@where_clauses$dataset == "SUPPDM"]
  ))
  from_scoped <- sort(unique(scoped@where_clauses$where_clause_id))
  expect_identical(from_full, from_scoped)
})

test_that("identical conditions share one clause definition", {
  # Define-XML's model is one def:WhereClauseDef referenced by many ItemRefs.
  v <- data.frame(
    dataset = c("LB", "LB"),
    variable = c("LBORRES", "LBORRES"),
    where_clause = c("LBTESTCD EQ (BILI)", "LBTESTCD EQ (BILI)"),
    stringsAsFactors = FALSE
  )
  out <- artoo:::.wc_from_values(v)
  expect_identical(length(unique(out$values$where_clause)), 1L)
  expect_identical(nrow(out$where_clauses), 1L)
})

test_that("the derived id is written back as a foreign key", {
  # Otherwise the only link between a value-level row and its condition is
  # free text, and a writer could re-join them only by position.
  v <- data.frame(
    dataset = "LB",
    variable = "LBORRES",
    where_clause = "LBTESTCD EQ (BILI)",
    stringsAsFactors = FALSE
  )
  out <- artoo:::.wc_from_values(v)
  expect_identical(out$values$where_clause, "WC.LB.LBORRES")
  expect_identical(out$where_clauses$where_clause_id, "WC.LB.LBORRES")
})

test_that("a free-text clause with no dataset or variable is refused", {
  v <- data.frame(
    dataset = NA_character_,
    variable = "QVAL",
    where_clause = "QNAM EQ (RACE1)",
    stringsAsFactors = FALSE
  )
  expect_error(artoo:::.wc_from_values(v), class = "artoo_error_p21_sheet")
})

test_that("writing xlsx warns when it drops a populated structural slot", {
  # Silence here would be exactly the silent truncation the project forbids.
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  spec <- suppressWarnings(
    read_spec(testthat::test_path("fixtures", "define21-sdtm.xml"))
  )
  out <- file.path(withr::local_tempdir(), "dropped.xlsx")
  expect_warning(write_spec(spec, out), class = "artoo_warning_spec")
})

# ---- the tabular generation, end to end --------------------------------

# Build a minimal Pinnacle 21 workbook with a WhereClauses sheet, so the
# tabular path is exercised as a real read rather than a unit call. No
# bundled workbook carries that sheet.
tabular_workbook <- function(value_ref = "WC.A") {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  path <- file.path(
    withr::local_tempdir(.local_envir = parent.frame()),
    "wb.xlsx"
  )
  writexl::write_xlsx(
    list(
      Datasets = data.frame(Dataset = "LB", Label = "Laboratory"),
      Variables = data.frame(
        Dataset = c("LB", "LB"),
        Variable = c("LBTESTCD", "LBORRES"),
        Label = c("Test Code", "Result"),
        `Data Type` = c("text", "text"),
        check.names = FALSE
      ),
      ValueLevel = data.frame(
        Dataset = "LB",
        Variable = "LBORRES",
        `Where Clause` = value_ref,
        `Data Type` = "text",
        check.names = FALSE
      ),
      WhereClauses = data.frame(
        ID = c("WC.A", "WC.A"),
        Dataset = c("LB", "LB"),
        Variable = c("LBTESTCD", "LBTESTCD"),
        Comparator = c("EQ", "NE"),
        Value = c("BILI", "GLUC")
      )
    ),
    path
  )
  path
}

test_that("a WhereClauses sheet is read in preference to the free text", {
  spec <- read_spec(tabular_workbook())
  expect_identical(nrow(spec@where_clauses), 2L)
  expect_identical(unique(spec@where_clauses$where_clause_id), "WC.A")
  expect_identical(spec@where_clauses$check_order, c(1L, 2L))
  # The sheet carries the dataset, which the free-text path cannot supply.
  expect_identical(unique(spec@where_clauses$dataset), "LB")
})

test_that("a value-level row naming an undefined clause warns", {
  # Matching is exact, so this would otherwise be a silent dangling
  # reference straight through to the writer.
  expect_warning(
    read_spec(tabular_workbook(value_ref = "WC.MISSING")),
    class = "artoo_warning_spec"
  )
})

test_that("a case-only near-miss is called out by name", {
  # The most common cause of the warning above, and the least obvious to
  # spot by eye.
  expect_warning(
    read_spec(tabular_workbook(value_ref = "wc.a")),
    "only by case"
  )
})
