# encoding.R — the transcoding single source of truth (SSOT).
#
# This file owns EVERY iconv() call in artoo; no codec calls iconv directly.
# Read converts source bytes to canonical UTF-8 (NFC); write converts UTF-8
# to a target charset under an explicit invalid-byte policy. Charset names
# follow the IANA registry; SAS encoding names (WLATIN1, LATIN1, ...) are
# canonicalised on entry from the SAS NLS "SBCS, DBCS, and Unicode Encoding
# Values for Transcoding Data" table. NFC normalisation uses the lightweight
# `utf8` package (no ICU).
#
# wlatin1 <-> UTF-8 fidelity invariant (the dominant clinical case): a value
# read from a wlatin1 (Windows-1252) xpt and written back to wlatin1
# reproduces the source bytes EXACTLY. NFC is a no-op on single-byte content
# (every character is already precomposed), so the read-side normalise cannot
# perturb a wlatin1 round-trip. The one case where on-disk bytes legitimately
# change is a decomposed-multibyte-UTF-8 source — intended normalisation,
# not loss.

# SAS encoding name -> IANA/code-page name (lowercase keys). Seeded from the
# SAS NLS encoding-values table. Two traps avoided: (1) the SAS name for
# ISO-8859-9 is `turkish` and for ISO-8859-5 is `cyrillic` — `latinN` does
# NOT line up with ISO-8859-N (`latin7`->8859-13, `latin9`->8859-15); (2)
# wlatin1 (WINDOWS-1252) differs from latin1 (ISO-8859-1) in 0x80-0x9F (Euro,
# trademark, curly quotes). Anything not here falls through to
# .resolve_charset()'s candidate ladder against iconvlist().
.sas_encoding_map <- c(
  # Unicode / ASCII
  "utf-8" = "UTF-8",
  "utf8" = "UTF-8",
  "us-ascii" = "US-ASCII",
  "ascii" = "US-ASCII",
  "ansi" = "US-ASCII",
  # Windows single-byte
  "wlatin1" = "WINDOWS-1252",
  "wlt1" = "WINDOWS-1252",
  "cp1252" = "WINDOWS-1252",
  "wlatin2" = "WINDOWS-1250",
  "wlt2" = "WINDOWS-1250",
  "cp1250" = "WINDOWS-1250",
  "wcyrillic" = "WINDOWS-1251",
  "wcyr" = "WINDOWS-1251",
  "cp1251" = "WINDOWS-1251",
  "wgreek" = "WINDOWS-1253",
  "wgrk" = "WINDOWS-1253",
  "wturkish" = "WINDOWS-1254",
  "wtur" = "WINDOWS-1254",
  "whebrew" = "WINDOWS-1255",
  "warabic" = "WINDOWS-1256",
  "wara" = "WINDOWS-1256",
  "wbaltic" = "WINDOWS-1257",
  "wbal" = "WINDOWS-1257",
  "wvietnamese" = "WINDOWS-1258",
  "wvie" = "WINDOWS-1258",
  # ISO single-byte (SAS names, deliberately NOT aligned to latinN)
  "latin1" = "ISO-8859-1",
  "lat1" = "ISO-8859-1",
  "latin2" = "ISO-8859-2",
  "lat2" = "ISO-8859-2",
  "latin3" = "ISO-8859-3",
  "cyrillic" = "ISO-8859-5",
  "arabic" = "ISO-8859-6",
  "greek" = "ISO-8859-7",
  "hebrew" = "ISO-8859-8",
  "turkish" = "ISO-8859-9",
  "thai" = "ISO-8859-11",
  "latin7" = "ISO-8859-13",
  "latin9" = "ISO-8859-15",
  "lat9" = "ISO-8859-15",
  "latin10" = "ISO-8859-16",
  # OEM/DOS single-byte (SGF4561-2020 Table 1)
  "pcoem437" = "CP437",
  "pcoem850" = "CP850",
  "pcoem852" = "CP852",
  "pcoem858" = "CP858",
  "pcoem862" = "CP862",
  "pcoem866" = "CP866",
  "msdos737" = "CP737",
  # DBCS (CJK)
  "shift-jis" = "SHIFT_JIS",
  "sjis" = "SHIFT_JIS",
  "ms-932" = "CP932",
  "euc-jp" = "EUC-JP",
  "jeuc" = "EUC-JP",
  "ms-936" = "CP936",
  "euc-cn" = "EUC-CN",
  "ms-949" = "CP949",
  "euc-kr" = "EUC-KR",
  "ms-950" = "CP950",
  # Direct passthroughs (already iconv-ish spellings)
  "windows-1252" = "WINDOWS-1252",
  "windows-1250" = "WINDOWS-1250",
  "windows-1251" = "WINDOWS-1251",
  "iso-8859-1" = "ISO-8859-1",
  "iso-8859-2" = "ISO-8859-2",
  "iso-8859-15" = "ISO-8859-15"
)

