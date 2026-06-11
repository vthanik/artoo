# The columnar JSON literal engine. The fixtures under fixtures/json-golden
# were written by the nested-list builder (one R object per cell -> one
# toJSON); the streaming literal engine must reproduce them byte for byte,
# proving the per-column serialize-strip-split assembly is observationally
# identical while never materializing O(rows x cols) cells.

.golden_path <- function(name) {
  test_path("fixtures", "json-golden", name)
}

.expect_bytes_equal <- function(actual_path, golden_path, label) {
  a <- readBin(actual_path, "raw", file.info(actual_path)$size)
  g <- readBin(golden_path, "raw", file.info(golden_path)$size)
  if (!identical(a, g)) {
    d <- which(
      a[seq_len(min(length(a), length(g)))] !=
        g[seq_len(min(length(a), length(g)))]
    )[1]
    info <- sprintf(
      "%s: first byte diff at %s (len %d vs %d): ...%s... vs ...%s...",
      label,
      d %||% "length",
      length(a),
      length(g),
      rawToChar(a[max(1, (d %||% 1) - 30):min(length(a), (d %||% 1) + 30)]),
      rawToChar(g[max(1, (d %||% 1) - 30):min(length(g), (d %||% 1) + 30)])
    )
    fail(info)
  } else {
    succeed()
  }
  invisible(TRUE)
}

test_that("the literal engine reproduces the demo goldens byte for byte", {
  frozen <- as.POSIXct("2024-01-15 10:30:00", tz = "UTC")
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  for (ds in c("DM", "ADSL")) {
    src <- apply_spec(
      if (ds == "DM") cdisc_dm else cdisc_adsl,
      spec,
      ds,
      on_error = "off"
    )
    p <- withr::local_tempfile(fileext = ".json")
    write_json(src, p, created = frozen)
    .expect_bytes_equal(p, .golden_path(paste0(tolower(ds), ".json")), ds)
  }
})

# The adversarial / torture frames carry separator-lookalike strings AND
# extreme-magnitude doubles (-1e75, 1e-300). The STRING escaping is what the
# literal-split engine must get right, so the strings are byte-pinned; the
# numbers are checked by round-trip equality, not byte-pinned -- jsonlite's
# 16th/17th significant digit for an extreme magnitude is platform-dependent
# (correctly-rounded but not identical across libc), and pinning it would
# test the platform's printf, not vport. Intra-run stability (write twice,
# identical bytes) is pinned separately below.
test_that("the engine escapes adversarial strings correctly (byte-pinned)", {
  frozen <- as.POSIXct("2024-01-15 10:30:00", tz = "UTC")
  adv <- data.frame(
    TXT = c(
      "a\",\"b",
      "x],[y",
      "back\\slash",
      "tab\there",
      "quote\"end",
      "\",\"",
      "café ÅÉ",
      "",
      NA,
      "newline\nin value"
    ),
    stringsAsFactors = FALSE
  )
  p <- withr::local_tempfile(fileext = ".json")
  write_json(adv, p, created = frozen)
  .expect_bytes_equal(p, .golden_path("adversarial.json"), "adversarial")
  expect_identical(read_json(p)$TXT, adv$TXT)
})

test_that("extreme-magnitude doubles round-trip and write stably", {
  frozen <- as.POSIXct("2024-01-15 10:30:00", tz = "UTC")
  adv <- data.frame(
    TXT = c("a", "b", "c", "d", "e", "f", "g", "h", "i", "j"),
    AVAL = c(0.1 + 0.2, -1e75, 1.5, NA, 63, 0.1, 2^53 - 1, -0.5, 1e-300, 42),
    stringsAsFactors = FALSE
  )
  p1 <- withr::local_tempfile(fileext = ".json")
  p2 <- withr::local_tempfile(fileext = ".json")
  write_json(adv, p1, created = frozen)
  write_json(adv, p2, created = frozen)
  # Deterministic on this platform: two writes are byte-identical.
  expect_identical(
    readBin(p1, "raw", file.info(p1)$size),
    readBin(p2, "raw", file.info(p2)$size)
  )
  # And lossless: jsonlite's formatter and parser are self-consistent, so
  # every double reads back to the identical bit pattern, 0.1 + 0.2 included.
  expect_identical(read_json(p1)$AVAL, adv$AVAL)
})

test_that("the torture frame round-trips through the literal engine", {
  frozen <- as.POSIXct("2024-01-15 10:30:00", tz = "UTC")
  src <- .torture_frame()
  p <- withr::local_tempfile(fileext = ".json")
  write_json(src, p, created = frozen)
  expect_lossless(src, read_json(p), via = "json literal engine")
})

test_that("the engine slabs large frames without changing the bytes", {
  # Force multiple slabs with a tiny slab size; the output must be identical
  # to a single-slab write.
  frozen <- as.POSIXct("2024-01-15 10:30:00", tz = "UTC")
  df <- data.frame(
    ID = sprintf("S-%03d", 1:25),
    VAL = c(seq(0.5, 12, by = 0.5), NA),
    stringsAsFactors = FALSE
  )
  p1 <- withr::local_tempfile(fileext = ".json")
  p2 <- withr::local_tempfile(fileext = ".json")
  write_json(df, p1, created = frozen)
  withr::local_options(vport.json_slab_rows = 4L)
  write_json(df, p2, created = frozen)
  expect_identical(
    readBin(p1, "raw", file.info(p1)$size),
    readBin(p2, "raw", file.info(p2)$size)
  )
})

test_that("a 0-row frame writes rows as an empty array", {
  df <- data.frame(USUBJID = character(0), AVAL = numeric(0))
  p <- withr::local_tempfile(fileext = ".json")
  write_json(df, p)
  parsed <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  expect_identical(parsed$rows, list())
  back <- read_json(p)
  expect_identical(nrow(back), 0L)
})
