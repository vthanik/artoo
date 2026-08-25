# Tests for artoo_spec() construction and is_artoo_spec().

test_that("artoo_spec() builds a valid spec from each bundled pair", {
  adam <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
  expect_true(is_artoo_spec(adam))
  expect_setequal(spec_datasets(adam), "ADSL")
  expect_identical(spec_standard(adam), "ADaMIG 1.1")

  sdtm <- artoo_spec(
    cdisc_sdtm_datasets,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists
  )
  expect_setequal(spec_datasets(sdtm), "DM")
  expect_identical(spec_standard(sdtm), "SDTMIG 3.1.2")
})

test_that("mixing the ADaM and SDTM demo tables links each to its own standard (D10)", {
  # This used to abort: everything folded into ONE scalar, so two values
  # meant information loss. Per-row values now survive as standard_id
  # links, the scalar is only the primary, and CDISC's own 2.1 SDTM example
  # names three standards across its datasets.
  spec <- artoo_spec(
    rbind(cdisc_adam_datasets, cdisc_sdtm_datasets),
    rbind(cdisc_adam_variables, cdisc_sdtm_variables),
    codelists = cdisc_codelists
  )
  # A tie is broken by first appearance.
  expect_identical(spec_standard(spec), "ADaMIG 1.1")
  linked <- stats::setNames(
    spec@standards$name[
      match(spec@datasets$standard_id, spec@standards$standard_id)
    ],
    spec@datasets$dataset
  )
  expect_identical(unname(linked[["ADSL"]]), "ADaMIG")
  expect_identical(unname(linked[["DM"]]), "SDTMIG")
})

test_that("artoo_spec() coerces a tibble slot to a plain data frame", {
  skip_if_not_installed("tibble")
  spec <- artoo_spec(
    tibble::tibble(dataset = "DM", label = "Demographics"),
    tibble::tibble(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_s3_class(spec@datasets, "data.frame")
  expect_false(inherits(spec@datasets, "tbl_df"))
})

test_that("artoo_spec() fills missing optional columns with typed NAs", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "AGE", data_type = "integer")
  )
  expect_true("length" %in% names(spec@variables))
  expect_type(spec@variables$length, "integer")
  expect_true(is.na(spec@variables$length))
})

test_that("artoo_spec() canonicalises variable types", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = c("A", "B"),
      data_type = c("text", "float")
    )
  )
  expect_equal(spec@variables$data_type, c("string", "float"))
})

test_that("artoo_spec() requires datasets and variables", {
  expect_error(artoo_spec(), class = "artoo_error_input")
  expect_error(
    artoo_spec(data.frame(dataset = "DM")),
    class = "artoo_error_input"
  )
})

test_that("artoo_spec() aborts on a missing required column", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(variable = "AGE", data_type = "integer") # no `dataset`
    ),
    class = "artoo_error_spec"
  )
})

test_that("artoo_spec() rejects a variable referencing an unknown dataset", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(dataset = "AE", variable = "AETERM", data_type = "string")
    ),
    class = "artoo_error_spec"
  )
})

test_that("artoo_spec() rejects an unresolved codelist reference", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(
        dataset = "DM",
        variable = "SEX",
        data_type = "string",
        codelist_id = "C99999"
      )
    ),
    class = "artoo_error_spec"
  )
})

test_that("artoo_spec() rejects an unknown variable type", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(dataset = "DM", variable = "A", data_type = "widget")
    ),
    class = "artoo_error_type"
  )
})

test_that("is_artoo_spec() is FALSE for non-specs", {
  expect_false(is_artoo_spec(mtcars))
  expect_false(is_artoo_spec(NULL))
})

# ---- single-standard model (@standard) -----------------------------------

test_that("an explicit standard lands on @standard", {
  spec <- artoo_spec(
    data.frame(dataset = "ADSL"),
    data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
    standard = "ADaMIG 1.1"
  )
  expect_identical(spec_standard(spec), "ADaMIG 1.1")
})