# WLATIN1 rows 8-F punctuation -> ASCII fold, pinned from the SAS 9.4 NLS
# "Smart Quotation Marks and Punctuation Characters" table (Migrating Data
# from WLATIN1 to UTF-8). Names are the Unicode characters (single-byte
# 0x82..0x9B in Windows-1252); values are the ASCII replacements SAS's
# KPROPDATA(..., "PUNC") applies. Used by on_invalid = "translit": folding
# typographic punctuation is safe, anything else (diacritics) still aborts.
.wlatin1_punct <- c(
  "\u201a" = ",", # 82 single low-9 quotation mark
  "\u201e" = "\"", # 84 double low-9 quotation mark
  "\u2026" = "...", # 85 horizontal ellipsis
  "\u2039" = "<", # 8B single left-pointing angle quotation mark
  "\u2018" = "'", # 91 left single quotation mark
  "\u2019" = "'", # 92 right single quotation mark
  "\u201c" = "\"", # 93 left double quotation mark
  "\u201d" = "\"", # 94 right double quotation mark
  "\u2022" = "*", # 95 bullet
  "\u2013" = "-", # 96 en dash
  "\u2014" = "-", # 97 em dash
  "\u203a" = ">" # 9B single right-pointing angle quotation mark
)

# Apply the punctuation fold to a UTF-8 character vector. fixed = TRUE per
# entry; the table is tiny so a loop over 12 gsubs is the simple, exact form.
#' @noRd
.fold_punct <- function(x) {
  for (i in seq_along(.wlatin1_punct)) {
    x <- gsub(names(.wlatin1_punct)[i], .wlatin1_punct[[i]], x, fixed = TRUE)
  }
  x
}

