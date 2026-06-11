# encoding.R -- the transcoding single source of truth (SSOT).
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
# change is a decomposed-multibyte-UTF-8 source -- intended normalisation,
# not loss.

# SAS encoding name -> IANA/code-page name (lowercase keys). Seeded from the
# SAS NLS encoding-values table. Two traps avoided: (1) the SAS name for
# ISO-8859-9 is `turkish` and for ISO-8859-5 is `cyrillic` -- `latinN` does
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
# offenders; "replace" substitutes "?" and warns; "ignore" drops. A UTF-8
# target fast-paths unchanged (lossless inherit).
#' @noRd
.to_target <- function(
  x,
  to,
  on_invalid = c("error", "replace", "ignore"),
  call = rlang::caller_env()
) {
  on_invalid <- match.arg(on_invalid)
  if (!length(x)) {
    return(x)
  }
  cs <- .resolve_charset(to, call)
  if (identical(toupper(cs), "UTF-8")) {
    return(x)
  }

  if (on_invalid == "error") {
    rt <- iconv(x, from = "UTF-8", to = cs)
    bad <- is.na(rt) & !is.na(x)
    if (any(bad)) {
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
    return(rt)
  }

  sub <- if (on_invalid == "replace") "?" else ""
  rt <- iconv(x, from = "UTF-8", to = cs, sub = sub)
  if (on_invalid == "replace") {
    lost <- iconv(x, from = "UTF-8", to = cs)
    n <- sum(is.na(lost) & !is.na(x))
    if (n > 0L) {
      .artoo_warn(
        c(
          "Replaced {n} unencodable value{?s} with {.val ?} for {.val {to}}.",
          "i" = "Use {.code on_invalid = \"error\"} to fail loudly instead."
        ),
        kind = "encoding",
        call = call
      )
    }
  }
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

#' Encodings for clinical datasets, across SAS, R, and Python
#'
#' List the character encodings clinical data actually travels in, with the
#' name each ecosystem uses for the same thing: the SAS session-encoding
#' name, the standard (IANA) name that R and artoo use, and the Python
#' codec. Any spelling from the `encoding` or `sas` column works as the
#' `encoding` argument of every artoo reader and writer.
#'
#' @details
#' **What an encoding is.** Text is stored as bytes; an encoding is the
#' rule that maps those bytes to characters. Plain A-Z digits and
#' punctuation are the same bytes in every encoding listed here -- the
#' differences only show in accented letters (a-umlaut, e-acute), special
#' symbols (micro, degree), and non-Latin scripts. Reading bytes with the
#' wrong rule is what turns a degree sign into garbage.
#'
#' **Which one do I have?** In SAS, run `PROC OPTIONS OPTION=ENCODING; RUN;`
#' and look up the reported name in the `sas` column. Most US/EU Windows
#' SAS installs report `WLATIN1` -- that is `windows-1252` here.
#'
#' **Which one should I write?** Usually none: `write_*(encoding = NULL)`
#' (the default) inherits the encoding recorded when the data was read, so
#' a round-trip is byte-faithful. The regulatory defaults artoo applies
#' when nothing is recorded: SAS XPORT writes `US-ASCII` (the FDA Study
#' Data Technical Conformance Guide expectation) and Dataset-JSON / NDJSON
#' write `UTF-8` (required by CDISC and RFC 8259). A value that cannot be
#' represented in the target encoding aborts loudly -- see `on_invalid` on
#' the writers.
#'
#' **Note:** in memory, artoo text is always UTF-8 (NFC-normalised) --
#' encodings only matter at the file boundary, exactly as in Python 3.
#'
#' @return *A `<data.frame>`* with one row per encoding and columns
#'   `encoding` (the standard IANA name, used by R), `sas` (the SAS
#'   session-encoding name), `python` (the Python codec name), and
#'   `description`.
#'
#' @examples
#' # ---- Example 1: the full cross-ecosystem table ----
#' #
#' # One row per encoding; the same byte rule under each ecosystem's name.
#' artoo_encodings()
#'
#' # ---- Example 2: look up a SAS session encoding ----
#' #
#' # PROC OPTIONS reported WLATIN1: find what to pass (either name works).
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
    encoding = c(
      "UTF-8",
      "US-ASCII",
      "windows-1252",
      "windows-1250",
      "windows-1251",
      "ISO-8859-1",
      "ISO-8859-15",
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