test_that("a P21-style datasets$standard column is consumed into @standard", {
  spec <- artoo_spec(
    data.frame(dataset = c("DM", "VS"), standard = "SDTMIG 3.2"),
    data.frame(
      dataset = c("DM", "VS"),
      variable = c("USUBJID", "VSTESTCD"),
      data_type = "string"
    )
  )
  expect_identical(spec_standard(spec), "SDTMIG 3.2")
  expect_false("standard" %in% names(spec@datasets))
})

test_that("a Define-style study$standard field is consumed into @standard", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "USUBJID", data_type = "string"),
    study = data.frame(studyid = "CDISC01", standard = "SDTMIG 3.2")
  )
  expect_identical(spec_standard(spec), "SDTMIG 3.2")
  expect_false("standard" %in% names(spec@study))
  expect_identical(spec_study(spec, "study_name"), "CDISC01")
})

test_that("artoo_spec() canonicalises study fields to the ODM vocabulary", {
  # The P21 Define sheet's verbatim attribute names (StudyName,
  # StudyDescription, ProtocolName) land as the canonical snake_case
  # fields; unknown fields (Language) pass through verbatim.
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "USUBJID", data_type = "string"),
    study = data.frame(
      StudyName = "CDISC01",
      StudyDescription = "A study",
      ProtocolName = "CDISC01-01",
      Language = "en",
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  )
  st <- spec_study(spec)
  expect_identical(st$study_name, "CDISC01")
  expect_identical(st$study_description, "A study")
  expect_identical(st$protocol_name, "CDISC01-01")
  # Language is canonicalised too now, along with the rest of the document
  # identifiers a study sheet carries.
  expect_identical(st$language, "en")
  expect_false(any(
    c("StudyName", "StudyDescription", "ProtocolName", "Language") %in%
      names(st)
  ))
})

test_that("artoo_spec() accepts studyid as a study_name alias", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "USUBJID", data_type = "string"),
    study = data.frame(studyid = "CDISCPILOT01", stringsAsFactors = FALSE)
  )
  expect_identical(spec_study(spec, "study_name"), "CDISCPILOT01")
  expect_false("studyid" %in% names(spec_study(spec)))
})

test_that("agreeing study-name aliases collapse to the one value", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "USUBJID", data_type = "string"),
    study = data.frame(
      studyid = "CDISC01",
      StudyName = "CDISC01",
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  )
  expect_identical(spec_study(spec, "study_name"), "CDISC01")
})

test_that("conflicting study-name fields abort at construction", {
  expect_error(
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(dataset = "DM", variable = "USUBJID", data_type = "string"),
      study = data.frame(
        studyid = "CDISC01",
        StudyName = "OTHER",
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
    ),
    class = "artoo_error_spec"
  )
  expect_snapshot(
    error = TRUE,
    artoo_spec(
      data.frame(dataset = "DM"),
      data.frame(dataset = "DM", variable = "USUBJID", data_type = "string"),
      study = data.frame(
        studyid = "CDISC01",
        StudyName = "OTHER",
        stringsAsFactors = FALSE,
        check.names = FALSE
      )
    )
  )
})

test_that("agreeing sources resolve to the one standard", {
  spec <- artoo_spec(
    data.frame(dataset = "ADSL", standard = "ADaMIG 1.1"),
    data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
    study = data.frame(standard = "ADaMIG 1.1"),
    standard = "ADaMIG 1.1"
  )
  expect_identical(spec_standard(spec), "ADaMIG 1.1")
})

test_that("mixing standards mints a row for each and links the datasets (D10)", {
  spec <- artoo_spec(
    data.frame(
      dataset = c("ADSL", "AE", "DM"),
      standard = c("ADaMIG 1.1", "SDTMIG 3.2", "SDTMIG 3.2")
    ),
    data.frame(
      dataset = c("ADSL", "AE", "DM"),
      variable = c("AGE", "AETERM", "USUBJID"),
      data_type = c("integer", "string", "string")
    )
  )
  # The scalar is the value the most datasets name...
  expect_identical(spec_standard(spec), "SDTMIG 3.2")
  # ...and every row resolves through its own minted standards entry.
  expect_identical(nrow(spec@standards), 2L)
  expect_true(all(spec@datasets$standard_id %in% spec@standards$standard_id))
  expect_setequal(spec@standards$name, c("ADaMIG", "SDTMIG"))
  # The display column is consumed; standard_id is its durable form.
  expect_false("standard" %in% names(spec@datasets))
})

