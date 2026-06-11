# Special-missing (.A-.Z, ._) carriage through every codec.
#
# The sas_missing column attribute is the in-session canonical form (what the
# xpt layer produces and consumes); on disk the tags ride the namespaced
# `_vport.specialMissings` block so json/parquet round-trip them while the
# data values stay plain nulls (foreign readers degrade gracefully).

# A small AE-shaped frame with tagged numeric missings: ".A" (not done),
# ".Z" (not applicable), "._" (underscore missing). Plain NA stays untagged.
.tagged_frame <- function() {
  df <- data.frame(
    USUBJID = c("01-001", "01-002", "01-003", "01-004", "01-005"),
    AESEQ = c(1L, 2L, 3L, 4L, 5L),
    AENDY = c(10, NA, NA, 40, NA),
    stringsAsFactors = FALSE
  )
  attr(df$AENDY, "sas_missing") <- c(NA, ".A", "._", NA, ".Z")
  df
}

# ---- helper unit behaviour --------------------------------------------------

test_that(".collect_special_missings gathers only non-'.' tags at NA cells", {
  df <- .tagged_frame()
  sm <- vport:::.collect_special_missings(df)
  expect_named(sm, "AENDY")
  expect_identical(sm$AENDY$rows, c(2L, 3L, 5L))
  expect_identical(sm$AENDY$tags, c(".A", "._", ".Z"))

  # "." is the default meaning of an on-disk null: never collected.
  plain <- data.frame(AVAL = c(1, NA))
  attr(plain$AVAL, "sas_missing") <- c(NA, ".")
  expect_null(vport:::.collect_special_missings(plain))

  # A tag on a non-NA cell is stale; it is ignored, not carried.
  stale <- data.frame(AVAL = c(1, 2))
  attr(stale$AVAL, "sas_missing") <- c(".A", NA)
  expect_null(vport:::.collect_special_missings(stale))

  # No tags anywhere -> NULL, so codecs can test emptiness cheaply.
  expect_null(vport:::.collect_special_missings(data.frame(AVAL = c(1, NA))))
})

test_that(".apply_special_missings reattaches tags and skips unknown columns", {
  df <- data.frame(AENDY = c(10, NA, NA, 40, NA))
  sm <- list(
    AENDY = list(rows = c(2L, 5L), tags = c(".A", ".Z")),
    GHOST = list(rows = 1L, tags = ".B")
  )
  out <- vport:::.apply_special_missings(df, sm)
  expect_identical(
    attr(out$AENDY, "sas_missing"),
    c(NA, ".A", NA, NA, ".Z")
  )
  expect_identical(names(out), "AENDY")
})

test_that(".subset_special_missings aligns tags to a row subset", {
  tags <- c(NA, ".A", "._", NA, ".Z")
  expect_identical(
    vport:::.subset_special_missings(tags, 1:3),
    c(NA, ".A", "._")
  )
  expect_identical(vport:::.subset_special_missings(NULL, 1:3), NULL)
})

# ---- the losslessness legs --------------------------------------------------

test_that("special missings survive xpt -> json -> xpt", {
  df <- .tagged_frame()
  xpt1 <- withr::local_tempfile(fileext = ".xpt")
  jsn <- withr::local_tempfile(fileext = ".json")
  xpt2 <- withr::local_tempfile(fileext = ".xpt")

  write_xpt(df, xpt1)
  a <- read_xpt(xpt1)
  write_json(a, jsn)
  b <- read_json(jsn)
  expect_identical(
    attr(b$AENDY, "sas_missing")[c(2, 3, 5)],
    c(".A", "._", ".Z")
  )
  write_xpt(b, xpt2)
  c2 <- read_xpt(xpt2)
  # Byte-level proof: the second xpt carries the same indicator bytes.
  expect_identical(
    attr(c2$AENDY, "sas_missing"),
    attr(a$AENDY, "sas_missing")
  )
  expect_identical(c2$AENDY, a$AENDY)
})

test_that("special missings survive xpt -> parquet -> xpt", {
  skip_if_not_installed("nanoparquet")
  df <- .tagged_frame()
  xpt1 <- withr::local_tempfile(fileext = ".xpt")
  pq <- withr::local_tempfile(fileext = ".parquet")
  xpt2 <- withr::local_tempfile(fileext = ".xpt")

  write_xpt(df, xpt1)
  a <- read_xpt(xpt1)
  write_parquet(a, pq)
  b <- read_parquet(pq)
  expect_identical(
    attr(b$AENDY, "sas_missing")[c(2, 3, 5)],
    c(".A", "._", ".Z")
  )
  write_xpt(b, xpt2)
  c2 <- read_xpt(xpt2)
  expect_identical(
    attr(c2$AENDY, "sas_missing"),
    attr(a$AENDY, "sas_missing")
  )
})

