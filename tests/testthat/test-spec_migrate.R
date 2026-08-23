# Tests for the S7 class migration.
#
# An S7 object embeds a complete copy of its class, so a spec saved by an
# earlier artoo keeps the property set it was built with. That object is a
# ZOMBIE: it passes is_artoo_spec(), class() looks right, old properties
# resolve, and then it dies on the first new one — deep inside user code,
# far from the cause.
#
# The fixture below is the real thing, not a synthetic stand-in: it was saved
# from a spec built while the class still had nine properties, BEFORE the five
# structural slots and the reserved dictionaries table were added. A
# synthesised object would not exercise the same path.

stale_spec <- function() {
  p <- testthat::test_path("fixtures", "spec-pre-phase3.rds")
  skip_if(!file.exists(p), "pre-migration fixture is unavailable")
  readRDS(p)
}

test_that("the fixture really is stale, and fails the way a zombie fails", {
  s <- stale_spec()

  # It gets past every guard...
  expect_true(is_artoo_spec(s))
  expect_s3_class(s, "artoo::artoo_spec")
  expect_gt(nrow(s@datasets), 0L)

  # ...and its embedded class is genuinely behind the live one.
  embedded <- names(S7::prop(attr(s, "S7_class", exact = TRUE), "properties"))
  live <- names(S7::prop(artoo:::artoo_spec_class, "properties"))
  expect_lt(length(embedded), length(live))
  expect_true(artoo:::.spec_stale(s))

  # ...and then it dies on a property added after it was saved. If this stops
  # erroring, the fixture is no longer stale and the whole file is vacuous.
  expect_error(s@standards)
})

test_that("a current spec is not treated as stale", {
  expect_false(artoo:::.spec_stale(sdtm_spec))
  expect_identical(artoo:::.spec_migrate(sdtm_spec), sdtm_spec)
})

test_that("migration rebuilds through the constructor, preserving content", {
  s <- stale_spec()
  m <- suppressMessages(artoo:::.spec_migrate(s))

  expect_identical(
    names(S7::props(m)),
    names(S7::prop(artoo:::artoo_spec_class, "properties"))
  )
  # Content survives untouched.
  expect_identical(m@datasets$dataset, s@datasets$dataset)
  expect_identical(m@variables$variable, s@variables$variable)
  expect_identical(m@standard, s@standard)
})

test_that("a new property arrives as its typed empty table, never NULL", {
  # Stamping attr(x, "S7_class") instead of rebuilding LOOKS like it works --
  # `@` stops erroring -- but S7 applies `default` only at construction, so the
  # new property reads back NULL. Downstream that surfaces as "argument is of
  # length zero" a long way from the cause. Rebuilding is what makes these
  # real, empty, correctly-typed frames.
  m <- suppressMessages(artoo:::.spec_migrate(stale_spec()))
  for (nm in c(
    "standards",
    "where_clauses",
    "method_expressions",
    "arm_displays",
    "arm_results",
    "dictionaries"
  )) {
    prop <- S7::prop(m, nm)
    expect_s3_class(prop, "data.frame")
    expect_identical(nrow(prop), 0L)
    expect_gt(ncol(prop), 0L)
  }
})

test_that("the migrated object satisfies the CURRENT validator", {
  # The point of rebuilding rather than restamping: invariants added after the
  # object was saved are enforced on it, instead of the old validator running
  # silently in their place.
  m <- suppressMessages(artoo:::.spec_migrate(stale_spec()))
  expect_no_error(S7::validate(m))
})

test_that("every accessor migrates transparently", {
  # The guard returns the migrated spec and every call site must consume it.
  # Calling it for side effect only -- which each site did before this change
  # -- silently discards the result and the stale object dies downstream.
  s <- stale_spec()
  expect_no_error(suppressMessages(spec_datasets(s)))
  expect_no_error(suppressMessages(spec_variables(s)))
  expect_no_error(suppressMessages(spec_codelists(s)))
  expect_no_error(suppressMessages(spec_standard(s)))
  expect_identical(suppressMessages(spec_datasets(s)), spec_datasets(sdtm_spec))
})

test_that("write_spec() migrates, rather than admitting a stale spec", {
  # write_spec() used a bare is_artoo_spec() check, which returns TRUE for a
  # zombie -- routing the package's own writer around the migration entirely.
  s <- stale_spec()
  out <- file.path(withr::local_tempdir(), "migrated.json")
  expect_no_error(suppressMessages(write_spec(s, out)))

  back <- read_spec(out)
  expect_identical(
    names(S7::props(back)),
    names(S7::prop(artoo:::artoo_spec_class, "properties"))
  )
  expect_identical(back@datasets$dataset, s@datasets$dataset)
})

test_that("apply_spec() and validate_spec() accept a stale spec", {
  s <- stale_spec()
  expect_no_error(suppressMessages(validate_spec(s)))
})

test_that("the upgrade notice is emitted once per session, not per call", {
  # A script touching a stale spec twenty times should say so once.
  env <- artoo:::.spec_migrate_env
  withr::defer(assign("told", env$told, envir = env))
  assign("told", NULL, envir = env)

  s <- stale_spec()
  expect_message(artoo:::.spec_migrate(s), class = "artoo_message_spec")
  expect_no_message(artoo:::.spec_migrate(s))
})

# ---- the drift guard ----------------------------------------------------

test_that("the bundled specs carry the current property set", {
  # Forgetting to rebuild data/*.rda after a class change is SILENT: the
  # package would ship zombie data and break its own examples. This test is
  # the only thing that catches it, and it must run offline, so it compares
  # against the live class rather than re-deriving from a network source.
  live <- names(S7::prop(artoo:::artoo_spec_class, "properties"))
  expect_identical(names(S7::props(sdtm_spec)), live)
  expect_identical(names(S7::props(adam_spec)), live)
  expect_false(artoo:::.spec_stale(sdtm_spec))
  expect_false(artoo:::.spec_stale(adam_spec))
})

test_that("the bundled specs still match their shipped workbooks", {
  # Offline content check: the .rda and the .xlsx that generated it must still
  # agree, so a rebuild cannot silently change what the package ships.
  skip_if_not_installed("readxl")
  from_xlsx <- read_spec(
    system.file("extdata", "sdtm-spec.xlsx", package = "artoo")
  )
  expect_identical(
    sort(spec_datasets(sdtm_spec)),
    sort(spec_datasets(from_xlsx))
  )
  expect_identical(nrow(sdtm_spec@variables), nrow(from_xlsx@variables))
})

test_that("staleness is decided safely for objects that are not artoo specs", {
  # .spec_stale() runs on whatever reaches the guard, so it must answer FALSE
  # for anything without a readable embedded class rather than erroring.
  expect_false(artoo:::.spec_stale(data.frame(x = 1)))
  expect_false(artoo:::.spec_stale(NULL))

  fake <- structure(list(), S7_class = "not a class object")
  expect_false(artoo:::.spec_stale(fake))
})

test_that("a spec with no standard migrates without inventing one", {
  # `standard` is a scalar that may legitimately be NA. The constructor reads
  # NULL as "unspecified" and NA as a value, so the two must not be conflated.
  expect_null(artoo:::.spec_migrate_standard(NULL))
  expect_null(artoo:::.spec_migrate_standard(NA_character_))
  expect_null(artoo:::.spec_migrate_standard(character(0)))
  expect_identical(artoo:::.spec_migrate_standard("SDTMIG 3.4"), "SDTMIG 3.4")
})