test_that("an explicit standard contradicting the source aborts (D10)", {
  # A file describing several standards is data; an ARGUMENT naming one the
  # file never mentions is the caller contradicting the file.
  expect_error(
    artoo_spec(
      data.frame(dataset = "ADSL", standard = "ADaMIG 1.1"),
      data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
      standard = "SDTMIG 3.2"
    ),
    class = "artoo_error_spec"
  )
  expect_snapshot(
    error = TRUE,
    artoo_spec(
      data.frame(dataset = "ADSL", standard = "ADaMIG 1.1"),
      data.frame(dataset = "ADSL", variable = "AGE", data_type = "integer"),
      standard = "SDTMIG 3.2"
    )
  )
})

test_that("no standard anywhere resolves to NA", {
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(dataset = "DM", variable = "USUBJID", data_type = "string")
  )
  expect_identical(spec_standard(spec), NA_character_)
})

test_that("blank and NA standards are ignored during resolution", {
  spec <- artoo_spec(
    data.frame(dataset = c("DM", "VS"), standard = c("SDTMIG 3.2", NA)),
    data.frame(
      dataset = c("DM", "VS"),
      variable = c("USUBJID", "VSTESTCD"),
      data_type = "string"
    ),
    study = data.frame(standard = "  ")
  )
  expect_identical(spec_standard(spec), "SDTMIG 3.2")
})

test_that("an inline method expression folds in beside the formal ones", {
  # `.fold_method_expressions()` turns a method's inline `expression_code`
  # into a method_expressions row. Three of its four exits had no test: no
  # code at all, code for a method that already has a formal expression, and
  # stacking onto an existing table.
  f <- artoo:::.fold_method_expressions

  methods <- data.frame(
    method_id = c("ME.1", "ME.2"),
    name = "M",
    description = "d",
    expression_context = "SAS",
    expression_code = c("x = 1;", NA_character_),
    stringsAsFactors = FALSE
  )

  # Nothing to fold: no method carries code.
  blank <- methods
  blank$expression_code <- NA_character_
  expect_null(f(blank, NULL))

  # Folded from nothing.
  out <- f(methods, NULL)
  expect_identical(out$method_id, "ME.1")
  expect_identical(out$code, "x = 1;")

  # A method that already has a formal expression is left alone, not doubled.
  formal <- data.frame(
    method_id = "ME.1",
    order = 1L,
    context = "SAS",
    code = "formal;",
    stringsAsFactors = FALSE
  )
  expect_identical(f(methods, formal), formal)

  # And an inline one for a DIFFERENT method stacks onto the table.
  methods2 <- methods
  methods2$expression_code <- c("x = 1;", "y = 2;")
  stacked <- f(methods2, formal)
  expect_identical(nrow(stacked), 2L)
  expect_setequal(stacked$method_id, c("ME.1", "ME.2"))
})

test_that("a primary standard is minted only from a versioned IG name", {
  # Four exits, none tested: no standards table, a blank standard, a standard
  # with no version, and a name that is not an implementation guide.
  f <- artoo:::.mint_primary_standard
  empty <- data.frame(standard_id = character(0), stringsAsFactors = FALSE)

  expect_identical(f(empty, NA_character_), empty)
  expect_identical(f(empty, ""), empty)
  expect_identical(f(empty, "SDTMIG"), empty)
  expect_identical(f(empty, "Something Else 1.0"), empty)

  minted <- f(empty, "SDTMIG 3.4")
  expect_identical(minted$standard_id, "STD.1")
})