# WLATIN1 upper range -> ASCII, pinned VERBATIM from the ICU "Latin-ASCII"
# transliterator (the same fold SAS BASECHAR performs), so the result is
# identical on every platform — unlike iconv //TRANSLIT, whose output differs
# between glibc and macOS. Regenerate against ICU with:
#   stringi::stri_trans_general(ch, "Latin-ASCII")
# over the Windows-1252 code points. Characters ICU leaves unmapped (Euro,
# dagger, per-mille, trademark, micro, degree, currency/legal symbols) are
# deliberately ABSENT: they have no standards-backed ASCII form, and artoo
# invents nothing — a value carrying one still aborts under "fold".
# Punctuation is not duplicated here; .wlatin1_punct applies first and wins
# where the two authorities disagree (ICU folds U+201E to ",,", SAS to '"').
.latin1_fold <- c(
  # 0x83-0x9F letters and spacing accents
  "\u0192" = "f", # 83 latin small f with hook
  "\u02c6" = "^", # 88 modifier circumflex
  "\u0160" = "S", # 8A S caron
  "\u0152" = "OE", # 8C ligature OE
  "\u017d" = "Z", # 8E Z caron
  "\u02dc" = "~", # 98 small tilde
  "\u0161" = "s", # 9A s caron
  "\u0153" = "oe", # 9C ligature oe
  "\u017e" = "z", # 9E z caron
  "\u0178" = "Y", # 9F Y diaeresis
  # 0xA0-0xBF signs ICU maps
  "\u00a0" = " ", # A0 no-break space
  "\u00a1" = "!", # A1 inverted exclamation
  "\u00a9" = "(C)", # A9 copyright
  "\u00ab" = "<<", # AB left guillemet
  "\u00ad" = "-", # AD soft hyphen
  "\u00ae" = "(R)", # AE registered
  "\u00b1" = "+/-", # B1 plus-minus
  "\u00bb" = ">>", # BB right guillemet
  "\u00bc" = " 1/4", # BC one quarter (ICU keeps a leading space)
  "\u00bd" = " 1/2", # BD one half
  "\u00be" = " 3/4", # BE three quarters
  "\u00bf" = "?", # BF inverted question
  # 0xC0-0xFF Latin letters and arithmetic signs
  "\u00c0" = "A",
  "\u00c1" = "A",
  "\u00c2" = "A",
  "\u00c3" = "A",
  "\u00c4" = "A",
  "\u00c5" = "A",
  "\u00c6" = "AE",
  "\u00c7" = "C",
  "\u00c8" = "E",
  "\u00c9" = "E",
  "\u00ca" = "E",
  "\u00cb" = "E",
  "\u00cc" = "I",
  "\u00cd" = "I",
  "\u00ce" = "I",
  "\u00cf" = "I",
  "\u00d0" = "D",
  "\u00d1" = "N",
  "\u00d2" = "O",
  "\u00d3" = "O",
  "\u00d4" = "O",
  "\u00d5" = "O",
  "\u00d6" = "O",
  "\u00d7" = "*",
  "\u00d8" = "O",
  "\u00d9" = "U",
  "\u00da" = "U",
  "\u00db" = "U",
  "\u00dc" = "U",
  "\u00dd" = "Y",
  "\u00de" = "TH",
  "\u00df" = "ss",
  "\u00e0" = "a",
  "\u00e1" = "a",
  "\u00e2" = "a",
  "\u00e3" = "a",
  "\u00e4" = "a",
  "\u00e5" = "a",
  "\u00e6" = "ae",
  "\u00e7" = "c",
  "\u00e8" = "e",
  "\u00e9" = "e",
  "\u00ea" = "e",
  "\u00eb" = "e",
  "\u00ec" = "i",
  "\u00ed" = "i",
  "\u00ee" = "i",
  "\u00ef" = "i",
  "\u00f0" = "d",
  "\u00f1" = "n",
  "\u00f2" = "o",
  "\u00f3" = "o",
  "\u00f4" = "o",
  "\u00f5" = "o",
  "\u00f6" = "o",
  "\u00f7" = "/",
  "\u00f8" = "o",
  "\u00f9" = "u",
  "\u00fa" = "u",
  "\u00fb" = "u",
  "\u00fc" = "u",
  "\u00fd" = "y",
  "\u00fe" = "th",
  "\u00ff" = "y"
)

# Full ASCII fold: SAS punctuation first (it wins the U+201E disagreement),
# then the ICU Latin-ASCII table. Fixed gsubs throughout, applied only to
# the offending values, so the loop over ~86 entries is not a hot path.
#' @noRd
.fold_ascii <- function(x) {
  x <- .fold_punct(x)
  for (i in seq_along(.latin1_fold)) {
    x <- gsub(names(.latin1_fold)[i], .latin1_fold[[i]], x, fixed = TRUE)
  }
  x
}

# Module-level cache (mirrors artoo_temporal.R's .sas_* style). Populated by
# .onLoad and lazily on first use so the resolver works under partial loads.
.artoo_iconv <- new.env(parent = emptyenv())

#' @noRd
.encoding_onload <- function() {
  .artoo_iconv$list <- toupper(iconvlist())
  .artoo_iconv$resolved <- new.env(parent = emptyenv())
  invisible(NULL)
}

# The cached, uppercased iconv name list (populate lazily if .onLoad has not
# run, e.g. an internal called directly in a test before load).
#' @noRd
.iconv_names <- function() {
  if (is.null(.artoo_iconv$list)) {
    .encoding_onload()
  }
  .artoo_iconv$list
}

