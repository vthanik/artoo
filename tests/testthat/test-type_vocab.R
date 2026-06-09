# Tests for the CDISC type vocabulary parser.

test_that(".parse_type canonicalises common SAS / P21 tokens", {
  expect_equal(vport:::.parse_type("text"), "string")
  expect_equal(vport:::.parse_type("Char"), "string")
  expect_equal(vport:::.parse_type("integer"), "integer")
  expect_equal(vport:::.parse_type("float"), "float")
  expect_equal(vport:::.parse_type("num"), "float")
  expect_equal(vport:::.parse_type("datetime"), "datetime")
})

test_that(".parse_type strips a trailing length in parens", {
  expect_equal(vport:::.parse_type("integer (8)"), "integer")
  expect_equal(vport:::.parse_type("text (200)"), "string")
})

test_that(".parse_type accepts an already-canonical value case-insensitively", {
  expect_equal(vport:::.parse_type("string"), "string")
  expect_equal(vport:::.parse_type("uri"), "URI")
})

test_that(".parse_type maps Define-XML date subtypes to CDISC dataTypes", {
  expect_equal(vport:::.parse_type("partialDate"), "date")
  expect_equal(vport:::.parse_type("partialTime"), "time")
  expect_equal(vport:::.parse_type("partialDatetime"), "datetime")
  expect_equal(vport:::.parse_type("incompleteDate"), "date")
  expect_equal(vport:::.parse_type("incompleteDatetime"), "datetime")
  expect_equal(vport:::.parse_type("durationDatetime"), "string")
  expect_equal(vport:::.parse_type("intervalDatetime"), "string")
})

test_that(".parse_type rejects an unknown token", {
  expect_error(vport:::.parse_type("widget"), class = "vport_error_type")
  expect_error(vport:::.parse_type("widget"), "closed CDISC set")
})

test_that(".parse_type rejects a missing or empty type", {
  expect_error(vport:::.parse_type(NA_character_), class = "vport_error_type")
  expect_error(vport:::.parse_type(""), class = "vport_error_type")
})

test_that(".type_storage maps dataTypes to R storage modes", {
  expect_equal(vport:::.type_storage("string"), "character")
  expect_equal(vport:::.type_storage("integer"), "integer")
  expect_equal(vport:::.type_storage("float"), "double")
  expect_equal(vport:::.type_storage("decimal"), "character")
  expect_equal(vport:::.type_storage("date"), "double")
  expect_equal(vport:::.type_storage("boolean"), "logical")
})

test_that(".type_storage maps the date/time and URI types", {
  expect_equal(vport:::.type_storage("datetime"), "double")
  expect_equal(vport:::.type_storage("time"), "double")
  expect_equal(vport:::.type_storage("URI"), "character")
  expect_equal(vport:::.type_storage("double"), "double")
  expect_equal(vport:::.type_storage("nonsense"), "character")
})

test_that(".na_for_type returns a typed NA per dataType", {
  expect_identical(
    vport:::.na_for_type("integer", 2L),
    c(NA_integer_, NA_integer_)
  )
  expect_identical(vport:::.na_for_type("string", 1L), NA_character_)
  expect_identical(vport:::.na_for_type("float", 1L), NA_real_)
})

test_that(".coerce_to_type reports NA introduced by lossy coercion", {
  res <- vport:::.coerce_to_type(c("1", "x", "3"), "integer")
  expect_equal(res$value, c(1L, NA, 3L))
  expect_equal(res$n_na_introduced, 1L)
})

test_that(".coerce_to_type does not flag pre-existing NA as introduced", {
  res <- vport:::.coerce_to_type(c("1", NA, "3"), "integer")
  expect_equal(res$n_na_introduced, 0L)
})
