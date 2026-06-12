# Tests for the CDISC type vocabulary parser.

test_that(".parse_type canonicalises common SAS / P21 tokens", {
  expect_equal(artoo:::.parse_type("text"), "string")
  expect_equal(artoo:::.parse_type("Char"), "string")
  expect_equal(artoo:::.parse_type("integer"), "integer")
  expect_equal(artoo:::.parse_type("float"), "float")
  expect_equal(artoo:::.parse_type("num"), "float")
  expect_equal(artoo:::.parse_type("datetime"), "datetime")
})

test_that(".parse_type strips a trailing length in parens", {
  expect_equal(artoo:::.parse_type("integer (8)"), "integer")
  expect_equal(artoo:::.parse_type("text (200)"), "string")
})

test_that(".parse_type accepts an already-canonical value case-insensitively", {
  expect_equal(artoo:::.parse_type("string"), "string")
  expect_equal(artoo:::.parse_type("uri"), "URI")
})

test_that(".parse_type maps Define-XML date subtypes to CDISC dataTypes", {
  expect_equal(artoo:::.parse_type("partialDate"), "date")
  expect_equal(artoo:::.parse_type("partialTime"), "time")
  expect_equal(artoo:::.parse_type("partialDatetime"), "datetime")
  expect_equal(artoo:::.parse_type("incompleteDate"), "date")
  expect_equal(artoo:::.parse_type("incompleteDatetime"), "datetime")
  expect_equal(artoo:::.parse_type("durationDatetime"), "string")
  expect_equal(artoo:::.parse_type("intervalDatetime"), "string")
})

test_that(".parse_type rejects an unknown token", {
  expect_error(artoo:::.parse_type("widget"), class = "artoo_error_type")
  expect_error(artoo:::.parse_type("widget"), "closed CDISC set")
})

test_that(".parse_type rejects a missing or empty type", {
  expect_error(artoo:::.parse_type(NA_character_), class = "artoo_error_type")
  expect_error(artoo:::.parse_type(""), class = "artoo_error_type")
})

test_that(".type_storage maps dataTypes to R storage modes", {
  expect_equal(artoo:::.type_storage("string"), "character")
  expect_equal(artoo:::.type_storage("integer"), "integer")
  expect_equal(artoo:::.type_storage("float"), "double")
  expect_equal(artoo:::.type_storage("decimal"), "character")
  expect_equal(artoo:::.type_storage("date"), "double")
  expect_equal(artoo:::.type_storage("boolean"), "logical")
})

test_that(".type_storage maps the date/time and URI types", {
  expect_equal(artoo:::.type_storage("datetime"), "double")
  expect_equal(artoo:::.type_storage("time"), "double")
  expect_equal(artoo:::.type_storage("URI"), "character")
  expect_equal(artoo:::.type_storage("double"), "double")
  expect_equal(artoo:::.type_storage("nonsense"), "character")
})

test_that(".na_for_type returns a typed NA per dataType", {
  expect_identical(
    artoo:::.na_for_type("integer", 2L),
    c(NA_integer_, NA_integer_)
  )
  expect_identical(artoo:::.na_for_type("string", 1L), NA_character_)
  expect_identical(artoo:::.na_for_type("float", 1L), NA_real_)
})

test_that(".coerce_to_type reports NA introduced by lossy coercion", {
  res <- artoo:::.coerce_to_type(c("1", "x", "3"), "integer")
  expect_equal(res$value, c(1L, NA, 3L))
  expect_equal(res$n_na_introduced, 1L)
})

test_that(".coerce_to_type does not flag pre-existing NA as introduced", {
  res <- artoo:::.coerce_to_type(c("1", NA, "3"), "integer")
  expect_equal(res$n_na_introduced, 0L)
})

test_that(".coerce_to_type counts fractional values truncated to integer (review B6)", {
  res <- artoo:::.coerce_to_type(c(63.7, 2, NA), "integer")
  expect_identical(res$value, c(63L, 2L, NA))
  expect_identical(res$n_lossy, 1L)
  expect_identical(res$n_na_introduced, 0L)
})

test_that(".coerce_to_type coerces a factor through its LABELS, not level codes", {
  # Bug: as.integer(<factor>) returns the integer LEVEL CODES (1,2,3), not the
  # authored values (10,20,30). On main this returned c(1L,2L,3L) and the lossy
  # guard agreed with itself (n_lossy == 0), writing wrong values silently.
  res <- artoo:::.coerce_to_type(factor(c("10", "20", "30")), "integer")
  expect_identical(res$value, c(10L, 20L, 30L))
  expect_identical(res$n_lossy, 0L)
  expect_identical(res$n_na_introduced, 0L)
})

test_that(".coerce_to_type coerces a factor to float through labels (no-guard path)", {
  # The double path has NO lossy guard, so a factor->float corruption was
  # entirely silent on main: factor(c("1.5","2.5")) became c(1,2) (codes).
  res <- artoo:::.coerce_to_type(factor(c("1.5", "2.5")), "float")
  expect_identical(res$value, c(1.5, 2.5))
  expect_identical(res$n_na_introduced, 0L)
})

test_that(".coerce_to_type flags NA when a factor label cannot coerce to integer", {
  # Non-numeric labels become NA (and the na_introduced guard now fires),
  # instead of silently mapping to level codes 1,2.
  res <- artoo:::.coerce_to_type(factor(c("M", "F")), "integer")
  expect_identical(res$value, c(NA_integer_, NA_integer_))
  expect_identical(res$n_na_introduced, 2L)
})

test_that(".coerce_to_type leaves a factor's labels intact for a string dataType", {
  # The string path was already safe (as.character(factor) = labels); guard it.
  res <- artoo:::.coerce_to_type(factor(c("M", "F")), "string")
  expect_identical(res$value, c("M", "F"))
  expect_identical(res$n_na_introduced, 0L)
})

test_that(".coerce_mode coerces a factor through labels for its other callers", {
  # .coerce_mode is also called directly (spec_construct), so it owns the guard
  # too: a factor of numeric labels must become the values, not the codes.
  expect_identical(
    artoo:::.coerce_mode(factor(c("10", "20")), "integer"),
    c(10L, 20L)
  )
})
