# bench-io.R -- the artoo I/O benchmark harness (dev-only, .Rbuildignore'd).
#
# Builds a 1M x 30 ADSL-shaped frame (mixed strings, codes, doubles, dates)
# and times write/read across every available format, writing the results to
# bench/baseline.json. Run from the package root:
#
#   Rscript bench/bench-io.R
#
# The opt-in perf-regression smoke (ARTOO_BENCH=1, test-stress.R) compares
# fresh timings against bench/baseline.json with a 5x tolerance, so refresh
# the baseline on hardware changes, not per commit.
#
# Reference points (haven 2.5.x / nanoparquet 0.5.x on an M4 mac mini, run
# OUTSIDE this project -- haven is banned from the codebase): haven::write_xpt
# on the same frame ~1.3s, haven::read_xpt ~1.9s, nanoparquet::write_parquet
# ~0.5s. Pure-R artoo targets: xpt write within ~2x of haven's C writer.

devtools::load_all(".", quiet = TRUE)

n <- 1e6L
set.seed(2026)
frame <- data.frame(
  STUDYID = rep("ARTOO-001", n),
  USUBJID = sprintf("ARTOO-001-%07d", seq_len(n)),
  ARM = sample(c("PLACEBO", "ACTIVE 10MG", "ACTIVE 20MG", NA), n, TRUE),
  AGEGR1 = sample(c("<65", "65-80", ">80"), n, TRUE),
  SEX = sample(c("M", "F"), n, TRUE),
  AVAL = round(rnorm(n, 50, 10), 6),
  CHG = round(rnorm(n), 6),
  ADT = as.Date("2024-01-01") + sample.int(365L, n, TRUE),
  stringsAsFactors = FALSE
)

formats <- c("xpt", "json", "ndjson", "rds")
if (requireNamespace("nanoparquet", quietly = TRUE)) {
  formats <- c(formats, "parquet")
}

results <- list()
for (fmt in formats) {
  path <- tempfile(fileext = paste0(".", fmt))
  tw <- system.time(write_dataset(frame, path, format = fmt))[["elapsed"]]
  tr <- system.time(invisible(read_dataset(path, format = fmt)))[["elapsed"]]
  size_mb <- round(file.info(path)$size / 1e6, 1)
  unlink(path)
  results[[fmt]] <- list(
    write_s = round(tw, 2),
    read_s = round(tr, 2),
    size_mb = size_mb
  )
  cat(sprintf(
    "%-8s write %6.2fs  read %6.2fs  %8.1f MB\n",
    fmt,
    tw,
    tr,
    size_mb
  ))
}

baseline <- list(
  rows = n,
  cols = ncol(frame),
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  platform = R.version$platform,
  timings = results
)
jsonlite::write_json(
  baseline,
  "bench/baseline.json",
  auto_unbox = TRUE,
  pretty = TRUE
)
cat("baseline written to bench/baseline.json\n")
