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

test_that(".to_target passes valid UTF-8 through and honours on_invalid policies", {
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

test_that(".to_target validates a UTF-8 target (invalid bytes hit on_invalid)", {
  # A lone latin1 byte in an unmarked string is invalid UTF-8: the UTF-8
  # branch must gate it through on_invalid instead of passing it to the
  # serializers (where utf8_normalize fails with a foreign error).
  bad <- rawToChar(as.raw(c(0x63, 0xE9)))
  expect_error(
    artoo:::.to_target(bad, "UTF-8", "error"),
    class = "artoo_error_codec"
  )
  expect_snapshot(artoo:::.to_target(bad, "UTF-8", "error"), error = TRUE)
  expect_warning(
    out <- artoo:::.to_target(bad, "UTF-8", "replace"),
    class = "artoo_warning_encoding"
  )
  expect_true(all(validUTF8(out)))
  expect_match(out, "[?]")
  expect_identical(artoo:::.to_target(bad, "UTF-8", "ignore"), "c")
})

test_that(".to_target UTF-8 validation honours declared marks and NA", {
  # A column legitimately marked latin1 transcodes cleanly — never flagged.
  lat <- rawToChar(as.raw(c(0x63, 0xE9)))
  Encoding(lat) <- "latin1"
  expect_identical(artoo:::.to_target(lat, "UTF-8", "error"), "cé")
  # NA-only and empty vectors pass untouched.
  expect_identical(
    artoo:::.to_target(NA_character_, "UTF-8", "error"),
    NA_character_
  )
  expect_identical(
    artoo:::.to_target(character(0), "UTF-8", "error"),
    character(0)
  )
  # The all-valid path returns the input as-is, attributes intact.
  ok <- c(USUBJID = "01-701-1015")
  attr(ok, "label") <- "Unique Subject Identifier"
  expect_identical(artoo:::.to_target(ok, "UTF-8", "error"), ok)
  # The replace path must also keep attributes (iconv strips them).
  labelled_bad <- rawToChar(as.raw(c(0x63, 0xE9)))
  attr(labelled_bad, "label") <- "Free text"
  suppressWarnings(
    rep_out <- artoo:::.to_target(labelled_bad, "UTF-8", "replace")
  )
  expect_identical(attr(rep_out, "label"), "Free text")
})

# ---- transliteration (SAS NLS punctuation fold) -----------------------------

test_that(".wlatin1_punct pins the SAS-published WLATIN1 punctuation code points", {
  tbl <- artoo:::.wlatin1_punct
  # The SAS 9.4 NLS "Smart Quotation Marks and Punctuation Characters" table:
  # WLATIN1 single-byte code point -> the ASCII character SAS folds it to.
  expected <- c(
    "‚" = ",", # 82 single low-9 quotation mark
    "„" = "\"", # 84 double low-9 quotation mark
    "…" = "...", # 85 horizontal ellipsis
    "‹" = "<", # 8B single left-pointing angle quotation mark
    "‘" = "'", # 91 left single quotation mark
    "’" = "'", # 92 right single quotation mark
    "“" = "\"", # 93 left double quotation mark
    "”" = "\"", # 94 right double quotation mark
    "•" = "*", # 95 bullet
    "–" = "-", # 96 en dash
    "—" = "-", # 97 em dash
    "›" = ">" # 9B single right-pointing angle quotation mark
  )
  expect_identical(tbl[names(expected)], expected)
  # Every fold target is itself ASCII, or the fold would not help.
  expect_true(all(validUTF8(tbl) & !grepl("[^\x01-\x7f]", tbl)))
})

test_that(".to_target translit folds smart punctuation to the SAS ASCII form", {
  x <- paste0(
    "Patient",
    "’",
    "s dose ",
    "–",
    " ",
    "“",
    "held",
    "”",
    "…"
  )
  expect_warning(
    out <- artoo:::.to_target(x, "US-ASCII", "translit"),
    class = "artoo_warning_encoding"
  )
  expect_identical(out, "Patient's dose - \"held\"...")
  expect_false(grepl("[?]", out))
})

test_that(".to_target translit leaves a UTF-8 target untouched", {
  # Nothing is unrepresentable in UTF-8, so there is nothing to fold: a
  # translit write to Dataset-JSON must not quietly ASCII-fy the text.
  x <- paste0("dose ", "–", " ", "“", "held", "”")
  expect_identical(artoo:::.to_target(x, "UTF-8", "translit"), x)
})

test_that(".to_target translit still aborts on a character with no ASCII fold", {
  # Folding punctuation is safe; silently stripping a person's diacritics is
  # not, so residue after the fold hits the same loud abort as "error".
  x <- "Öztürk"
  expect_error(
    artoo:::.to_target(x, "US-ASCII", "translit"),
    class = "artoo_error_codec"
  )
  expect_snapshot(artoo:::.to_target(x, "US-ASCII", "translit"), error = TRUE)
})

test_that(".to_target translit is a no-op when nothing needs folding", {
  x <- c("PARIS", NA_character_, "")
  expect_no_warning(
    out <- artoo:::.to_target(x, "US-ASCII", "translit")
  )
  expect_identical(out, x)
})

test_that(".to_target replace substitutes one ? per character, not per byte", {
  # Regression: iconv(sub = "?") replaces each unrepresentable BYTE, so one
  # right single quote (3 UTF-8 bytes) became "???" and inflated the value.
  x <- paste0("Patient", "’", "s")
  expect_warning(
    out <- artoo:::.to_target(x, "US-ASCII", "replace"),
    class = "artoo_warning_encoding"
  )
  expect_identical(out, "Patient?s")
  x2 <- "Öztürk" # 2 non-ASCII chars, 2 bytes each
  expect_warning(
    out2 <- artoo:::.to_target(x2, "US-ASCII", "replace"),
    class = "artoo_warning_encoding"
  )
  expect_identical(out2, "?zt?rk")
})

test_that("write_xpt(on_invalid = 'translit') emits legible ASCII", {
  x <- data.frame(
    USUBJID = "01-701-1015",
    COMMENT = paste0("dose ", "–", " ", "“", "held", "”")
  )
  f <- withr::local_tempfile(fileext = ".xpt")
  expect_warning(
    write_xpt(x, f, encoding = "US-ASCII", on_invalid = "translit"),
    class = "artoo_warning_encoding"
  )
  expect_identical(read_xpt(f)$COMMENT, "dose - \"held\"")
})

test_that(".sas_encoding_map covers the SAS OEM/DOS encoding names", {
  # SGF4561-2020 Table 1: OEM/DOS names per language. Map them to the CPnnn
  # spellings host iconv ships.
  m <- artoo:::.sas_encoding_map
  expect_identical(unname(m["pcoem437"]), "CP437")
  expect_identical(unname(m["pcoem850"]), "CP850")
  expect_identical(unname(m["pcoem852"]), "CP852")
  expect_identical(unname(m["pcoem862"]), "CP862")
  expect_identical(unname(m["pcoem866"]), "CP866")
  expect_identical(unname(m["msdos737"]), "CP737")
})
