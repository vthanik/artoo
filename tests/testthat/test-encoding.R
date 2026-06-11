# Tests for the encoding SSOT (encoding.R). Internals via artoo:::.

test_that(".resolve_charset maps SAS aliases and IANA names", {
  # wlatin1 resolves to a Windows-1252 spelling the host iconv ships.
  expect_true(
    toupper(artoo:::.resolve_charset("wlatin1")) %in%
      c("WINDOWS-1252", "CP1252")
  )
  # latin1 is a DIFFERENT charset (ISO-8859-1), not 1252.
  expect_true(
    toupper(artoo:::.resolve_charset("latin1")) %in%
      c("ISO-8859-1", "ISO8859-1", "ISO8859_1", "LATIN1")
  )
  # IANA name passes through.
  expect_identical(toupper(artoo:::.resolve_charset("UTF-8")), "UTF-8")
})

test_that(".resolve_charset uses the candidate ladder when a spelling is absent", {
  # Host iconv ships only CP1252, not WINDOWS-1252: the ladder still resolves.
  # Mutate the cache env in place (do not reassign the namespace binding).
  e <- artoo:::.artoo_iconv
  old_list <- e$list
  old_resolved <- e$resolved
  withr::defer({
    e$list <- old_list
    e$resolved <- old_resolved
  })
  e$list <- c("CP1252", "UTF-8", "ASCII")
  e$resolved <- new.env(parent = emptyenv())
  expect_identical(artoo:::.resolve_charset("wlatin1"), "CP1252")
  expect_identical(artoo:::.resolve_charset("us-ascii"), "ASCII")
})

test_that(".resolve_charset aborts on an unavailable charset", {
  expect_snapshot(
    artoo:::.resolve_charset("not-a-real-charset-zzz"),
    error = TRUE
  )
  expect_error(
    artoo:::.resolve_charset("not-a-real-charset-zzz"),
    class = "artoo_error_codec"
  )
})

test_that(".to_internal decodes Windows-1252 bytes to UTF-8 (proves cp1252, not latin1)", {
  # Bytes defined in Windows-1252 but UNDEFINED in ISO-8859-1: Euro (0x80),
  # trademark (0x99), curly quotes (0x93/0x94), plus e-acute (0xE9).
  b <- as.raw(c(0x80, 0x99, 0x93, 0x94, 0xE9))
  x <- rawToChar(b)
  got <- artoo:::.to_internal(x, "wlatin1")
  expect_identical(
    got,
    intToUtf8(c(0x20AC, 0x2122, 0x201C, 0x201D, 0x00E9))
  )
  expect_identical(Encoding(got), "UTF-8")
})

test_that(".to_internal NFC-normalises decomposed UTF-8", {
  decomposed <- intToUtf8(c(0x65, 0x0301)) # e + combining acute
  got <- artoo:::.to_internal(decomposed, "UTF-8")
  expect_identical(got, intToUtf8(0x00E9)) # precomposed e-acute
})

test_that(".to_internal passes NA and empty through", {
  expect_identical(artoo:::.to_internal(character(0), "wlatin1"), character(0))
  expect_true(is.na(artoo:::.to_internal(c(NA, "A"), "wlatin1")[1]))
})

test_that("wlatin1 <-> UTF-8 round-trips byte-for-byte (the fidelity invariant)", {
  b <- as.raw(c(0x80, 0x99, 0x93, 0x94, 0xE9))
  internal <- artoo:::.to_internal(rawToChar(b), "wlatin1")
  back <- artoo:::.to_target(internal, "wlatin1", "error")
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
        artoo:::.resolve_charset(enc)
        TRUE
      },
      artoo_error_codec = function(e) FALSE
    )
    if (!available) {
      next
    }
    b <- cases[[enc]]
    internal <- artoo:::.to_internal(rawToChar(b), enc)
    expect_identical(Encoding(internal), "UTF-8")
    back <- artoo:::.to_target(internal, enc, "error")
    expect_identical(charToRaw(back), b)
    tested <- tested + 1L
  }
  expect_gt(tested, 0L)
})

