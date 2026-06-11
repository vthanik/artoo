# Stress: wide (1000-variable) and tall (200k-row) frames round-trip through
# every format with identity preserved and bounded memory. The big sizes run
# only under VPORT_STRESS=1 (and never on CRAN); a smaller default size keeps
# the everyday suite honest without the wall-clock cost.

skip_on_cran()

.stress_big <- function() {
  identical(Sys.getenv("VPORT_STRESS"), "1")
}

.full_formats_stress <- function() {
  fmts <- c("xpt", "json", "ndjson", "rds")
  if (requireNamespace("nanoparquet", quietly = TRUE)) {
    fmts <- c(fmts, "parquet")
  }
  fmts
}

test_that("a wide frame (1000 variables) round-trips through every format", {
  nvar <- if (.stress_big()) 1000L else 250L
  n <- 20L
  cols <- stats::setNames(
    lapply(seq_len(nvar), function(j) {
      if (j %% 3L == 0L) {
        as.numeric(seq_len(n) + j)
      } else if (j %% 3L == 1L) {
        sprintf("V%d-%d", j, seq_len(n))
      } else {
        as.integer(seq_len(n))
      }
    }),
    sprintf("VAR%04d", seq_len(nvar))
  )
  df <- as.data.frame(cols, stringsAsFactors = FALSE)
  meta <- vport:::.meta_from_frame(df)
  df <- set_meta(df, meta)

  for (fmt in .full_formats_stress()) {
    p <- withr::local_tempfile(fileext = paste0(".", fmt))
    write_dataset(df, p, format = fmt)
    back <- read_dataset(p, format = fmt)
    expect_identical(ncol(back), nvar, info = fmt)
    expect_identical(nrow(back), n, info = fmt)
    expect_identical(back[["VAR0001"]], df[["VAR0001"]], info = fmt)
    expect_identical(
      back[["VAR0999"]],
      df[["VAR0999"]],
      info = paste(fmt, "tail")
    )
  }
})

test_that("a tall frame round-trips through every format with bounded memory", {
  n <- if (.stress_big()) 200000L else 20000L
  df <- data.frame(
    USUBJID = sprintf("S-%07d", seq_len(n)),
    AVAL = round(seq_len(n) * 1.5, 3),
    CAT = rep(c("A", "B", "C", NA), length.out = n),
    ADT = as.Date("2020-01-01") + (seq_len(n) %% 365L),
    stringsAsFactors = FALSE
  )
  spec <- vport_spec(
    data.frame(dataset = "LB", label = "Labs"),
    data.frame(
      dataset = "LB",
      variable = c("USUBJID", "AVAL", "CAT", "ADT"),
      label = c("Subject", "Value", "Category", "Date"),
      data_type = c("string", "float", "string", "date"),
      display_format = c(NA, NA, NA, "DATE9."),
      stringsAsFactors = FALSE
    )
  )
  conf <- apply_spec(df, spec, "LB", on_error = "off")

  for (fmt in .full_formats_stress()) {
    p <- withr::local_tempfile(fileext = paste0(".", fmt))
    write_dataset(conf, p, format = fmt)
    back <- read_dataset(p, format = fmt)
    expect_identical(nrow(back), n, info = fmt)
    expect_identical(back$USUBJID, conf$USUBJID, info = fmt)
    expect_identical(back$AVAL, conf$AVAL, info = fmt)
  }
  # The streaming JSON/NDJSON writers never build the O(n*p) cell list the
  # old row-major builder did; that bound is measured properly by the bench
  # harness (bench/bench-io.R), not a brittle in-test gc() probe.
})

test_that("the real LB lab domain round-trips when present", {
  fixture <- test_path("fixtures", "sas-lb.xpt")
  skip_if_not(file.exists(fixture), "LB fixture not present (download-only)")
  lb <- read_xpt(fixture)
  expect_gt(nrow(lb), 50000L)
  for (fmt in .full_formats_stress()) {
    p <- withr::local_tempfile(fileext = paste0(".", fmt))
    write_dataset(lb, p, format = fmt)
    back <- read_dataset(p, format = fmt)
    expect_identical(nrow(back), nrow(lb), info = fmt)
    expect_identical(back[[1]], lb[[1]], info = fmt)
  }
})

# ---- perf regression (opt-in, vs bench/baseline.json) -----------------------

test_that("write/read timings stay within 5x of the recorded baseline", {
  skip_if(Sys.getenv("VPORT_BENCH") != "1", "set VPORT_BENCH=1 to run")
  baseline_path <- test_path("..", "..", "bench", "baseline.json")
  skip_if_not(file.exists(baseline_path), "bench/baseline.json not present")
  baseline <- jsonlite::fromJSON(baseline_path, simplifyVector = FALSE)

  n <- as.integer(baseline$rows)
  set.seed(2026)
  frame <- data.frame(
    STUDYID = rep("VPORT-001", n),
    USUBJID = sprintf("VPORT-001-%07d", seq_len(n)),
    ARM = sample(c("PLACEBO", "ACTIVE 10MG", NA), n, TRUE),
    AVAL = round(rnorm(n), 6),
    ADT = as.Date("2024-01-01") + sample.int(365L, n, TRUE),
    stringsAsFactors = FALSE
  )
  for (fmt in c("xpt", "json", "ndjson")) {
    base <- baseline$timings[[fmt]]
    p <- withr::local_tempfile(fileext = paste0(".", fmt))
    tw <- system.time(write_dataset(frame, p, format = fmt))[["elapsed"]]
    tr <- system.time(invisible(read_dataset(p, format = fmt)))[["elapsed"]]
    expect_lt(tw, 5 * base$write_s, label = paste(fmt, "write"))
    expect_lt(tr, 5 * base$read_s, label = paste(fmt, "read"))
  }
})
