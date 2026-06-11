# Tests for the open rule catalog (inst/spec_rules.json) and code parity.

test_that("the rule catalog parses and has the required shape", {
  r <- artoo:::.spec_rules()
  expect_s3_class(r, "data.frame")
  expect_true(all(
    c(
      "id",
      "dimension",
      "severity",
      "requires_data",
      "scope",
      "status",
      "engine"
    ) %in%
      names(r)
  ))
  expect_true(all(r$severity %in% c("error", "warning", "note")))
  expect_true(all(r$engine %in% c("spec", "data")))
  # A data-engine rule cannot run without data.
  expect_false(any(r$engine == "data" & !r$requires_data))
  expect_false(any(duplicated(r$id)))
})

test_that("implemented spec-engine ids exactly match what validate_spec emits", {
  r <- artoo:::.spec_rules()
  implemented <- r$id[r$status == "implemented" & r$engine == "spec"]
  emitted <- artoo:::.engine_check_ids()
  expect_setequal(implemented, emitted)
})

test_that("implemented data-engine ids match the artoo_checks() dimensions", {
  r <- artoo:::.spec_rules()
  data_ids <- r$id[r$status == "implemented" & r$engine == "data"]
  expect_setequal(data_ids, names(formals(artoo_checks)))
})

test_that("every check the engine emits has a valid catalog entry", {
  # .spec_rule() aborts on an unknown id, so this also guards typos.
  for (id in artoo:::.engine_check_ids()) {
    row <- artoo:::.spec_rule(id)
    expect_equal(nrow(row), 1L)
    expect_true(row$severity %in% c("error", "warning", "note"))
  }
})

test_that("the catalog also documents deferred rules (transparency)", {
  r <- artoo:::.spec_rules()
  expect_true(any(r$status == "deferred"))
})

test_that(".check_rules_df rejects a malformed catalog", {
  ok <- data.frame(
    id = "x",
    dimension = "study",
    severity = "warning",
    requires_data = FALSE,
    scope = "scoped",
    status = "implemented",
    engine = "spec",
    stringsAsFactors = FALSE
  )
  expect_invisible(artoo:::.check_rules_df(ok))
  expect_error(
    artoo:::.check_rules_df(ok[, c("id", "dimension")]),
    class = "artoo_error_validation"
  )
  bad_sev <- ok
  bad_sev$severity <- "fatal"
  expect_error(
    artoo:::.check_rules_df(bad_sev),
    class = "artoo_error_validation"
  )
  bad_dim <- ok
  bad_dim$dimension <- "galaxy"
  expect_error(
    artoo:::.check_rules_df(bad_dim),
    class = "artoo_error_validation"
  )
  bad_engine <- ok
  bad_engine$engine <- "quantum"
  expect_error(
    artoo:::.check_rules_df(bad_engine),
    class = "artoo_error_validation"
  )
  # A data-engine rule must require data.
  bad_data <- ok
  bad_data$engine <- "data"
  expect_error(
    artoo:::.check_rules_df(bad_data),
    class = "artoo_error_validation"
  )
  dup <- rbind(ok, ok)
  expect_error(artoo:::.check_rules_df(dup), class = "artoo_error_validation")
})

test_that(".check_rules_df names the offending value in each integrity error", {
  ok <- data.frame(
    id = "x",
    dimension = "study",
    severity = "warning",
    requires_data = FALSE,
    scope = "scoped",
    status = "implemented",
    engine = "spec",
    stringsAsFactors = FALSE
  )
  bad_sev <- ok
  bad_sev$severity <- "fatal"
  expect_error(artoo:::.check_rules_df(bad_sev), "fatal")
  bad_dim <- ok
  bad_dim$dimension <- "galaxy"
  expect_error(artoo:::.check_rules_df(bad_dim), "galaxy")
  bad_engine <- ok
  bad_engine$engine <- "quantum"
  expect_error(artoo:::.check_rules_df(bad_engine), "quantum")
  bad_data <- ok
  bad_data$id <- "no_data_rule"
  bad_data$engine <- "data"
  expect_error(artoo:::.check_rules_df(bad_data), "no_data_rule")
  dup <- rbind(ok, ok)
  expect_error(artoo:::.check_rules_df(dup), "x")

  expect_snapshot(artoo:::.check_rules_df(bad_sev), error = TRUE)
  expect_snapshot(artoo:::.check_rules_df(bad_data), error = TRUE)
  expect_snapshot(artoo:::.check_rules_df(dup), error = TRUE)
})

test_that(".spec_rule aborts on an unknown id", {
  expect_error(
    artoo:::.spec_rule("not_a_real_check"),
    class = "artoo_error_validation"
  )
})