# Candidate spellings to try for an IANA name, since host iconv is
# inconsistent (WINDOWS-1252 vs CP1252, ISO-8859-1 vs ISO8859-1 vs ISO8859_1
# vs LATIN1, US-ASCII vs ASCII). Matched case-insensitively against the
# cached list; the first present spelling wins.
#' @noRd
.charset_candidates <- function(iana) {
  up <- toupper(iana)
  cands <- c(
    up,
    sub("^WINDOWS-", "CP", up),
    sub("^CP", "WINDOWS-", up),
    sub("^ISO-8859-", "ISO8859-", up),
    sub("^ISO-8859-", "ISO8859_", up),
    gsub("-", "", up)
  )
  if (up == "ISO-8859-1") {
    cands <- c(cands, "LATIN1")
  }
  if (up == "US-ASCII") {
    cands <- c(cands, "ASCII", "ANSI_X3.4-1968")
  }
  unique(cands)
}

# Map a SAS/IANA name to an iconv spelling actually present in iconvlist().
# Memoized. None present -> artoo_error_codec (loud, never a silent
# mis-transcode).
#' @noRd
.resolve_charset <- function(name, call = rlang::caller_env()) {
  if (
    !is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)
  ) {
    .artoo_abort(
      c(
        "{.arg encoding} must be a single charset name.",
        "x" = "You supplied {.obj_type_friendly {name}}."
      ),
      kind = "codec",
      call = call
    )
  }
  key <- tolower(trimws(name))
  if (is.null(.artoo_iconv$resolved)) {
    .encoding_onload()
  }
  hit <- .artoo_iconv$resolved[[key]]
  if (!is.null(hit)) {
    return(hit)
  }

  mapped <- .sas_encoding_map[key]
  iana <- if (is.na(mapped)) name else unname(mapped)
  avail <- .iconv_names()
  for (cand in .charset_candidates(iana)) {
    if (toupper(cand) %in% avail) {
      .artoo_iconv$resolved[[key]] <- cand
      return(cand)
    }
  }
  .artoo_abort(
    c(
      "Encoding {.val {name}} is not available on this system.",
      "i" = "The host {.code iconv} provides no spelling of it or a known alias."
    ),
    kind = "codec",
    call = call
  )
}

# READ: source bytes (charset `from`) -> canonical UTF-8 (NFC). The
# NFC normalise is a no-op for single-byte sources, so byte goldens stay
# stable. NA and empty short-circuit.
#' @noRd
.to_internal <- function(x, from) {
  if (!length(x)) {
    return(x)
  }
  cs <- .resolve_charset(from)
  out <- if (identical(toupper(cs), "UTF-8")) {
    # Mark the bytes UTF-8 so normalise interprets them as UTF-8 (decode
    # passes byte-passthrough strings marked "unknown").
    Encoding(x) <- "UTF-8"
    x
  } else {
    iconv(x, from = cs, to = "UTF-8", sub = "byte")
  }
  out <- utf8::utf8_normalize(out, map_compat = FALSE)
  Encoding(out) <- "UTF-8"
  out
}

# Canonicalise an already-UTF-8 character vector to NFC, NA-safe. Used on the
# WRITE side (json/parquet) so serialized output is canonical. A no-op on
# ASCII / single-byte content, so existing byte goldens are unaffected; only a
# decomposed-multibyte-UTF-8 value changes, which is intended normalisation.
#' @noRd
.nfc <- function(x) {
  if (!length(x) || !is.character(x)) {
    return(x)
  }
  out <- utf8::utf8_normalize(enc2utf8(x), map_compat = FALSE)
  Encoding(out) <- "UTF-8"
  out
}

# Attribute-preserving per-column decode for codec reads: transcode a character
# column's bytes from `enc` to internal UTF-8 (NFC) while keeping its label /
# format.sas attributes. A non-character column passes through untouched.
# Encoding marks live in the CHARSXP, not in attributes(), so restoring the
# saved attributes does not unset the UTF-8 marks .to_internal applied.
#' @noRd
.recode_col <- function(col, enc) {
  if (!is.character(col)) {
    return(col)
  }
  at <- attributes(col)
  out <- .to_internal(col, enc)
  attributes(out) <- at
  out
}

