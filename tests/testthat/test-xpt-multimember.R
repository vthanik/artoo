# Multi-member XPORT reads: xpt_members() lists the datasets a transport
# file holds; read_xpt(member=) seeks to and decodes one of them. Fixtures
# are built by byte-concatenating artoo-written single-member files — every
# member section is 80-byte padded, so the catenation is a valid library.

.mm_frames <- function() {
  dm <- data.frame(
    USUBJID = c("01-001", "01-002", "01-003"),
    AGE = c(34, 47, 61),
    stringsAsFactors = FALSE
  )
  ae <- data.frame(
    USUBJID = c("01-001", "01-001", "01-002"),
    AESEQ = c(1, 2, 1),
    AESEV = c("MILD", "SEVERE", "MODERATE"),
    stringsAsFactors = FALSE
  )
  list(dm = dm, ae = ae)
}

# Concatenate the library header of the first file with every file's member
# section (bytes after the 3-record, 240-byte library header).
.mm_fixture <- function(version) {
  fr <- .mm_frames()
  frozen <- as.POSIXct("2024-01-15 10:30:00", tz = "UTC")
  p1 <- tempfile(fileext = ".xpt")
  p2 <- tempfile(fileext = ".xpt")
  on.exit(unlink(c(p1, p2)))
  dm <- fr$dm
  ae <- fr$ae
  attr(dm, "dataset_name") <- "DM"
  attr(ae, "dataset_name") <- "AE"
  write_xpt(dm, p1, version = version, created = frozen)
  write_xpt(ae, p2, version = version, created = frozen)
  b1 <- readBin(p1, "raw", file.info(p1)$size)
  b2 <- readBin(p2, "raw", file.info(p2)$size)
  out <- tempfile(fileext = ".xpt")
  con <- file(out, "wb")
  writeBin(c(b1, b2[-(1:240)]), con)
  close(con)
  out
}

for (v in c(5L, 8L)) {
  test_that(sprintf("xpt_members lists both members (v%d)", v), {
    p <- .mm_fixture(v)
    withr::defer(unlink(p))
    m <- xpt_members(p)
    expect_s3_class(m, "data.frame")
    expect_identical(m$member, 1:2)
    expect_identical(m$name, c("DM", "AE"))
    expect_identical(m$nvars, c(2L, 3L))
    expect_identical(m$nobs, c(3L, 3L))
  })

  test_that(sprintf("read_xpt(member=) reads each member (v%d)", v), {
    p <- .mm_fixture(v)
    withr::defer(unlink(p))
    fr <- .mm_frames()

    dm <- read_xpt(p, member = "DM")
    expect_identical(as.vector(dm$USUBJID), fr$dm$USUBJID)
    expect_identical(as.vector(dm$AGE), fr$dm$AGE)
    expect_identical(get_meta(dm)@dataset$name, "DM")

    # By index, and case-insensitively by name.
    ae <- read_xpt(p, member = 2)
    expect_identical(as.vector(ae$AESEV), fr$ae$AESEV)
    ae2 <- read_xpt(p, member = "ae")
    expect_identical(as.vector(ae2$AESEQ), fr$ae$AESEQ)
    expect_identical(get_meta(ae2)@dataset$records, 3L)
  })

  test_that(sprintf("member reads honor col_select and n_max (v%d)", v), {
    p <- .mm_fixture(v)
    withr::defer(unlink(p))
    part <- read_xpt(p, member = "AE", col_select = "AESEV", n_max = 2)
    expect_identical(names(part), "AESEV")
    expect_identical(nrow(part), 2L)
  })

  test_that(sprintf("the default read aborts pointing at member= (v%d)", v), {
    p <- .mm_fixture(v)
    withr::defer(unlink(p))
    err <- tryCatch(read_xpt(p), error = function(e) e)
    expect_s3_class(err, "artoo_error_codec")
    expect_match(conditionMessage(err), "xpt_members|member", all = FALSE)
  })

  test_that(sprintf("an unknown member errors listing the names (v%d)", v), {
    p <- .mm_fixture(v)
    withr::defer(unlink(p))
    err <- tryCatch(read_xpt(p, member = "LB"), error = function(e) e)
    expect_s3_class(err, "artoo_error_input")
    expect_match(conditionMessage(err), "DM")
    expect_error(read_xpt(p, member = 9), class = "artoo_error_input")
  })
}

test_that("a single-member file still reads with and without member=", {
  fr <- .mm_frames()
  dm <- fr$dm
  attr(dm, "dataset_name") <- "DM"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p)
  expect_identical(as.vector(read_xpt(p)$AGE), fr$dm$AGE)
  expect_identical(as.vector(read_xpt(p, member = "DM")$AGE), fr$dm$AGE)
  expect_identical(as.vector(read_xpt(p, member = 1)$AGE), fr$dm$AGE)
  m <- xpt_members(p)
  expect_identical(nrow(m), 1L)
  expect_error(read_xpt(p, member = "AE"), class = "artoo_error_input")
})

test_that("read_dataset forwards member= to the xpt codec", {
  p <- .mm_fixture(8L)
  withr::defer(unlink(p))
  ae <- read_dataset(p, member = "AE")
  expect_identical(get_meta(ae)@dataset$name, "AE")
})

