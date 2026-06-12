# Tests for columns(): the SAS-viewer-style variable attribute pane on a
# stamped frame, a plain frame, and a file path.

demo_adam_spec <- function() {
  artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
}

demo_sdtm_spec <- function() {
  artoo_spec(
    cdisc_sdtm_datasets,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists
  )
}

test_that("columns() on a stamped frame is one row per variable", {
  spec <- demo_adam_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  pane <- columns(adsl)

  expect_s3_class(pane, "artoo_columns")
  expect_s3_class(pane, "data.frame")
  # Informat is absent: ADSL carries none (shown only when populated).
  expect_identical(
    names(pane),
    c("#", "Variable", "Type", "Len", "Format", "Label", "Key")
  )
  expect_identical(nrow(pane), ncol(adsl))
  expect_identical(pane$Variable, names(adsl))
  expect_identical(pane$`#`, seq_along(adsl))
  # Storage drives Type: USUBJID is Char; AGE is Num.
  expect_identical(pane$Type[pane$Variable == "USUBJID"], "Char")
  expect_identical(pane$Type[pane$Variable == "AGE"], "Num")
  # Labels ride from the spec.
  expect_identical(
    pane$Label[pane$Variable == "AGE"],
    spec_variables(spec, "ADSL")$label[
      spec_variables(spec, "ADSL")$variable == "AGE"
    ]
  )
})

test_that("numeric Len is blank; a Char column always shows a byte Len", {
  # A date variable with no targetDataType is ISO 8601 text (Char) and the
  # spec declares no length: the pane must still show an inferred byte width,
  # not a blank (the RFSTDTC/RFENDTC bug). Numerics show no Len at all.
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = c("USUBJID", "AGE", "RFSTDTC"),
      label = c("Subject", "Age", "Ref Start Date/Time"),
      data_type = c("string", "integer", "date"),
      length = c(11L, 8L, NA_integer_),
      order = 1:3,
      stringsAsFactors = FALSE
    )
  )
  raw <- data.frame(
    USUBJID = c("01-701-1015", "01-701-1023"),
    AGE = c(34L, 56L),
    RFSTDTC = c("2014-01-02", "2014-07-02"),
    stringsAsFactors = FALSE
  )
  pane <- columns(apply_spec(raw, spec, "DM", conformance = "off"))
  # RFSTDTC: Char, no declared length -> inferred byte width (>= 10).
  rf <- pane[pane$Variable == "RFSTDTC", ]
  expect_identical(rf$Type, "Char")
  expect_false(is.na(rf$Len))
  expect_gte(rf$Len, 10L)
  # AGE is numeric -> blank Len; the Len column stays integer-typed.
  expect_true(is.na(pane$Len[pane$Variable == "AGE"]))
  expect_type(pane$Len, "integer")
})

test_that("Format names render uppercase regardless of source spelling", {
  # Define-sourced formats are often lowercase (date9.); the SAS pane shows
  # them uppercase, while the metadata keeps the source spelling.
  spec <- artoo_spec(
    data.frame(dataset = "DM"),
    data.frame(
      dataset = "DM",
      variable = "VISITDT",
      data_type = "date",
      display_format = "date9.",
      order = 1L,
      stringsAsFactors = FALSE
    )
  )
  raw <- data.frame(VISITDT = "2014-01-02", stringsAsFactors = FALSE)
  pane <- columns(apply_spec(raw, spec, "DM", conformance = "off"))
  expect_identical(pane$Format[pane$Variable == "VISITDT"], "DATE9.")
})

test_that("the Informat column appears only when a variable carries one", {
  df <- data.frame(USUBJID = c("A", "B"), stringsAsFactors = FALSE)
  expect_false("Informat" %in% names(columns(df)))
  # An informat present -> the column appears, uppercased.
  attr(df$USUBJID, "informat.sas") <- "date9."
  pane <- columns(df)
  expect_true("Informat" %in% names(pane))
  expect_identical(pane$Informat[pane$Variable == "USUBJID"], "DATE9.")
})

