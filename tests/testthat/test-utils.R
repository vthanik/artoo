# Tests for the small base-R helpers.

test_that(".coerce_mode casts to each storage mode, preserving NA", {
  expect_identical(vport:::.coerce_mode(c(1, 2), "character"), c("1", "2"))
  expect_identical(vport:::.coerce_mode(c("1", "x"), "integer"), c(1L, NA))
  expect_identical(vport:::.coerce_mode(c("1.5", "x"), "double"), c(1.5, NA))
  expect_identical(vport:::.coerce_mode("anything", "raw"), "anything")
})

test_that(".as_logical accepts the common truthy / falsy spellings", {
  expect_identical(
    vport:::.as_logical(c("Y", "N", "Yes", "no", "T", "F", "1", "0")),
    c(TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE)
  )
  expect_identical(vport:::.as_logical(c(1, 0, 2)), c(TRUE, FALSE, TRUE))
  expect_identical(vport:::.as_logical(c(TRUE, NA)), c(TRUE, NA))
  expect_true(is.na(vport:::.as_logical("maybe")))
})

test_that(".na_mode returns a typed NA vector of the requested length", {
  expect_identical(
    vport:::.na_mode("character", 2L),
    c(NA_character_, NA_character_)
  )
  expect_identical(vport:::.na_mode("integer", 1L), NA_integer_)
  expect_identical(vport:::.na_mode("double", 1L), NA_real_)
  expect_identical(vport:::.na_mode("logical", 1L), NA)
  expect_identical(vport:::.na_mode("other", 1L), NA)
})

test_that(".check_path accepts one non-empty string and rejects the rest", {
  expect_identical(vport:::.check_path("a.xpt"), "a.xpt")
  expect_error(vport:::.check_path(NULL), class = "vport_error_input")
  expect_error(vport:::.check_path(NA_character_), class = "vport_error_input")
  expect_error(vport:::.check_path(""), class = "vport_error_input")
  expect_error(vport:::.check_path(c("a", "b")), class = "vport_error_input")
})

test_that(".onLoad registers S7 methods without error", {
  expect_no_error(vport:::.onLoad("lib", "vport"))
})
