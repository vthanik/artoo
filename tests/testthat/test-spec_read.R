# Tests for read_spec() (native JSON + Pinnacle 21 Excel).

# ---- Native JSON round-trip (F1) ----------------------------------------

test_that("read_spec() round-trips a spec through JSON identically (F1)", {
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  expect_identical(read_spec(p), spec)
})

test_that("read_spec() round-trips value-level and study slots (F1)", {
  vlm <- data.frame(
    dataset = "ADSL",
    variable = "PARAMCD",
    where_clause = "PARAMCD EQ HEIGHT",
    label = "Height",
    stringsAsFactors = FALSE
  )
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists,
    study = data.frame(studyid = "CDISCPILOT01"),
    values = vlm
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  back <- read_spec(p)
  expect_identical(back, spec)
  expect_s3_class(back@values, "data.frame")
})

test_that("artoo_spec() demotes a tibble value-level table to plain df (H2)", {
  skip_if_not_installed("tibble")
  vlm <- tibble::tibble(dataset = "ADSL", variable = "PARAMCD", label = "L")
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists,
    values = vlm
  )
  expect_s3_class(spec@values, "data.frame")
  expect_false(inherits(spec@values, "tbl_df"))
})

test_that("read_spec() preserves non-ASCII labels and empty strings (H8)", {
  vars <- data.frame(
    dataset = "DM",
    variable = c("A", "B"),
    data_type = c("string", "string"),
    label = c("Naïve label", ""),
    stringsAsFactors = FALSE
  )
  spec <- artoo_spec(data.frame(dataset = "DM"), vars)
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  back <- read_spec(p)
  lbl <- back@variables$label
  expect_identical(lbl[back@variables$variable == "A"], "Naïve label")
  expect_identical(lbl[back@variables$variable == "B"], "")
})

test_that("read_spec() reconstructs empty optional slots", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  back <- read_spec(p)
  expect_identical(back, spec)
  expect_null(back@values)
  expect_equal(nrow(back@codelists), 0L)
})

test_that("read_spec() warns on an unrecognised version but still reads (H10)", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  txt <- gsub(
    '("artoo_spec_version":\\s*)"1"',
    '\\1"99"',
    readLines(p)
  )
  writeLines(txt, p)
  expect_warning(s <- read_spec(p), class = "artoo_warning_spec")
  expect_true(is_artoo_spec(s))
})

test_that("read_spec() rejects bad paths and unsupported extensions", {
  expect_error(read_spec(42), class = "artoo_error_input")
  expect_error(read_spec("does-not-exist.json"), class = "artoo_error_input")
  tmp <- withr::local_tempfile(fileext = ".csv")
  file.create(tmp)
  expect_error(read_spec(tmp), class = "artoo_error_input")
  expect_snapshot(read_spec(tmp), error = TRUE)
})

# ---- Pinnacle 21 Excel (integration, committed fixture) -----------------

test_that("read_spec() ingests a P21 Excel spec with merged cells", {
  skip_if_not_installed("readxl")
  spec <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))
  expect_true(is_artoo_spec(spec))
  expect_setequal(spec_datasets(spec), c("ADSL", "DM"))

  v <- spec_variables(spec)
  # H4: the merged Dataset column is forward-filled to continuation rows.
  expect_identical(v$dataset[v$variable == "AGE"], "ADSL")
  expect_identical(
    unique(v$dataset[v$variable == "USUBJID" & v$dataset == "DM"]),
    "DM"
  )
  # H1: a Define-XML partialDatetime canonicalises to datetime.
  expect_identical(v$data_type[v$variable == "TRTSDTM"], "datetime")
  # H6: a space-padded codelist id is trimmed and resolves.
  expect_identical(
    v$codelist_id[v$variable == "SEX" & v$dataset == "ADSL"],
    "C66731"
  )
  # Mandatory "Yes" coerces to TRUE.
  expect_true(v$mandatory[v$variable == "STUDYID"][1])
})

test_that("read_spec() recovers all terms of a merged-id codelist (H4/H5)", {
  skip_if_not_installed("readxl")
  spec <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))
  cl <- spec_codelists(spec, "C66731")
  expect_setequal(cl$term, c("F", "M", "U"))
  expect_setequal(cl$decode, c("Female", "Male", "Unknown"))
})