# WRITE: UTF-8 (internal) -> target charset bytes, under an invalid-byte
# policy. Returns a character vector whose stored bytes are the target
# encoding (ready for charToRaw by the codec). "error" fails loud naming
# offenders; "replace" substitutes one "?" per unrepresentable CHARACTER and
# warns; "ignore" drops; "translit" folds WLATIN1-style smart punctuation to
# its ASCII form (the SAS NLS table) and warns, aborting like "error" when a
# character with no fold (a diacritic) remains. A UTF-8 target validates,
# then inherits losslessly: unmarked bytes that are not valid UTF-8 hit the
# same on_invalid policy here instead of surfacing later as a foreign
# utf8_normalize error inside a serializer.
#' @noRd
.to_target <- function(
  x,
  to,
  on_invalid = c("error", "translit", "fold", "replace", "ignore"),
  call = rlang::caller_env()
) {
  on_invalid <- match.arg(on_invalid)
  if (!length(x)) {
    return(x)
  }
  cs <- .resolve_charset(to, call)
  if (identical(toupper(cs), "UTF-8")) {
    # Declared single-byte marks (latin1) transcode cleanly first; for
    # internal UTF-8 / unmarked bytes enc2utf8 is the identity, so the
    # all-valid path returns input-equivalent content and byte goldens
    # are unaffected. iconv strips attributes; save and restore them
    # (encoding marks live in the CHARSXPs, not in attributes()).
    at <- attributes(x)
    out <- enc2utf8(x)
    bad <- !validUTF8(out) & !is.na(out)
    if (!any(bad)) {
      attributes(out) <- at
      return(out)
    }
    if (on_invalid %in% c("error", "translit", "fold")) {
      # translit/fold act on characters; a byte-level invalidity has no
      # fold, so it aborts exactly like "error".
      shown <- utils::head(
        unique(iconv(out[bad], from = "UTF-8", to = "UTF-8", sub = "byte")),
        3L
      )
      .artoo_abort(
        c(
          "Cannot encode {sum(bad)} value{?s} as UTF-8.",
          "x" = "Invalid bytes (hex-escaped): {.val {shown}}.",
          "i" = "Re-read the source with the correct {.arg encoding}, or set {.arg on_invalid}."
        ),
        kind = "codec",
        call = call
      )
    }
    sub <- if (on_invalid == "replace") "?" else ""
    out <- iconv(out, from = "UTF-8", to = "UTF-8", sub = sub)
    if (on_invalid == "replace") {
      .artoo_warn(
        c(
          "Replaced invalid UTF-8 bytes with {.val ?} in {sum(bad)} value{?s}.",
          "i" = "Use {.code on_invalid = \"error\"} to fail loudly instead."
        ),
        kind = "encoding",
        call = call
      )
    }
    attributes(out) <- at
    return(out)
  }

  rt <- iconv(x, from = "UTF-8", to = cs)
  bad <- is.na(rt) & !is.na(x)
  if (!any(bad)) {
    return(rt)
  }

  if (on_invalid %in% c("translit", "fold")) {
    # translit folds the SAS punctuation table only; fold adds the ICU
    # Latin-ASCII accent strip (the BASECHAR analogue). Either way a residue
    # character with no standards-backed ASCII form still aborts: silently
    # dropping it would corrupt the value.
    fold_fn <- if (on_invalid == "fold") .fold_ascii else .fold_punct
    folded <- fold_fn(enc2utf8(x[bad]))
    rt2 <- iconv(folded, from = "UTF-8", to = cs)
    still <- is.na(rt2) & !is.na(folded)
    if (any(still)) {
      offenders <- utils::head(unique(x[bad][still]), 3L)
      what <- if (on_invalid == "fold") {
        "ASCII folding"
      } else {
        "punctuation folding"
      }
      hint <- if (on_invalid == "fold") {
        "The character has no standards-backed ASCII fold (ICU Latin-ASCII leaves it unmapped); write to Dataset-JSON (UTF-8), or set {.arg on_invalid}."
      } else {
        "Only smart punctuation has an ASCII fold; use {.code on_invalid = \"fold\"} to also strip accents, or write to Dataset-JSON (UTF-8)."
      }
      .artoo_abort(
        c(
          "Cannot encode {sum(still)} value{?s} to {.val {to}} even after {what}.",
          "x" = "Offending value{?s}: {.val {offenders}}.",
          "i" = hint
        ),
        kind = "codec",
        call = call
      )
    }
    rt[bad] <- rt2
    msg <- if (on_invalid == "fold") {
      c(
        "Folded {sum(bad)} value{?s} to ASCII for {.val {to}} (accents stripped).",
        "i" = "The fold follows the SAS NLS punctuation table plus ICU Latin-ASCII; the original characters are not recoverable from the output."
      )
    } else {
      c(
        "Transliterated smart punctuation to ASCII in {sum(bad)} value{?s} for {.val {to}}.",
        "i" = "The fold follows the SAS NLS punctuation table (quotes, dashes, ellipsis, bullet)."
      )
    }
    .artoo_warn(msg, kind = "encoding", call = call)
    return(rt)
  }

  if (on_invalid == "error") {
    offenders <- utils::head(unique(x[bad]), 3L)
    .artoo_abort(
      c(
        "Cannot encode {sum(bad)} value{?s} to {.val {to}}.",
        "x" = "Offending value{?s}: {.val {offenders}}.",
        "i" = "Write to Dataset-JSON (UTF-8), or set {.arg on_invalid}."
      ),
      kind = "codec",
      call = call
    )
  }

  if (on_invalid == "replace") {
    # One "?" per unrepresentable CHARACTER (iconv's sub= replaces per BYTE,
    # which turns one curly quote into "???" and inflates the byte width).
    rt[bad] <- vapply(
      enc2utf8(x[bad]),
      function(v) {
        ch <- strsplit(v, "", fixed = TRUE)[[1]]
        ch[is.na(iconv(ch, from = "UTF-8", to = cs))] <- "?"
        iconv(paste0(ch, collapse = ""), from = "UTF-8", to = cs)
      },
      character(1),
      USE.NAMES = FALSE
    )
    .artoo_warn(
      c(
        "Replaced unencodable characters with {.val ?} in {sum(bad)} value{?s} for {.val {to}}.",
        "i" = "Use {.code on_invalid = \"error\"} to fail loudly instead."
      ),
      kind = "encoding",
      call = call
    )
    return(rt)
  }

  # ignore: drop the unencodable bytes silently.
  rt[bad] <- iconv(x[bad], from = "UTF-8", to = cs, sub = "")
  rt
}