test_that("xpt_members rejects a non-xpt file", {
  p <- withr::local_tempfile(fileext = ".xpt")
  writeBin(charToRaw(strrep("x", 400)), p)
  expect_error(xpt_members(p), class = "artoo_error_codec")
})

test_that("a member read equals the same dataset read single-member", {
  # The oracle here is artoo's own single-member reader (pyreadstat absorbs
  # a second v5 member as extra rows of the first — the exact failure mode
  # artoo's boundary-bounded read avoids).
  fr <- .mm_frames()
  dm <- fr$dm
  attr(dm, "dataset_name") <- "DM"
  single <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, single)
  ref <- read_xpt(single)

  p <- .mm_fixture(5L)
  withr::defer(unlink(p))
  got <- read_xpt(p, member = "DM")
  expect_identical(got$USUBJID, ref$USUBJID)
  expect_identical(got$AGE, ref$AGE)
  expect_identical(get_meta(got)@columns, get_meta(ref)@columns)
})

# ---- edge coverage -----------------------------------------------------------

test_that("xpt_members input guards fire", {
  expect_error(xpt_members("/nope/missing.xpt"), class = "artoo_error_input")
  p <- .mm_fixture(8L)
  withr::defer(unlink(p))
  expect_error(read_xpt(p, member = list()), class = "artoo_error_input")
})

test_that("a library header with no member aborts", {
  p <- withr::local_tempfile(fileext = ".xpt")
  src <- .mm_fixture(5L)
  withr::defer(unlink(src))
  writeBin(readBin(src, "raw", 240L), p)
  expect_error(xpt_members(p), class = "artoo_error_codec")
})

test_that("trailing blank padding after the last member is not a member", {
  p <- .mm_fixture(8L)
  withr::defer(unlink(p))
  con <- file(p, "ab")
  writeBin(rep(as.raw(0x20), 160L), con)
  close(con)
  expect_identical(nrow(xpt_members(p)), 2L)
})

test_that("the scanner handles a v8 member with a long label", {
  long_lab <- strrep("A very long adverse events label ", 3) # > 40 bytes
  ae <- data.frame(USUBJID = "01-001", AESEQ = 1)
  attr(ae, "dataset_name") <- "AE"
  attr(ae, "label") <- long_lab
  dm <- data.frame(USUBJID = "01-001", AGE = 34)
  attr(dm, "dataset_name") <- "DM"
  lab_col <- "Subject identifier label well over forty bytes for LABELV8"
  attr(ae$USUBJID, "label") <- lab_col

  p1 <- withr::local_tempfile(fileext = ".xpt")
  p2 <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p1, version = 8)
  # The long dataset label truncates at 40 bytes (expected; v8 has no
  # dataset-label extension) — the long COLUMN label is what LABELV8 keeps.
  suppressWarnings(write_xpt(ae, p2, version = 8))
  multi <- withr::local_tempfile(fileext = ".xpt")
  con <- file(multi, "wb")
  writeBin(
    c(
      readBin(p1, "raw", file.info(p1)$size),
      readBin(p2, "raw", file.info(p2)$size)[-(1:240)]
    ),
    con
  )
  close(con)
  m <- xpt_members(multi)
  expect_identical(m$name, c("DM", "AE"))
  back <- read_xpt(multi, member = "AE")
  expect_identical(attr(back$USUBJID, "label"), lab_col)
})

test_that(".xpt_parse_label_extension reads LABELV9 format/informat strings", {
  # artoo writes LABELV8 only; LABELV9 (10-byte header + name/label/format/
  # informat strings) appears in other writers' files. Build one record by
  # hand and parse it.
  ns <- list(list(
    vartype = 1L,
    length = 8L,
    varnum = 1L,
    name = "OLD",
    label = "old",
    format_name = "",
    formatl = 0L,
    formatd = 0L,
    informat_name = "",
    informatl = 0L,
    informatd = 0L,
    npos = 0L
  ))
  name <- charToRaw("AVAL")
  label <- charToRaw("Analysis Value")
  fmt <- charToRaw("BEST12.2")
  infmt <- charToRaw("YYMMDD10.")
  rec <- c(
    artoo:::.int_to_pib2(1L),
    artoo:::.int_to_pib2(length(name)),
    artoo:::.int_to_pib2(length(label)),
    artoo:::.int_to_pib2(length(fmt)),
    artoo:::.int_to_pib2(length(infmt)),
    name,
    label,
    fmt,
    infmt
  )
  pad <- 80L - (length(rec) %% 80L)
  con <- rawConnection(c(rec, rep(as.raw(0x20), pad)), "rb")
  on.exit(close(con))
  hdr <- sprintf(
    "%-80s",
    paste0(
      "HEADER RECORD*******LABELV9 HEADER RECORD!!!!!!!",
      formatC(1L, width = 30L, flag = " ")
    )
  )
  out <- artoo:::.xpt_parse_label_extension(con, hdr, ns)
  expect_identical(out[[1]]$name, "AVAL")
  expect_identical(out[[1]]$label, "Analysis Value")
  expect_identical(out[[1]]$format_name, "BEST")
  expect_identical(out[[1]]$formatl, 12L)
  expect_identical(out[[1]]$formatd, 2L)
  expect_identical(out[[1]]$informat_name, "YYMMDD")
  expect_identical(out[[1]]$informatl, 10L)
})
