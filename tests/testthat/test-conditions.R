# Condition family (.artoo_abort / .artoo_warn / .artoo_inform): every
# condition artoo raises carries the three-level class chain
# c("artoo_<severity>_<kind>", "artoo_<severity>", "artoo_condition") so it is
# catchable at any altitude.

test_that("helper conditions carry the full three-level class chain", {
  err <- rlang::catch_cnd(artoo:::.artoo_abort("boom", kind = "input"))
  expect_s3_class(err, "artoo_error_input")
  expect_s3_class(err, "artoo_error")
  expect_s3_class(err, "artoo_condition")

  wrn <- rlang::catch_cnd(artoo:::.artoo_warn("careful", kind = "encoding"))
  expect_s3_class(wrn, "artoo_warning_encoding")
  expect_s3_class(wrn, "artoo_warning")
  expect_s3_class(wrn, "artoo_condition")

  msg <- rlang::catch_cnd(artoo:::.artoo_inform("fyi", kind = "apply"))
  expect_s3_class(msg, "artoo_message_apply")
  expect_s3_class(msg, "artoo_message")
  expect_s3_class(msg, "artoo_condition")
})

test_that("public errors of different kinds are caught family-wide", {
  # input kind (bad path), codec kind (unknown extension), spec kind
  # (malformed slot) — one tryCatch(artoo_error = ) catches them all.
  expect_error(read_spec(123), class = "artoo_error")
  expect_error(artoo:::.codec_for_ext("zzz"), class = "artoo_error")
  expect_error(
    artoo_spec(datasets = "not a data frame"),
    class = "artoo_error"
  )

  caught <- tryCatch(read_spec(123), artoo_error = function(e) "caught")
  expect_identical(caught, "caught")

  caught <- tryCatch(
    artoo:::.codec_for_ext("zzz"),
    artoo_condition = function(e) "caught at the root"
  )
  expect_identical(caught, "caught at the root")
})

test_that("glue interpolation resolves in the raising frame", {
  f <- function() {
    path <- "study/ae.xpt"
    artoo:::.artoo_abort("Cannot open {.path {path}}.", kind = "input")
  }
  err <- rlang::catch_cnd(f())
  expect_match(conditionMessage(err), "study/ae.xpt", fixed = TRUE)

  g <- function() {
    n_bad <- 3L
    artoo:::.artoo_warn("{n_bad} value{?s} replaced.", kind = "coercion")
  }
  wrn <- rlang::catch_cnd(g())
  expect_match(conditionMessage(wrn), "3 values", fixed = TRUE)
})
