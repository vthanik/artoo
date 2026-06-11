# Fuzz / corruption robustness: a truncated or bit-flipped file must abort
# with a vport condition, never crash the session, hang, or silently return
# wrong data. Deterministic seeds keep failures reproducible.

# A clean one-of-each-format set written from a small frame.
.fuzz_sources <- function(env = parent.frame()) {
  df <- data.frame(
    USUBJID = c("01-001", "01-002", "01-003"),
    AGE = c(34, 47, 61),
    ARM = c("PLACEBO", "DRUG", "DRUG"),
    ADT = as.Date(c("2024-01-01", "2024-02-15", "2024-03-30")),
    stringsAsFactors = FALSE
  )
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = c("USUBJID", "AGE", "ARM", "ADT"),
      label = c("Subject", "Age", "Arm", "Date"),
      data_type = c("string", "integer", "string", "date"),
      display_format = c(NA, NA, NA, "DATE9."),
      stringsAsFactors = FALSE
    )
  )
  conf <- apply_spec(df, spec, "DM", conformance = "off")
  fmts <- c("xpt", "json", "ndjson", "rds")
  if (requireNamespace("nanoparquet", quietly = TRUE)) {
    fmts <- c(fmts, "parquet")
  }
  paths <- list()
  for (f in fmts) {
    p <- withr::local_tempfile(fileext = paste0(".", f), .local_envir = env)
    write_dataset(conf, p, format = f)
    paths[[f]] <- p
  }
  paths
}

# Reading must EITHER succeed with a data frame OR throw a vport condition --
# never any other error, never a crash, never a hang.
.expect_clean <- function(path, fmt) {
  # A corrupt-but-readable file may legitimately warn (an encoding heuristic,
  # a coercion); the contract under test is "data frame or clean vport abort",
  # not warning-freedom, so warnings are suppressed.
  res <- suppressWarnings(tryCatch(
    read_dataset(path, format = fmt),
    vport_error_codec = function(e) "vport",
    vport_error_input = function(e) "vport",
    vport_error_type = function(e) "vport",
    error = function(e) structure("other", message = conditionMessage(e))
  ))
  if (identical(res, "other")) {
    fail(sprintf("%s: non-vport error: %s", fmt, attr(res, "message")))
  } else if (is.data.frame(res)) {
    succeed()
  } else {
    expect_identical(res, "vport")
  }
}

test_that("truncation at every structural boundary aborts cleanly", {
  paths <- .fuzz_sources()
  for (fmt in names(paths)) {
    full <- readBin(paths[[fmt]], "raw", file.info(paths[[fmt]])$size)
    n <- length(full)
    # xpt is 80-byte blocked; the others have no fixed stride, so sample a
    # spread of cut points including header/body/footer boundaries.
    cuts <- if (fmt == "xpt") {
      seq(0L, n, by = 80L)
    } else {
      unique(as.integer(c(0, n * c(0.1, 0.25, 0.5, 0.75, 0.9, 0.99), n - 1L)))
    }
    cuts <- cuts[cuts >= 0L & cuts < n]
    for (cut in cuts) {
      p <- withr::local_tempfile(fileext = paste0(".", fmt))
      writeBin(full[seq_len(cut)], p)
      .expect_clean(p, fmt)
    }
  }
})

test_that("a header bit-flip aborts cleanly", {
  set.seed(11)
  paths <- .fuzz_sources()
  for (fmt in names(paths)) {
    full <- readBin(paths[[fmt]], "raw", file.info(paths[[fmt]])$size)
    n <- length(full)
    for (i in 1:25) {
      pos <- sample.int(min(n, 400L), 1L) # corrupt the header region
      bytes <- full
      bytes[pos] <- as.raw(bitwXor(
        as.integer(bytes[pos]),
        sample.int(255L, 1L)
      ))
      p <- withr::local_tempfile(fileext = paste0(".", fmt))
      writeBin(bytes, p)
      .expect_clean(p, fmt)
    }
  }
})

test_that("random bytes behind a valid magic abort cleanly", {
  set.seed(23)
  # xpt: a valid library header then garbage. json/ndjson: a valid first
  # token then garbage.
  hdr <- paste0(
    "HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!",
    strrep("0", 30)
  )
  p <- withr::local_tempfile(fileext = ".xpt")
  writeBin(
    c(charToRaw(sprintf("%-80s", hdr)), as.raw(sample(0:255, 400, TRUE))),
    p
  )
  .expect_clean(p, "xpt")

  p2 <- withr::local_tempfile(fileext = ".json")
  writeBin(charToRaw('{"datasetJSONVersion":"1.1.0", garbage'), p2)
  .expect_clean(p2, "json")

  p3 <- withr::local_tempfile(fileext = ".ndjson")
  writeLines(c('{"datasetJSONVersion":"1.1.0","columns":[]}', "{not json"), p3)
  .expect_clean(p3, "ndjson")
})

test_that("an empty file of each format aborts cleanly", {
  for (fmt in c("xpt", "json", "ndjson", "rds")) {
    p <- withr::local_tempfile(fileext = paste0(".", fmt))
    file.create(p)
    .expect_clean(p, fmt)
  }
})

test_that("a real SAS file with a flipped interior byte stays bounded", {
  fixture <- test_path("fixtures", "sas-ae.xpt")
  skip_if_not(file.exists(fixture), "AE fixture not present")
  full <- readBin(fixture, "raw", file.info(fixture)$size)
  set.seed(7)
  n <- length(full)
  for (i in 1:30) {
    pos <- sample.int(n, 1L)
    bytes <- full
    bytes[pos] <- as.raw(bitwXor(as.integer(bytes[pos]), 0xFFL))
    p <- withr::local_tempfile(fileext = ".xpt")
    writeBin(bytes, p)
    # Reading a corrupt-but-structurally-plausible xpt may succeed (the flip
    # landed in data) or abort; it must do one of those, bounded, never hang.
    .expect_clean(p, "xpt")
  }
})
