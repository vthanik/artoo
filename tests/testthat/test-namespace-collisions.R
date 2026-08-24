# One name, one definition.
#
# R sources R/ alphabetically and a later file silently replaces an earlier
# definition of the same name. That has now bitten twice: .define_resolve_version()
# (the reader's, in define_validate.R, shadowed the version profile's) and
# .dx_arm_result() (the reader's, in spec_read_define.R, shadowed the ARM
# writer's, which then received a data frame where it expected an XML node).
# Neither failed at load; both failed at the call site, far from the cause.
#
# Definitions are NOT de-duplicated per file: a name defined twice in ONE
# file is the same silent replacement, and de-duplicating first made exactly
# that case invisible to the guard written for it.

# Every top-level object, not only functions: a list or registry redefined in
# a second file is replaced just as quietly, and .dx_expected_columns and the
# format registry are both of that shape.

test_that("no top-level function is defined twice", {
  files <- list.files(
    testthat::test_path("..", "..", "R"),
    pattern = "[.]R$",
    full.names = TRUE
  )
  skip_if(!length(files), "package source not available")
  defined <- lapply(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    hits <- grep(
      "^[.a-zA-Z][.a-zA-Z0-9_]* *(<-|=) *function",
      lines,
      value = TRUE
    )
    trimws(sub(" *(<-|=) *function.*$", "", hits))
  })
  names(defined) <- basename(files)
  all_names <- unlist(defined, use.names = FALSE)
  duplicated_names <- unique(all_names[duplicated(all_names)])
  where <- vapply(
    duplicated_names,
    function(n) {
      paste(
        names(defined)[vapply(defined, function(d) n %in% d, logical(1))],
        collapse = " + "
      )
    },
    character(1)
  )
  expect_identical(where, stats::setNames(character(0), character(0)))
})

test_that("no top-level non-function object is defined twice", {
  files <- list.files(
    testthat::test_path("..", "..", "R"),
    pattern = "[.]R$",
    full.names = TRUE
  )
  skip_if(!length(files), "package source not available")
  defined <- lapply(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    hits <- grep(
      "^[.a-zA-Z][.a-zA-Z0-9_]* *(<-|=) *(?!function)",
      lines,
      value = TRUE,
      perl = TRUE
    )
    trimws(sub(" *(<-|=).*$", "", hits))
  })
  names(defined) <- basename(files)
  all_names <- unlist(defined, use.names = FALSE)
  duplicated_names <- unique(all_names[duplicated(all_names)])
  where <- vapply(
    duplicated_names,
    function(n) {
      paste(
        names(defined)[vapply(defined, function(d) n %in% d, logical(1))],
        collapse = " + "
      )
    },
    character(1)
  )
  expect_identical(where, stats::setNames(character(0), character(0)))
})