test_that("an undeclared frame column still appears, attrs inferred", {
  spec <- demo_adam_spec()
  raw <- cdisc_adsl
  raw$DERIVED <- seq_len(nrow(raw)) + 0.5
  out <- apply_spec(raw, spec, "ADSL", conformance = "off")
  pane <- columns(out)
  hit <- pane[pane$Variable == "DERIVED", ]
  expect_identical(nrow(hit), 1L)
  expect_identical(hit$Type, "Num")
})

test_that("a plain unstamped data.frame works (all inferred)", {
  df <- data.frame(
    USUBJID = c("01-001", "01-002"),
    AGE = c(34L, 56L),
    stringsAsFactors = FALSE
  )
  pane <- columns(df)
  expect_identical(pane$Variable, c("USUBJID", "AGE"))
  expect_identical(pane$Type, c("Char", "Num"))
})

test_that("columns(path) reads through the codec registry", {
  spec <- demo_adam_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  p <- withr::local_tempfile(fileext = ".json")
  write_json(adsl, p)
  pane <- columns(p)
  expect_identical(pane$Variable, names(adsl))
  # Same attributes as the in-memory pane.
  expect_identical(pane$Label, columns(adsl)$Label)
})

test_that("columns(path) honors member= and inherits the multi-member abort", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p)
  # member= flows through to read_xpt.
  pane <- columns(p, member = "DM")
  expect_identical(pane$Variable, names(dm))
  # A multi-member file without member= aborts with read_xpt's guidance
  # (synthesized second member header at the 80-byte-aligned EOF, exactly
  # as in the xpt codec tests).
  df <- data.frame(SUBJ = c("A", "B"), N = c(1, 2), stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "T"
  p2 <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p2)
  sig <- "HEADER RECORD*******MEMBER  HEADER RECORD!!!!!!!"
  con <- file(p2, "ab")
  writeBin(charToRaw(sprintf("%-80s", sig)), con)
  close(con)
  expect_error(columns(p2), class = "artoo_error_codec")
})

test_that("an unknown path extension aborts via the codec registry", {
  expect_error(columns("spec.docx"), class = "artoo_error_codec")
  expect_snapshot(error = TRUE, columns("spec.docx"))
})

test_that("columns() rejects a non-frame non-path input", {
  expect_error(columns(1L), class = "artoo_error_input")
  expect_error(columns(c("a.xpt", "b.xpt")), class = "artoo_error_input")
})

test_that("the Key column carries the spec keySequence in order", {
  ds <- cdisc_sdtm_datasets
  ds$keys <- NA_character_
  ds$keys[ds$dataset == "DM"] <- "STUDYID USUBJID"
  spec <- artoo_spec(ds, cdisc_sdtm_variables, codelists = cdisc_codelists)
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  pane <- columns(dm)
  expect_identical(pane$Key[pane$Variable == "STUDYID"], 1L)
  expect_identical(pane$Key[pane$Variable == "USUBJID"], 2L)
  expect_true(is.na(pane$Key[pane$Variable == "AGE"]))
})

test_that("a zero-column frame yields the canonical empty pane", {
  pane <- columns(data.frame())
  expect_identical(nrow(pane), 0L)
  # The empty pane omits Informat too (no variable carries one), so the schema
  # is uniform with a populated, informat-free pane.
  expect_identical(
    names(pane),
    c("#", "Variable", "Type", "Len", "Format", "Label", "Key")
  )
})

test_that("print is the left-aligned SAS pane (snapshot)", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  expect_snapshot(print(columns(dm)))
})

test_that("a subset artoo_columns still prints (attrs dropped by `[`)", {
  spec <- demo_sdtm_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", conformance = "off")
  pane <- columns(dm)
  # A 0-row subset (this spec declares no keys) and a populated subset must
  # both format without warnings.
  empty_sub <- pane[!is.na(pane$Key), c("Variable", "Key")]
  expect_identical(nrow(empty_sub), 0L)
  expect_no_warning(out0 <- format(empty_sub))
  expect_match(out0[1], "artoo_columns")

  some_sub <- pane[1:3, c("Variable", "Type")]
  expect_no_warning(out3 <- format(some_sub))
  expect_match(out3[1], "3 variables")
  expect_length(out3, 5L) # header + names row + 3 data rows
})
