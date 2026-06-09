# Tests for the xpt byte-level helpers (padding, string<->raw, S370 PIB
# integers, the SAS header datetime, and short-read detection). These are
# the primitives the xpt header/read/write layers build on.

test_that(".pad_to pads, truncates, and leaves exact-width strings", {
  expect_identical(vport:::.pad_to("AB", 4L), "AB  ")
  expect_identical(vport:::.pad_to("ABCDE", 3L), "ABC")
  expect_identical(vport:::.pad_to("ABC", 3L), "ABC")
  # vectorised
  expect_identical(vport:::.pad_to(c("A", "BB"), 2L), c("A ", "BB"))
})

test_that(".pad_record fills to the next 80-byte boundary with spaces", {
  r <- vport:::.pad_record(as.raw(rep(1L, 100L)))
  expect_length(r, 160L)
  expect_true(all(r[101:160] == as.raw(0x20)))
  # exact multiples are untouched
  expect_length(vport:::.pad_record(as.raw(rep(1L, 80L))), 80L)
})

test_that(".str_to_raw and .raw_to_str round-trip a padded header field", {
  raw8 <- vport:::.str_to_raw("DM", 8L)
  expect_length(raw8, 8L)
  expect_identical(vport:::.raw_to_str(raw8), "DM")
})

test_that("S370 PIB integers round-trip big-endian", {
  expect_identical(vport:::.pib2_to_int(vport:::.int_to_pib2(258L)), 258L)
  expect_identical(vport:::.pib4_to_int(vport:::.int_to_pib4(70000L)), 70000L)
  # big-endian byte order
  expect_identical(as.integer(vport:::.int_to_pib2(1L)), c(0L, 1L))
})

test_that(".raw_to_str drops NUL padding and trailing spaces", {
  expect_identical(
    vport:::.raw_to_str(as.raw(c(0x41, 0x42, 0x20, 0x00))),
    "AB"
  )
  expect_identical(vport:::.raw_to_str(as.raw(c(0x00, 0x00))), "")
})

test_that(".raw_mat_to_strvec converts a byte matrix per column", {
  m <- matrix(charToRaw("AB  CD  "), nrow = 4L)
  expect_identical(vport:::.raw_mat_to_strvec(m), c("AB", "CD"))
  # with an explicit single-byte encoding
  expect_identical(
    vport:::.raw_mat_to_strvec(m, encoding = "WINDOWS-1252"),
    c("AB", "CD")
  )
  expect_identical(
    vport:::.raw_mat_to_strvec(matrix(raw(0), nrow = 4L, ncol = 0L)),
    character(0)
  )
})

test_that(".sas_datetime_str formats a frozen UTC time", {
  t <- as.POSIXct("2020-01-02 03:04:05", tz = "UTC")
  expect_identical(vport:::.sas_datetime_str(t), "02JAN20:03:04:05")
})

test_that(".read_bytes aborts on a short read", {
  con <- rawConnection(as.raw(c(1L, 2L, 3L)))
  on.exit(close(con))
  expect_error(
    vport:::.read_bytes(con, 8L),
    class = "vport_error_codec"
  )
})

test_that(".read_bytes returns exactly n bytes", {
  con <- rawConnection(as.raw(1:10))
  on.exit(close(con))
  expect_length(vport:::.read_bytes(con, 6L), 6L)
})