test_that(".to_target fast-paths UTF-8 and honours on_invalid policies", {
  x <- intToUtf8(c(0x2122)) # trademark, not in ASCII
  expect_identical(artoo:::.to_target(x, "UTF-8", "error"), x)
  # error: trademark is not encodable in US-ASCII.
  expect_error(
    artoo:::.to_target(x, "US-ASCII", "error"),
    class = "artoo_error_codec"
  )
  expect_snapshot(artoo:::.to_target(x, "US-ASCII", "error"), error = TRUE)
  # replace: substitutes (iconv replaces per byte) and warns; result is ASCII.
  expect_warning(
    out <- artoo:::.to_target(x, "US-ASCII", "replace"),
    class = "artoo_warning_encoding"
  )
  expect_false(is.na(out))
  expect_match(out, "^[?]+$")
  # ignore: drops the unencodable char silently.
  expect_identical(artoo:::.to_target(x, "US-ASCII", "ignore"), "")
})

test_that(".to_target latin1 cannot encode Euro/trademark (proves wlatin1 != latin1)", {
  x <- intToUtf8(c(0x20AC, 0x2122)) # Euro + trademark
  expect_error(
    artoo:::.to_target(x, "latin1", "error"),
    class = "artoo_error_codec"
  )
})

test_that(".fda_forbidden_bytes flags bytes 160-191 on a single-byte stream", {
  expect_identical(
    artoo:::.fda_forbidden_bytes(as.raw(c(0x41, 0xA9, 0x42, 0xBF))),
    c(2L, 4L)
  )
  expect_identical(
    artoo:::.fda_forbidden_bytes(charToRaw("PLAIN ASCII")),
    integer(0)
  )
  expect_identical(artoo:::.fda_forbidden_bytes(raw(0)), integer(0))
})

test_that(".resolve_charset rejects a non-string name", {
  expect_error(
    artoo:::.resolve_charset(NA_character_),
    class = "artoo_error_codec"
  )
  expect_error(artoo:::.resolve_charset(123), class = "artoo_error_codec")
})

test_that(".resolve_charset repopulates a cleared cache lazily", {
  e <- artoo:::.artoo_iconv
  old_list <- e$list
  old_resolved <- e$resolved
  withr::defer({
    e$list <- old_list
    e$resolved <- old_resolved
  })
  e$list <- NULL
  e$resolved <- NULL
  # Both NULL: .resolve_charset must repopulate via .encoding_onload.
  expect_identical(toupper(artoo:::.resolve_charset("UTF-8")), "UTF-8")
  expect_false(is.null(e$list))
})

# ---- Part B: NFC-on-write and attribute-preserving decode ------------------

test_that(".nfc canonicalizes to NFC and is a no-op on ASCII / non-character", {
  decomposed <- "café" # cafe + combining acute accent (NFD)
  precomposed <- "café" # cafe with a precomposed e-acute (NFC)
  expect_false(identical(decomposed, precomposed)) # genuinely different bytes
  expect_identical(artoo:::.nfc(decomposed), precomposed)
  expect_identical(artoo:::.nfc("plain ascii"), "plain ascii")
  expect_identical(artoo:::.nfc(character(0)), character(0))
  expect_identical(artoo:::.nfc(1:3), 1:3) # non-character passthrough
})

test_that(".recode_col transcodes a character column and preserves its attributes", {
  col <- iconv("café", "UTF-8", "windows-1252") # single byte 0xe9
  attr(col, "label") <- "City"
  out <- artoo:::.recode_col(col, "windows-1252")
  expect_identical(as.character(out), "café")
  expect_identical(attr(out, "label"), "City")
  expect_identical(Encoding(out), "UTF-8")
  # a non-character column passes through untouched.
  expect_identical(artoo:::.recode_col(1:3, "windows-1252"), 1:3)
})

# ---- artoo_encodings(): the cross-ecosystem reference table -----------------

test_that("artoo_encodings() returns the documented shape", {
  enc <- artoo_encodings()
  expect_s3_class(enc, "data.frame")
  expect_identical(names(enc), c("r", "sas", "python", "description"))
  expect_gt(nrow(enc), 10L)
  expect_false(anyNA(unlist(enc)))
})

test_that("every listed SAS name resolves through the alias map", {
  enc <- artoo_encodings()
  for (nm in enc$sas) {
    expect_no_error(artoo:::.resolve_charset(nm), message = nm)
  }
})

test_that("every listed R (IANA) name resolves on this host", {
  enc <- artoo_encodings()
  for (nm in enc$r) {
    expect_no_error(artoo:::.resolve_charset(nm), message = nm)
  }
})

test_that("SAS and IANA spellings of one row resolve to the same charset", {
  enc <- artoo_encodings()
  for (i in seq_len(nrow(enc))) {
    expect_identical(
      artoo:::.resolve_charset(enc$sas[i]),
      artoo:::.resolve_charset(enc$r[i]),
      label = enc$r[i]
    )
  }
})
