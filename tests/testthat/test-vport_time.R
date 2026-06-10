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

# ---- Wave 2: assignment guards, combine, summary, Ops, fractional -----------

test_that("[<- with a numeric or vport_time RHS keeps the class", {
  t <- vport_time(c(10, 20, 30))
  t[2] <- 99
  expect_true(is_vport_time(t))
  expect_identical(unclass(t), c(10, 99, 30))
  t[3] <- vport_time(40)
  expect_identical(unclass(t), c(10, 99, 40))
})

test_that("[<- accepts a logical NA RHS (blank a slot)", {
  t <- vport_time(c(10, 20))
  t[1] <- NA
  expect_true(is_vport_time(t))
  expect_identical(is.na(t), c(TRUE, FALSE))
})

test_that("[<- aborts on a character RHS (no silent corruption)", {
  t <- vport_time(c(10, 20))
  expect_error(
    {
      t[1] <- "noon"
    },
    class = "vport_error_input"
  )
})

test_that("[[<- guards the RHS type like [<-", {
  t <- vport_time(c(10, 20))
  t[[1]] <- 5
  expect_identical(unclass(t), c(5, 20))
  expect_error(
    {
      t[[2]] <- "noon"
    },
    class = "vport_error_input"
  )
})

test_that("c accepts a logical NA element", {
  out <- c(vport_time(c(1, 2)), NA)
  expect_true(is_vport_time(out))
  expect_identical(is.na(out), c(FALSE, FALSE, TRUE))
})

test_that("unique and mean keep the class", {
  t <- vport_time(c(10, 10, 20))
  expect_true(is_vport_time(unique(t)))
  expect_identical(unclass(unique(t)), c(10, 20))
  expect_true(is_vport_time(mean(t)))
  expect_identical(unclass(mean(vport_time(c(10, 20)))), 15)
})

test_that("modulo and integer-divide preserve the class (day wrap)", {
  t <- vport_time(90000) # 25:00:00
  wrapped <- t %% 86400
  expect_true(is_vport_time(wrapped))
  expect_identical(unclass(wrapped), 3600)
  expect_true(is_vport_time(t %/% 2))
})

test_that("comparison with a character value aborts (review)", {
  t <- vport_time(30600)
  expect_error(t == "08:30:00", class = "vport_error_input")
  expect_error("08:30:00" == t, class = "vport_error_input")
  # numeric and NA comparisons stay legal
  expect_true(t == 30600)
  expect_true(is.na(t == NA))
})

test_that("format renders fractional seconds (hms convention)", {
  expect_identical(format(vport_time(30600.5)), "08:30:00.5")
  expect_identical(
    format(vport_time(c(30600, 30600.25))),
    c(
      "08:30:00",
      "08:30:00.25"
    )
  )
  expect_identical(format(vport_time(-3600.5)), "-01:00:00.5")
})

# ---- review 2026-06: S3 dispatch must work outside the namespace ------------

test_that("the namespace holds no local print/format bindings (review B1)", {
  # S7::method(print, ...)<- on a base generic creates a local `print` binding
  # in the package namespace, which hijacks S3 registration of every plain
  # *.vport_time method: registerS3methods then registers them into vport's
  # own methods table instead of base's, and user-facing dispatch dies.
  ns <- asNamespace("vport")
  expect_false(exists("print", envir = ns, inherits = FALSE))
  expect_false(exists("format", envir = ns, inherits = FALSE))
})

test_that("format/print dispatch for vport_time from outside the namespace (review B1)", {
  # In-namespace tests find format.vport_time lexically even when registration
  # is broken; evaluate from an environment that does NOT chain into vport.
  e <- new.env(parent = baseenv())
  e$t <- vport_time(c(30600, NA))
  expect_identical(eval(quote(format(t)), e), c("08:30:00", NA))
  expect_output(eval(quote(print(t)), e), "<vport_time\\[2\\]>")
})
