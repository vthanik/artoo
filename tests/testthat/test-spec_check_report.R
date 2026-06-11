# Tests for the artoo_check text report (.format_check).
# The S7 print dispatch only fires in an installed build; the renderer is a
# plain function, so it is snapshot-tested directly here (H12).

fixed_check <- function() {
  findings <- data.frame(
    check = c(
      "variable_method_resolves",
      "method_description_present",
      "variable_label_present"
    ),
    dimension = c("variable", "method", "variable"),
    severity = c("error", "warning", "note"),
    dataset = c("ADSL", NA, "ADSL"),
    variable = c("AGEGR1", "MT.X", "SEX"),
    message = c(
      "Variable ADSL.AGEGR1 references undefined method 'MT.MISSING'.",
      "method_id 'MT.X' has a blank\r\ndescription that spans lines.",
      "Variable ADSL.SEX has no label."
    ),
    stringsAsFactors = FALSE
  )
  artoo:::artoo_check_class(
    findings = findings,
    scope = c("ADSL"),
    study = "CDISCPILOT01",
    summary = list(
      n_datasets = 1L,
      n_variables = 48L,
      n_methods_ref = 5L,
      n_comments_ref = 3L
    )
  )
}

test_that(".format_check renders the sectioned report", {
  expect_snapshot(cat(artoo:::.format_check(fixed_check()), sep = "\n"))
})

test_that("the S7 print and format methods run", {
  # Dispatch fires under an installed build (covr); harmless under load_all.
  expect_no_error(print(fixed_check()))
  expect_no_error(format(fixed_check()))
})

test_that(".format_check collapses newlines in a message (H7)", {
  lines <- artoo:::.format_check(fixed_check())
  joined <- paste(lines, collapse = "\n")
  # The multi-line description is flattened to one line.
  expect_match(joined, "blank description that spans lines", fixed = TRUE)
  expect_no_match(
    grep("MT.X", lines, value = TRUE)[1],
    "\n"
  )
})

test_that(".format_check reports a clean check as no findings", {
  chk <- artoo:::artoo_check_class(
    findings = artoo:::.empty_findings(),
    scope = "ADSL",
    study = "S1"
  )
  lines <- artoo:::.format_check(chk)
  expect_true(any(grepl("No findings", lines)))
})

test_that("a per-section cap truncates with an 'and N more' line", {
  many <- data.frame(
    check = rep("variable_label_present", 20),
    dimension = "variable",
    severity = "note",
    dataset = "ADSL",
    variable = sprintf("V%02d", 1:20),
    message = sprintf("Variable ADSL.V%02d has no label.", 1:20),
    stringsAsFactors = FALSE
  )
  chk <- artoo:::artoo_check_class(
    findings = many,
    scope = "ADSL",
    study = "S1"
  )
  lines <- artoo:::.format_check(chk)
  expect_true(any(grepl("and 5 more", lines)))
})
