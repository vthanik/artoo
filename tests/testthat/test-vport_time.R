# Tests for the vport_time S3 class: a clock-time-of-day value (seconds
# since midnight) that renders HH:MM:SS in the Positron/RStudio viewer and
# round-trips losslessly to its underlying seconds.

test_that("constructor coerces to double and tags the class", {
  t <- vport_time(c(0, 3600, 86399))
  expect_true(is_vport_time(t))
  expect_type(unclass(t), "double")
  expect_identical(unclass(t), c(0, 3600, 86399))
})

test_that("is_vport_time is FALSE for other objects", {
  expect_false(is_vport_time(1L))
  expect_false(is_vport_time(Sys.Date()))
  expect_false(is_vport_time("08:00:00"))
})

test_that("format renders HH:MM:SS, NA, and times past 24h", {
  t <- vport_time(c(0, 30600, 50700, 86399, NA, 90000))
  expect_identical(
    format(t),
    c("00:00:00", "08:30:00", "14:05:00", "23:59:59", NA, "25:00:00")
  )
})

test_that("format renders negative (elapsed) times with a sign", {
  expect_identical(format(vport_time(-3600)), "-01:00:00")
})

test_that("as.character matches format", {
  t <- vport_time(c(0, 3661))
  expect_identical(as.character(t), c("00:00:00", "01:01:01"))
})

test_that("print is stable", {
  expect_snapshot(print(vport_time(c(0, 30600, NA))))
})

test_that("subsetting preserves the class", {
  t <- vport_time(c(10, 20, 30))
  expect_true(is_vport_time(t[2:3]))
  expect_identical(unclass(t[2:3]), c(20, 30))
  expect_true(is_vport_time(t[[1]]))
})

test_that("c and rep preserve the class", {
  a <- vport_time(c(1, 2))
  b <- vport_time(3)
  expect_identical(unclass(c(a, b)), c(1, 2, 3))
  expect_true(is_vport_time(c(a, b)))
  expect_identical(unclass(rep(b, 3)), c(3, 3, 3))
  expect_true(is_vport_time(rep(b, 3)))
})

test_that("a vport_time survives as a data.frame column", {
  df <- data.frame(
    id = 1:3,
    tm = vport_time(c(0, 30600, 86399))
  )
  expect_true(is_vport_time(df$tm))
  expect_identical(format(df$tm)[2], "08:30:00")
})

test_that("ordering and sorting work via xtfrm", {
  t <- vport_time(c(30, 10, 20))
  expect_identical(order(t), c(2L, 3L, 1L))
  expect_identical(unclass(sort(t)), c(10, 20, 30))
})

test_that("comparison operators work via Ops", {
  a <- vport_time(100)
  b <- vport_time(200)
  expect_true(a < b)
  expect_true(b >= a)
  expect_false(a == b)
})

test_that("min/max/range return vport_time via Summary", {
  t <- vport_time(c(30, 10, 20))
  expect_true(is_vport_time(min(t)))
  expect_identical(unclass(min(t)), 10)
  expect_identical(unclass(max(t)), 30)
  expect_identical(unclass(range(t)), c(10, 30))
})

test_that("NA is detected natively", {
  t <- vport_time(c(1, NA, 3))
  expect_identical(is.na(t), c(FALSE, TRUE, FALSE))
})

test_that("the constructor is idempotent", {
  t <- vport_time(c(1, 2))
  expect_identical(vport_time(t), t)
})

test_that("c aborts when combining with a non-numeric", {
  expect_error(
    c(vport_time(1), "noon"),
    class = "vport_error_input"
  )
})

test_that("arithmetic returns vport_time; unary minus negates", {
  a <- vport_time(100)
  b <- vport_time(40)
  expect_true(is_vport_time(a - b))
  expect_identical(unclass(a - b), 60)
  expect_identical(unclass(-a), -100)
})

test_that("sum returns the total seconds (not a clock time)", {
  expect_identical(sum(vport_time(c(10, 20, 30))), 60)
})
