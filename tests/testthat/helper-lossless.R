# Shared by the round-trip matrix: compare two frames for losslessness.
#
# `expect_lossless(a, b)` asserts value identity, class identity, and
# special-missing tag equivalence per column, and (when both sides carry it)
# artoo_meta column identity. Tag equivalence normalizes the two encodings of
# an ordinary missing — a "." tag and an absent tag mean the same on-disk
# null — so an xpt leg (which re-tags every missing ".") compares equal to a
# json/parquet leg (which carries only non-"." tags).

.norm_tags <- function(col, n) {
  tags <- attr(col, "sas_missing", exact = TRUE)
  if (is.null(tags)) {
    tags <- rep(NA_character_, n)
  }
  tags[!is.na(tags) & tags == "."] <- NA_character_
  tags
}

.strip_tags <- function(col) {
  attr(col, "sas_missing") <- NULL
  col
}

expect_lossless <- function(a, b, via = "", meta = TRUE) {
  lab <- if (nzchar(via)) paste0(" [via ", via, "]") else ""
  expect_identical(names(a), names(b), label = paste0("column names", lab))
  expect_identical(nrow(a), nrow(b), label = paste0("row count", lab))
  for (nm in names(a)) {
    expect_identical(
      .strip_tags(a[[nm]]),
      .strip_tags(b[[nm]]),
      label = paste0("column ", nm, lab)
    )
    expect_identical(
      .norm_tags(a[[nm]], nrow(a)),
      .norm_tags(b[[nm]], nrow(b)),
      label = paste0("sas_missing tags on ", nm, lab)
    )
  }
  if (meta) {
    expect_identical(
      get_meta(a)@columns,
      get_meta(b)@columns,
      label = paste0("meta columns", lab)
    )
  }
  invisible(TRUE)
}

# The torture frame: every CDISC dataType, non-ASCII text, special missings
# on a plain numeric and a temporal column, NA in every column. Conformed via
# its own spec so the metadata carries the full type vocabulary.
.torture_spec <- function() {
  artoo_spec(
    data.frame(dataset = "TT", label = "Torture"),
    data.frame(
      dataset = "TT",
      variable = c(
        "USUBJID",
        "AESEQ",
        "DECVAL",
        "AVAL",
        "DVAL",
        "ABLFL",
        "ADT",
        "ADTM",
        "ATM",
        "REFURI"
      ),
      label = c(
        "Subject ÅÉ", # non-ASCII label
        "Sequence",
        "Decimal",
        "Analysis Value",
        "Double",
        "Baseline Flag",
        "Analysis Date",
        "Analysis Datetime",
        "Analysis Time",
        "Reference URI"
      ),
      data_type = c(
        "string",
        "integer",
        "decimal",
        "float",
        "double",
        "boolean",
        "date",
        "datetime",
        "time",
        "URI"
      ),
      display_format = c(
        NA,
        NA,
        NA,
        NA,
        NA,
        NA,
        "DATE9.",
        "DATETIME20.",
        "TIME8.",
        NA
      ),
      informat = c(NA, NA, NA, NA, NA, NA, "YYMMDD10.", NA, NA, NA),
      stringsAsFactors = FALSE
    )
  )
}

.torture_frame <- function() {
  df <- data.frame(
    USUBJID = c("01-001", "01-ÅÉ2", NA),
    AESEQ = c(1L, 2L, NA),
    DECVAL = c("0.100", "1234.5678901234567", NA),
    AVAL = c(1.5, NA, 3.25),
    DVAL = c(0.1 + 0.2, -1e75, NA),
    ABLFL = c(TRUE, FALSE, NA),
    ADT = as.Date(c("2024-03-01", NA, "2024-03-15")),
    ADTM = as.POSIXct(
      c("2024-03-01 12:34:56", NA, "2024-03-15 23:59:59"),
      tz = "UTC"
    ),
    ATM = hms::hms(c(3600, NA, 86399)),
    REFURI = c("https://x.test/a", NA, "https://x.test/b"),
    stringsAsFactors = FALSE
  )
  attr(df$AVAL, "sas_missing") <- c(NA, ".A", NA)
  attr(df$ADT, "sas_missing") <- c(NA, ".Z", NA)
  suppressWarnings(apply_spec(df, .torture_spec(), "TT", conformance = "off"))
}
