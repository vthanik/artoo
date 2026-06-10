# Tests for the open rule catalog (inst/spec_rules.json) and code parity.

test_that("the rule catalog parses and has the required shape", {
  skip_if_not_installed("jsonlite")
  r <- vport:::.spec_rules()
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
  skip_if_not_installed("jsonlite")
  r <- vport:::.spec_rules()
  implemented <- r$id[r$status == "implemented" & r$engine == "spec"]
  emitted <- vport:::.engine_check_ids()
  expect_setequal(implemented, emitted)
})

test_that("implemented data-engine ids match the vport_checks() dimensions", {
  skip_if_not_installed("jsonlite")
  r <- vport:::.spec_rules()
  data_ids <- r$id[r$status == "implemented" & r$engine == "data"]
  expect_setequal(data_ids, names(formals(vport_checks)))
})

test_that("every check the engine emits has a valid catalog entry", {
  skip_if_not_installed("jsonlite")
  # .spec_rule() aborts on an unknown id, so this also guards typos.
  for (id in vport:::.engine_check_ids()) {
    row <- vport:::.spec_rule(id)
    expect_equal(nrow(row), 1L)
    expect_true(row$severity %in% c("error", "warning", "note"))
  }
})

test_that("the catalog also documents deferred rules (transparency)", {
  skip_if_not_installed("jsonlite")
  r <- vport:::.spec_rules()
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
  expect_invisible(vport:::.check_rules_df(ok))
  expect_error(
    vport:::.check_rules_df(ok[, c("id", "dimension")]),
    class = "vport_error_validation"
  )
  bad_sev <- ok
  bad_sev$severity <- "fatal"
  expect_error(
    vport:::.check_rules_df(bad_sev),
    class = "vport_error_validation"
  )
  bad_dim <- ok
  bad_dim$dimension <- "galaxy"
  expect_error(
    vport:::.check_rules_df(bad_dim),
    class = "vport_error_validation"
  )
  bad_engine <- ok
  bad_engine$engine <- "quantum"
  expect_error(
    vport:::.check_rules_df(bad_engine),
    class = "vport_error_validation"
  )
  # A data-engine rule must require data.
  bad_data <- ok
  bad_data$engine <- "data"
  expect_error(
    vport:::.check_rules_df(bad_data),
    class = "vport_error_validation"
  )
  dup <- rbind(ok, ok)
  expect_error(vport:::.check_rules_df(dup), class = "vport_error_validation")
})

test_that(".spec_rule aborts on an unknown id", {
  expect_error(
    vport:::.spec_rule("not_a_real_check"),
    class = "vport_error_validation"
  )
})