# Truncate an already-transcoded string to at most `width` bytes, backing off
# to a character boundary in the target charset. Boundary validity is probed
# by round-tripping the candidate bytes through iconv (this file owns every
# iconv call): an NA means the cut split a multibyte character, so back off
# one byte and retry. Single-byte charsets always cut clean on the first try.
#' @noRd
.trunc_bytes_boundary <- function(x, enc, width) {
  b <- charToRaw(x)
  if (length(b) <= width) {
    return(x)
  }
  cs <- .resolve_charset(enc)
  w <- width
  while (w > 0L) {
    cand <- rawToChar(b[seq_len(w)])
    if (!is.na(iconv(cand, from = cs, to = "UTF-8"))) {
      return(cand)
    }
    w <- w - 1L
  }
  ""
}

# FDA Study Data TCG prohibits bytes 160-191 in submission xpt. Runs on the
# POST-transcode single-byte stream (so it neither false-fires on multibyte
# UTF-8 nor misses real extended chars). Returns the integer positions of any
# forbidden bytes. Drives the xpt writer's FDA-byte warning (codec_xpt.R).
#' @noRd
.fda_forbidden_bytes <- function(raw) {
  if (!length(raw)) {
    return(integer(0))
  }
  v <- as.integer(raw)
  which(v >= 160L & v <= 191L)
}