test_that("special missings survive the full chain json -> parquet -> rds", {
  skip_if_not_installed("nanoparquet")
  df <- .tagged_frame()
  jsn <- withr::local_tempfile(fileext = ".json")
  pq <- withr::local_tempfile(fileext = ".parquet")
  rds <- withr::local_tempfile(fileext = ".rds")

  write_json(df, jsn)
  a <- read_json(jsn)
  write_parquet(a, pq)
  b <- read_parquet(pq)
  write_rds(b, rds)
  c2 <- read_rds(rds)
  expect_identical(
    attr(c2$AENDY, "sas_missing")[c(2, 3, 5)],
    c(".A", "._", ".Z")
  )
  expect_identical(c2$AENDY, df$AENDY, ignore_attr = FALSE)
})

test_that("n_max keeps and aligns tags on json and parquet reads", {
  df <- .tagged_frame()
  jsn <- withr::local_tempfile(fileext = ".json")
  write_json(df, jsn)
  part <- read_json(jsn, n_max = 3)
  expect_identical(attr(part$AENDY, "sas_missing"), c(NA, ".A", "._"))

  skip_if_not_installed("nanoparquet")
  pq <- withr::local_tempfile(fileext = ".parquet")
  write_parquet(df, pq)
  partp <- read_parquet(pq, n_max = 3)
  expect_identical(attr(partp$AENDY, "sas_missing"), c(NA, ".A", "._"))
})

test_that("col_select keeps tags on the kept columns", {
  df <- .tagged_frame()
  jsn <- withr::local_tempfile(fileext = ".json")
  write_json(df, jsn)
  part <- read_json(jsn, col_select = c("USUBJID", "AENDY"))
  expect_identical(
    attr(part$AENDY, "sas_missing"),
    c(NA, ".A", "._", NA, ".Z")
  )
})

test_that("tagged temporal columns carry their tags through json", {
  df <- data.frame(
    USUBJID = c("01-001", "01-002", "01-003"),
    ADT = as.Date(c("2024-03-01", NA, "2024-03-15")),
    stringsAsFactors = FALSE
  )
  attr(df$ADT, "sas_missing") <- c(NA, ".A", NA)
  jsn <- withr::local_tempfile(fileext = ".json")
  write_json(df, jsn)
  back <- read_json(jsn)
  expect_s3_class(back$ADT, "Date")
  expect_identical(attr(back$ADT, "sas_missing"), c(NA, ".A", NA))
})

test_that("tags survive apply_spec conformance", {
  spec <- vport_spec(
    data.frame(dataset = "AE", label = "Adverse Events"),
    data.frame(
      dataset = c("AE", "AE", "AE"),
      variable = c("USUBJID", "AESEQ", "AENDY"),
      label = c("Subject", "Sequence", "End Day"),
      data_type = c("string", "integer", "float"),
      stringsAsFactors = FALSE
    )
  )
  df <- .tagged_frame()
  out <- apply_spec(df, spec, "AE", on_error = "off")
  expect_identical(
    attr(out$AENDY, "sas_missing"),
    c(NA, ".A", "._", NA, ".Z")
  )
})

# ---- on-disk shape: graceful degradation ------------------------------------

test_that("the json file stays valid Dataset-JSON with plain nulls", {
  df <- .tagged_frame()
  jsn <- withr::local_tempfile(fileext = ".json")
  write_json(df, jsn)
  p <- jsonlite::fromJSON(jsn, simplifyVector = FALSE)
  # Data values are ordinary nulls -- a foreign reader sees plain missings.
  expect_null(p$rows[[2]][[3]])
  expect_null(p$rows[[5]][[3]])
  # The tags ride the namespaced extension, version-stamped.
  expect_identical(p[["_vport"]]$vportMetaVersion, "1.0")
  expect_identical(
    unlist(p[["_vport"]]$specialMissings$AENDY$tags),
    c(".A", "._", ".Z")
  )
})

test_that("a frame with no extension content writes strict-CDISC json", {
  df <- data.frame(USUBJID = c("01-001", "01-002"), AVAL = c(1, NA))
  jsn <- withr::local_tempfile(fileext = ".json")
  write_json(df, jsn)
  p <- jsonlite::fromJSON(jsn, simplifyVector = FALSE)
  expect_false("_vport" %in% names(p))
})

test_that("write_json(strict = TRUE) suppresses _vport with a loss warning", {
  df <- .tagged_frame()
  jsn <- withr::local_tempfile(fileext = ".json")
  expect_warning(
    write_json(df, jsn, strict = TRUE),
    class = "vport_warning_codec"
  )
  p <- jsonlite::fromJSON(jsn, simplifyVector = FALSE)
  expect_false("_vport" %in% names(p))
  back <- suppressWarnings({
    write_json(df, jsn, strict = TRUE)
    read_json(jsn)
  })
  expect_null(attr(back$AENDY, "sas_missing"))
})

test_that("pyreadstat reads tagged cells as plain missing", {
  skip_on_cran()
  py <- py_with_pyreadstat()
  skip_if(py == "", "python3 + pyreadstat not available")
  df <- .tagged_frame()
  xpt <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, xpt)
  script <- withr::local_tempfile(fileext = ".py")
  writeLines(
    c(
      "import sys, pyreadstat",
      sprintf("df, meta = pyreadstat.read_xport(r'%s')", xpt),
      "print(int(df['AENDY'].isna().sum()))"
    ),
    script
  )
  out <- system2(py, script, stdout = TRUE)
  expect_identical(tail(out, 1L), "3")
})
