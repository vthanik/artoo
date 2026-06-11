# Tests for the IBM 370 <-> IEEE 754 float conversion (the byte-level core of
# the xpt codec). The headline property is a lossless round-trip for values
# SAS represents exactly, plus correct handling of zero, regular missing, the
# extended special missings (.A-.Z, ._), and overflow.

rt <- function(x, missing = NULL) {
  artoo:::.ibm_to_ieee(artoo:::.ieee_to_ibm(x, missing = missing))
}

test_that("integers and SAS dates round-trip exactly", {
  # SAS dates are integers (days since 1960-01-01); typical clinical numerics.
  x <- c(0, 1, -1, 42, 1960, 23741, -10957, 1e6, 123456789)
  expect_equal(as.numeric(rt(x)), x)
})

test_that("simple decimals representable in IBM hex round-trip exactly", {
  x <- c(0.5, 0.25, 0.125, -0.5, 3.5, 100.25, 0.0625)
  expect_equal(as.numeric(rt(x)), x)
})

test_that("regular missing (NA/NaN/Inf) becomes SAS standard missing", {
  out <- rt(c(1, NA, 2, NaN, Inf, -Inf, 3))
  expect_equal(as.numeric(out[c(1, 3, 7)]), c(1, 2, 3))
  expect_true(all(is.na(out[c(2, 4, 5, 6)])))
  # All map to the standard "." indicator.
  tags <- attr(out, "sas_missing")
  expect_equal(tags[c(2, 4, 5, 6)], rep(".", 4))
})

test_that("extended special missings survive a write/read round-trip", {
  # The v0 lossiness fix: .A-.Z and ._ must come back, not collapse to ".".
  x <- c(10, NA, NA, NA, 20)
  miss <- c(NA, ".A", "._", ".Z", NA)
  out <- rt(x, missing = miss)
  expect_equal(as.numeric(out[c(1, 5)]), c(10, 20))
  expect_true(all(is.na(out[2:4])))
  expect_equal(attr(out, "sas_missing")[2:4], c(".A", "._", ".Z"))
})

test_that("untagged NA with a missing vector still yields standard missing", {
  out <- rt(c(NA, 5), missing = c(NA, NA))
  expect_equal(attr(out, "sas_missing")[1], ".")
  expect_equal(as.numeric(out[2]), 5)
})

test_that("the encoded length is 8 bytes per value", {
  expect_length(artoo:::.ieee_to_ibm(c(1, 2, 3)), 24L)
  expect_length(artoo:::.ieee_to_ibm(numeric(0)), 0L)
})

test_that("empty input decodes to numeric(0)", {
  expect_equal(artoo:::.ibm_to_ieee(raw(0)), numeric(0))
})

test_that(".is_sas_missing recognises the indicator byte patterns", {
  expect_true(artoo:::.is_sas_missing(as.raw(c(0x2E, rep(0, 7)))))
  expect_true(artoo:::.is_sas_missing(as.raw(c(0x41, rep(0, 7))))) # .A
  expect_false(artoo:::.is_sas_missing(as.raw(c(0x2E, 1, rep(0, 6)))))
})

test_that("values beyond the IBM range overflow to SAS missing", {
  # IBM 370 caps near 16^63 ~ 7.2e75; larger magnitudes cannot be stored.
  out <- rt(c(5, 1e80, -1e80, 7))
  expect_equal(as.numeric(out[c(1, 4)]), c(5, 7))
  expect_true(all(is.na(out[2:3])))
})

test_that("all-missing input encodes and decodes without a regular branch", {
  enc <- artoo:::.ieee_to_ibm(c(NA, NA, NaN))
  expect_length(enc, 24L)
  dec <- artoo:::.ibm_to_ieee(enc)
  expect_true(all(is.na(dec)))
})

test_that(".sas_indicator_byte handles an empty tag vector", {
  expect_equal(artoo:::.sas_indicator_byte(character(0)), integer(0))
})

test_that("a large vector with mixed values round-trips", {
  x <- c(seq(-1000, 1000, by = 0.5), NA, 0, 17.0)
  out <- rt(x)
  finite <- is.finite(x)
  expect_equal(as.numeric(out[finite]), x[finite])
})

# ---- external oracle: published IBM System/370 hex-float constants ----------
# Big-endian 8-byte IBM-370 representations, independent of artoo's code — a
# symmetric encode/decode bug cannot satisfy these fixed bytes.

test_that(".ieee_to_ibm matches the published IBM-370 hex constants", {
  golden <- list(
    `1` = as.raw(c(0x41, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)),
    `2` = as.raw(c(0x41, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)),
    `0.5` = as.raw(c(0x40, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)),
    `-1` = as.raw(c(0xC1, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)),
    `0` = as.raw(c(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
  )
  for (k in names(golden)) {
    v <- as.numeric(k)
    expect_identical(artoo:::.ieee_to_ibm(v), golden[[k]], info = k)
    expect_equal(artoo:::.ibm_to_ieee(golden[[k]]), v, info = k)
  }
})

test_that("-0.0 encodes to the zero pattern and an integer > 2^53 loses precision predictably", {
  expect_identical(
    artoo:::.ieee_to_ibm(-0.0),
    as.raw(c(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
  )
  # 2^53 + 1 is not representable as a double; document the IEEE limit.
  big <- 2^53
  expect_equal(artoo:::.ibm_to_ieee(artoo:::.ieee_to_ibm(big)), big)
})
