# Tests for the small base-R helpers.

test_that(".coerce_mode casts to each storage mode, preserving NA", {
  expect_identical(artoo:::.coerce_mode(c(1, 2), "character"), c("1", "2"))
  expect_identical(artoo:::.coerce_mode(c("1", "x"), "integer"), c(1L, NA))
  expect_identical(artoo:::.coerce_mode(c("1.5", "x"), "double"), c(1.5, NA))
  expect_identical(artoo:::.coerce_mode("anything", "raw"), "anything")
})

test_that(".as_logical accepts the common truthy / falsy spellings", {
  expect_identical(
    artoo:::.as_logical(c("Y", "N", "Yes", "no", "T", "F", "1", "0")),
    c(TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE)
  )
  expect_identical(artoo:::.as_logical(c(1, 0, 2)), c(TRUE, FALSE, TRUE))
  expect_identical(artoo:::.as_logical(c(TRUE, NA)), c(TRUE, NA))
  expect_true(is.na(artoo:::.as_logical("maybe")))
})

test_that(".na_mode returns a typed NA vector of the requested length", {
  expect_identical(
    artoo:::.na_mode("character", 2L),
    c(NA_character_, NA_character_)
  )
  expect_identical(artoo:::.na_mode("integer", 1L), NA_integer_)
  expect_identical(artoo:::.na_mode("double", 1L), NA_real_)
  expect_identical(artoo:::.na_mode("logical", 1L), NA)
  expect_identical(artoo:::.na_mode("other", 1L), NA)
})

test_that(".check_path accepts one non-empty string and rejects the rest", {
  expect_identical(artoo:::.check_path("a.xpt"), "a.xpt")
  expect_error(artoo:::.check_path(NULL), class = "artoo_error_input")
  expect_error(artoo:::.check_path(NA_character_), class = "artoo_error_input")
  expect_error(artoo:::.check_path(""), class = "artoo_error_input")
  expect_error(artoo:::.check_path(c("a", "b")), class = "artoo_error_input")
})

test_that(".onLoad registers S7 methods without error", {
  expect_no_error(artoo:::.onLoad("lib", "artoo"))
})

test_that(".move_into_place renames a temp file into the target", {
  dir <- withr::local_tempdir()
  tmp <- file.path(dir, "src.tmp")
  path <- file.path(dir, "dest.txt")
  writeLines("hi", tmp)
  artoo:::.move_into_place(tmp, path)
  expect_true(file.exists(path))
  expect_false(file.exists(tmp))
  expect_identical(readLines(path), "hi")
})

test_that(".move_into_place aborts when rename and copy both fail", {
  testthat::local_mocked_bindings(.rename_file = function(from, to) FALSE)
  # A non-existent source makes file.copy() return FALSE, so the move fails.
  expect_error(
    suppressWarnings(artoo:::.move_into_place(tempfile(), tempfile())),
    class = "artoo_error_codec"
  )
})

test_that(".move_into_place falls back to copy when rename fails", {
  testthat::local_mocked_bindings(.rename_file = function(from, to) FALSE)
  dir <- withr::local_tempdir()
  tmp <- file.path(dir, "src.tmp")
  path <- file.path(dir, "dest.txt")
  writeLines("hi", tmp)
  artoo:::.move_into_place(tmp, path)
  expect_true(file.exists(path))
  expect_false(file.exists(tmp))
  expect_identical(readLines(path), "hi")
})