#' Encodings for clinical datasets, across R, SAS, and Python
#'
#' List the character encodings clinical data actually travels in, with
#' the name each ecosystem uses for the same thing: the R name (the
#' standard IANA name, which `iconv()` and the wider R ecosystem use),
#' the SAS session-encoding name, and the Python codec. Any spelling
#' from the `r` or `sas` column works as the `encoding` argument of
#' every artoo reader and writer.
#'
#' @details
#' **What an encoding is.** Text is stored as bytes; an encoding is the
#' rule that maps those bytes to characters. Plain A-Z digits and
#' punctuation are the same bytes in every encoding listed here — the
#' differences only show in accented letters (a-umlaut, e-acute), special
#' symbols (micro, degree), and non-Latin scripts. Reading bytes with the
#' wrong rule is what turns a degree sign into garbage.
#'
#' **Which one do I have?** In SAS, run `PROC OPTIONS OPTION=ENCODING; RUN;`
#' and look up the reported name in the `sas` column. Most US/EU Windows
#' SAS installs report `WLATIN1` — that is `windows-1252` here.
#'
#' **Which one should I write?** Usually none: `write_*(encoding = NULL)`
#' (the default) inherits the encoding recorded when the data was read, so
#' a round-trip is byte-faithful. The regulatory defaults artoo applies
#' when nothing is recorded: SAS XPORT writes `US-ASCII` (the FDA Study
#' Data Technical Conformance Guide expectation) and Dataset-JSON / NDJSON
#' write `UTF-8` (required by CDISC and RFC 8259). A value that cannot be
#' represented in the target encoding aborts loudly — see `on_invalid` on
#' the writers.
#'
#' **Note:** in memory, artoo text is always UTF-8 (NFC-normalised) —
#' encodings only matter at the file boundary, exactly as in Python 3.
#'
#' @return *A `<data.frame>`* with one row per encoding and columns
#'   `r` (the R name — the standard IANA name `iconv()` uses, and what
#'   artoo records in the metadata), `sas` (the SAS session-encoding
#'   name), `python` (the Python codec name), and `description`.
#'
#' @examples
#' # ---- Example 1: the full cross-ecosystem table ----
#' #
#' # One row per encoding; the same byte rule under each ecosystem's name.
#' artoo_encodings()
#'
#' # ---- Example 2: look up a SAS session encoding ----
#' #
#' # PROC OPTIONS reported WLATIN1: find the R and Python names for the
#' # same bytes (the sas and r spellings both work as encoding=).
#' enc <- artoo_encodings()
#' enc[enc$sas == "WLATIN1", ]
#'
#' @seealso
#' **Use it:** the `encoding` argument of [read_xpt()], [write_xpt()],
#' [read_json()], and the other readers/writers.
#'
#' **Formats:** [artoo_formats()] for the codec registry.
#' @export
artoo_encodings <- function() {
  data.frame(
    r = c(
      "UTF-8",
      "US-ASCII",
      "windows-1252",
      "windows-1250",
      "windows-1251",
      "ISO-8859-1",
      "ISO-8859-15",
      "CP437",
      "CP850",
      "Shift_JIS",
      "CP932",
      "EUC-JP",
      "EUC-KR",
      "CP936",
      "CP950"
    ),
    sas = c(
      "UTF-8",
      "ASCII",
      "WLATIN1",
      "WLATIN2",
      "WCYRILLIC",
      "LATIN1",
      "LATIN9",
      "PCOEM437",
      "PCOEM850",
      "SHIFT-JIS",
      "MS-932",
      "EUC-JP",
      "EUC-KR",
      "MS-936",
      "MS-950"
    ),
    python = c(
      "utf_8",
      "ascii",
      "cp1252",
      "cp1250",
      "cp1251",
      "latin_1",
      "iso8859_15",
      "cp437",
      "cp850",
      "shift_jis",
      "cp932",
      "euc_jp",
      "euc_kr",
      "gbk",
      "cp950"
    ),
    description = c(
      "Unicode; Dataset-JSON requirement and the modern default everywhere",
      "7-bit basic Latin; what the FDA expects inside a submission XPORT",
      "Western European Windows; the usual US/EU SAS session (WLATIN1)",
      "Central European Windows",
      "Cyrillic Windows",
      "Western European Unix SAS (LATIN1)",
      "Western European with the euro sign (LATIN9)",
      "US DOS (OEM); very old PC archives",
      "Western European DOS (OEM); very old PC archives",
      "Japanese (PMDA submissions from Japanese SAS sessions)",
      "Japanese Windows (Microsoft Shift JIS variant)",
      "Japanese Unix",
      "Korean",
      "Simplified Chinese Windows (GBK)",
      "Traditional Chinese Windows (Big5)"
    ),
    stringsAsFactors = FALSE
  )
}