test_that("read_spec() populates methods/comments/documents slots", {
  skip_if_not_installed("readxl")
  spec <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))
  # Trailing blank-key method row is dropped (H4): MT.TRTSDTM + MT.DM only.
  expect_setequal(spec_methods(spec)$method_id, c("MT.TRTSDTM", "MT.DM"))
  expect_identical(spec_comments(spec)$comment_id, "C.BLANK")
  expect_identical(spec_documents(spec)$document_id, "DOC.SAP")
  # FK columns mapped onto variables.
  v <- spec_variables(spec)
  expect_identical(v$method_id[v$variable == "TRTSDTM"], "MT.TRTSDTM")
  expect_identical(
    v$method_id[v$variable == "USUBJID" & v$dataset == "DM"],
    "MT.DM"
  )
  # The DM method carries a blank description (a crafted defect).
  m <- spec_methods(spec)
  expect_true(is.na(m$description[m$method_id == "MT.DM"]))
})

test_that("read_spec() round-trips the new slots through JSON (F1)", {
  spec <- artoo_spec(
    data.frame(dataset = "ADSL"),
    data.frame(
      dataset = "ADSL",
      variable = "AGEGR1",
      data_type = "string",
      method_id = "MT.AGEGR1",
      stringsAsFactors = FALSE
    ),
    methods = data.frame(
      method_id = "MT.AGEGR1",
      description = "Age group from AGE.",
      stringsAsFactors = FALSE
    ),
    comments = data.frame(
      comment_id = "C1",
      description = "A note.",
      stringsAsFactors = FALSE
    ),
    documents = data.frame(
      document_id = "SAP",
      title = "SAP",
      href = "sap.pdf",
      stringsAsFactors = FALSE
    )
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  expect_identical(read_spec(p), spec)
})

test_that("read_spec() pivots the P21 Define sheet into a study row", {
  skip_if_not_installed("readxl")
  spec <- read_spec(test_path("fixtures", "p21_adam_spec.xlsx"))
  expect_identical(spec_study(spec, "StudyName"), "CDISCPILOT01")
})

# ---- P21 internals (fast unit tests of the hardening branches) ----------

test_that(".match_p21_sheet resolves spelling and spacing variants (H3)", {
  al <- artoo:::.p21_sheet_aliases$variables
  expect_identical(
    artoo:::.match_p21_sheet("Variable Level Metadata", al),
    "Variable Level Metadata"
  )
  expect_identical(artoo:::.match_p21_sheet("VARIABLES", al), "VARIABLES")
  expect_null(artoo:::.match_p21_sheet("Datasets", al))
})

test_that(".fill_down leaves a leading NA, and .check_filled fails loud (H4)", {
  df <- data.frame(
    dataset = c(NA, "ADSL", NA),
    variable = c("A", "B", "C"),
    stringsAsFactors = FALSE
  )
  filled <- artoo:::.fill_down(df, "dataset")
  expect_identical(filled$dataset, c(NA, "ADSL", "ADSL"))
  expect_error(
    artoo:::.check_filled(filled, "dataset", "Variables", rlang::current_env()),
    class = "artoo_error_spec"
  )
})

test_that(".require_p21_sheet errors on an absent or empty required sheet (H7)", {
  expect_error(
    artoo:::.require_p21_sheet(
      NULL,
      NULL,
      "Datasets",
      "X",
      rlang::current_env()
    ),
    class = "artoo_error_spec"
  )
  expect_error(
    artoo:::.require_p21_sheet(
      data.frame(),
      "Datasets",
      "Datasets",
      "Datasets",
      rlang::current_env()
    ),
    class = "artoo_error_spec"
  )
})

# ---- .match_p21_sheet alias resolution ----------------------------------

test_that(".match_p21_sheet informs when several sheets match one role", {
  expect_message(
    used <- artoo:::.match_p21_sheet(c("Datasets", "datasets "), "datasets"),
    class = "artoo_message_p21_sheet"
  )
  # The first match wins; the inform names it.
  expect_identical(used, "Datasets")
  expect_snapshot(
    invisible(artoo:::.match_p21_sheet(c("Datasets", "datasets "), "datasets"))
  )
})

test_that(".match_p21_sheet returns NULL when nothing matches", {
  expect_null(artoo:::.match_p21_sheet(c("Foo", "Bar"), "datasets"))
})

test_that(".match_p21_sheet on a single match is silent", {
  expect_no_message(
    used <- artoo:::.match_p21_sheet(c("Variables", "Datasets"), "datasets")
  )
  expect_identical(used, "Datasets")
})

# ---- datasets = scoping + on_duplicate (read-time hardening) ----------------

test_that("read_spec(datasets=) scopes a native JSON spec to one dataset", {
  # The bundled SDTM spec spans four datasets (one standard), so scoping
  # to DM genuinely narrows it.
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(sdtm_spec, p)
  dm_only <- read_spec(p, datasets = "DM")
  expect_identical(spec_datasets(dm_only), "DM")
  expect_identical(unique(spec_variables(dm_only)$dataset), "DM")
})

test_that("read_spec(datasets=) rejects an unknown dataset, listing what exists", {
  spec <- artoo_spec(
    cdisc_sdtm_datasets,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_spec(spec, p)
  expect_error(read_spec(p, datasets = "ADAE"), class = "artoo_error_input")
  expect_snapshot(error = TRUE, read_spec(p, datasets = "ADAE"))
  expect_error(read_spec(p, datasets = 1L), class = "artoo_error_input")
})

test_that("read_spec(datasets=) scopes a P21 workbook", {
  skip_if_not_installed("readxl")
  p <- test_path("fixtures", "p21_adam_spec.xlsx")
  suppressMessages(dm_only <- read_spec(p, datasets = "DM"))
  expect_identical(spec_datasets(dm_only), "DM")
})

# A native JSON spec with one variable defined twice (hand-built: the
# artoo_spec() constructor itself refuses duplicates, which is the point).
.dup_spec_json <- function() {
  # The bundled SDTM spec spans four domains, so a duplicate confined to DM
  # can coexist with clean domains for the scoping test below.
  p <- withr::local_tempfile(fileext = ".json", .local_envir = parent.frame())
  write_spec(sdtm_spec, p)
  raw <- jsonlite::fromJSON(p, simplifyDataFrame = TRUE)
  v <- raw$variables
  dup <- v[v$dataset == "DM" & v$variable == "SEX", , drop = FALSE]
  raw$variables <- rbind(v, dup)
  jsonlite::write_json(raw, p, auto_unbox = TRUE, null = "null", na = "null")
  p
}

test_that("a duplicated variable aborts at read with its row locations", {
  p <- .dup_spec_json()
  expect_error(read_spec(p), class = "artoo_error_spec")
  err <- tryCatch(read_spec(p), error = function(e) conditionMessage(e))
  # The message names the locations and the offending variable.
  expect_match(paste(err, collapse = " "), "DM.SEX")
  expect_match(paste(err, collapse = " "), "rows")
})

test_that("on_duplicate = 'first' keeps the first definition", {
  p <- .dup_spec_json()
  spec <- suppressMessages(read_spec(p, on_duplicate = "first"))
  v <- spec_variables(spec, "DM")
  expect_identical(sum(v$variable == "SEX"), 1L)
})

test_that("on_duplicate = 'warn' keeps the first definition and warns", {
  p <- .dup_spec_json()
  expect_warning(
    spec <- read_spec(p, on_duplicate = "warn"),
    class = "artoo_warning_spec"
  )
  expect_identical(sum(spec_variables(spec, "DM")$variable == "SEX"), 1L)
})

test_that("scoping runs before the duplicate guard (broken domain elsewhere)", {
  # The dogfood scenario: a duplicate confined to one domain must not block
  # reading a different, clean domain.
  p <- .dup_spec_json() # duplicate lives in DM
  vs_only <- read_spec(p, datasets = "VS")
  expect_identical(spec_datasets(vs_only), "VS")
})

test_that(".resolve_duplicate_variables reports source rows (Excel-style)", {
  vars <- data.frame(
    dataset = c("ADCM", "ADCM", "ADCM"),
    variable = c("STUDYID", "TRTP", "STUDYID"),
    stringsAsFactors = FALSE
  )
  err <- tryCatch(
    artoo:::.resolve_duplicate_variables(
      vars,
      "error",
      where = "Sheet 'Variables'",
      rows = c(276L, 277L, 280L)
    ),
    error = function(e) conditionMessage(e)
  )
  expect_match(
    paste(err, collapse = " "),
    "Sheet 'Variables' rows 276 and 280 all define ADCM.STUDYID",
    fixed = TRUE
  )
})
