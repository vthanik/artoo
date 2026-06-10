# Tests for the encoding SSOT (encoding.R). Internals via vport:::.

test_that(".resolve_charset maps SAS aliases and IANA names", {
  # wlatin1 resolves to a Windows-1252 spelling the host iconv ships.
  expect_true(
    toupper(vport:::.resolve_charset("wlatin1")) %in%
      c("WINDOWS-1252", "CP1252")
  )
  # latin1 is a DIFFERENT charset (ISO-8859-1), not 1252.
  expect_true(
    toupper(vport:::.resolve_charset("latin1")) %in%
      c("ISO-8859-1", "ISO8859-1", "ISO8859_1", "LATIN1")
  )
  # IANA name passes through.
  expect_identical(toupper(vport:::.resolve_charset("UTF-8")), "UTF-8")
})

test_that(".resolve_charset uses the candidate ladder when a spelling is absent", {
  # Host iconv ships only CP1252, not WINDOWS-1252: the ladder still resolves.
  # Mutate the cache env in place (do not reassign the namespace binding).
  e <- vport:::.vport_iconv
  old_list <- e$list
  old_resolved <- e$resolved
  withr::defer({
    e$list <- old_list
    e$resolved <- old_resolved
  })
  e$list <- c("CP1252", "UTF-8", "ASCII")
  e$resolved <- new.env(parent = emptyenv())
  expect_identical(vport:::.resolve_charset("wlatin1"), "CP1252")
  expect_identical(vport:::.resolve_charset("us-ascii"), "ASCII")
})

test_that(".resolve_charset aborts on an unavailable charset", {
  expect_snapshot(
    vport:::.resolve_charset("not-a-real-charset-zzz"),
    error = TRUE
  )
  expect_error(
    vport:::.resolve_charset("not-a-real-charset-zzz"),
    class = "vport_error_codec"
  )
})

test_that(".to_internal decodes Windows-1252 bytes to UTF-8 (proves cp1252, not latin1)", {
  # Bytes defined in Windows-1252 but UNDEFINED in ISO-8859-1: Euro (0x80),
  # trademark (0x99), curly quotes (0x93/0x94), plus e-acute (0xE9).
  b <- as.raw(c(0x80, 0x99, 0x93, 0x94, 0xE9))
  x <- rawToChar(b)
  got <- vport:::.to_internal(x, "wlatin1")
  expect_identical(
    got,
    intToUtf8(c(0x20AC, 0x2122, 0x201C, 0x201D, 0x00E9))
  )
  expect_identical(Encoding(got), "UTF-8")
})

test_that(".to_internal NFC-normalises decomposed UTF-8", {
  decomposed <- intToUtf8(c(0x65, 0x0301)) # e + combining acute
  got <- vport:::.to_internal(decomposed, "UTF-8")
  expect_identical(got, intToUtf8(0x00E9)) # precomposed e-acute
})

test_that(".to_internal passes NA and empty through", {
  expect_identical(vport:::.to_internal(character(0), "wlatin1"), character(0))
  expect_true(is.na(vport:::.to_internal(c(NA, "A"), "wlatin1")[1]))
})

test_that("wlatin1 <-> UTF-8 round-trips byte-for-byte (the fidelity invariant)", {
  b <- as.raw(c(0x80, 0x99, 0x93, 0x94, 0xE9))
  internal <- vport:::.to_internal(rawToChar(b), "wlatin1")
  back <- vport:::.to_target(internal, "wlatin1", "error")
  expect_identical(charToRaw(back), b)
})

test_that("read/write round-trips byte-for-byte for ANY single-byte encoding", {
  # The fidelity invariant is NOT wlatin1-specific: it holds for every
  # single-byte charset the host iconv ships (NFC is a no-op on single-byte
  # content). Each case uses high bytes defined in that encoding.
  cases <- list(
    "latin1" = as.raw(c(0xE9, 0xF1, 0xFC, 0xA9, 0xB0)), # ISO-8859-1
    "wlatin1" = as.raw(c(0x80, 0x99, 0x93, 0x94, 0xE9)), # Windows-1252
    "latin2" = as.raw(c(0xE1, 0xE9, 0xB3, 0xBF)), # ISO-8859-2
    "latin9" = as.raw(c(0xA4, 0xE9, 0xFC)), # ISO-8859-15 (Euro at 0xA4)
    "wcyrillic" = as.raw(c(0xC0, 0xD0, 0xE0, 0xFF)), # Windows-1251
    "wlatin2" = as.raw(c(0xE1, 0xE9, 0xB9)) # Windows-1250
  )
  tested <- 0L
  for (enc in names(cases)) {
    available <- tryCatch(
      {
        vport:::.resolve_charset(enc)
        TRUE
      },
      vport_error_codec = function(e) FALSE
    )
    if (!available) {
      next
    }
    b <- cases[[enc]]
    internal <- vport:::.to_internal(rawToChar(b), enc)
    expect_identical(Encoding(internal), "UTF-8")
    back <- vport:::.to_target(internal, enc, "error")
    expect_identical(charToRaw(back), b)
    tested <- tested + 1L
  }
  expect_gt(tested, 0L)
})

test_that(".to_target fast-paths UTF-8 and honours on_invalid policies", {
  x <- intToUtf8(c(0x2122)) # trademark, not in ASCII
  expect_identical(vport:::.to_target(x, "UTF-8", "error"), x)
  # error: trademark is not encodable in US-ASCII.
  expect_error(
    vport:::.to_target(x, "US-ASCII", "error"),
    class = "vport_error_codec"
  )
  expect_snapshot(vport:::.to_target(x, "US-ASCII", "error"), error = TRUE)
  # replace: substitutes (iconv replaces per byte) and warns; result is ASCII.
  expect_warning(
    out <- vport:::.to_target(x, "US-ASCII", "replace"),
    class = "vport_warning_encoding"
  )
  expect_false(is.na(out))
  expect_match(out, "^[?]+$")
  # ignore: drops the unencodable char silently.
  expect_identical(vport:::.to_target(x, "US-ASCII", "ignore"), "")
})

test_that(".to_target latin1 cannot encode Euro/trademark (proves wlatin1 != latin1)", {
  x <- intToUtf8(c(0x20AC, 0x2122)) # Euro + trademark
  expect_error(
    vport:::.to_target(x, "latin1", "error"),
    class = "vport_error_codec"
  )
})

test_that(".fda_forbidden_bytes flags bytes 160-191 on a single-byte stream", {
  expect_identical(
    vport:::.fda_forbidden_bytes(as.raw(c(0x41, 0xA9, 0x42, 0xBF))),
    c(2L, 4L)
  )
  expect_identical(
    vport:::.fda_forbidden_bytes(charToRaw("PLAIN ASCII")),
    integer(0)
  )
  expect_identical(vport:::.fda_forbidden_bytes(raw(0)), integer(0))
})

test_that(".resolve_charset rejects a non-string name", {
  expect_error(
    vport:::.resolve_charset(NA_character_),
    class = "vport_error_codec"
  )
  expect_error(vport:::.resolve_charset(123), class = "vport_error_codec")
})

test_that(".resolve_charset repopulates a cleared cache lazily", {
  e <- vport:::.vport_iconv
  old_list <- e$list
  old_resolved <- e$resolved
  withr::defer({
    e$list <- old_list
    e$resolved <- old_resolved
  })
  e$list <- NULL
  e$resolved <- NULL
  # Both NULL: .resolve_charset must repopulate via .encoding_onload.
  expect_identical(toupper(vport:::.resolve_charset("UTF-8")), "UTF-8")
  expect_false(is.null(e$list))
})
