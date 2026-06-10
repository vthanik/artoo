# Tests for the xpt codec (codec_xpt.R): v5/v8 framing, the meta bridge,
# special missings, temporal + encoding round-trips, and the F1/F2/C4
# invariants. Internals via vport:::; a frozen `created` keeps bytes stable.

demo_spec <- function() {
  vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
}

frozen <- as.POSIXct("2020-01-01", tz = "UTC")

# Compare column VALUES (vport keeps labels in meta, not on columns; the
# sas_missing tag is a separate concern). Class is preserved by as.character.
# Honors C4: XPORT stores "" as a blank, which reads back as NA.
expect_values_equal <- function(back, orig) {
  for (nm in names(orig)) {
    o <- as.character(orig[[nm]])
    o[!is.na(o) & o == ""] <- NA_character_
    expect_identical(as.character(back[[nm]]), o, info = nm)
  }
}

# ---- v5 / v8 round-trip on bundled CDISC data ------------------------------

test_that("v5 round-trips DM values and per-column metadata", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", check = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p, created = frozen)
  back <- read_xpt(p)

  expect_identical(names(back), names(dm))
  expect_values_equal(back, dm)
  m <- get_meta(back)
  expect_identical(m@dataset$name, "DM")
  expect_identical(m@dataset$records, nrow(dm))
  expect_identical(m@columns$STUDYID$label, "Study Identifier")
})

test_that("v5 round-trips ADSL including Date columns", {
  spec <- demo_spec()
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", check = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(adsl, p, created = frozen)
  back <- read_xpt(p)

  expect_values_equal(back, adsl)
  dcol <- names(adsl)[vapply(adsl, inherits, logical(1), "Date")][1]
  expect_s3_class(back[[dcol]], "Date")
  expect_equal(as.numeric(back[[dcol]]), as.numeric(adsl[[dcol]]))
})

test_that("v8 round-trips DM (extended member format)", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", check = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p, version = 8, created = frozen)
  back <- read_xpt(p)
  expect_identical(names(back), names(dm))
  expect_values_equal(back, dm)
})

# ---- byte stability ---------------------------------------------------------

test_that("two writes with a frozen timestamp are byte-identical", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", check = "off")
  p1 <- withr::local_tempfile(fileext = ".xpt")
  p2 <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p1, created = frozen)
  write_xpt(dm, p2, created = frozen)
  expect_identical(
    readBin(p1, "raw", n = file.info(p1)$size),
    readBin(p2, "raw", n = file.info(p2)$size)
  )
})

# ---- special missing values -------------------------------------------------

test_that("special missing tags survive a numeric round-trip (.A-.Z, ._)", {
  df <- data.frame(
    SUBJ = c("A", "B", "C", "D", "E"),
    VAL = c(1, NA, NA, NA, NA),
    stringsAsFactors = FALSE
  )
  attr(df$VAL, "sas_missing") <- c(NA, ".", "._", ".A", ".Z")
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_identical(attr(back$VAL, "sas_missing"), c(NA, ".", "._", ".A", ".Z"))
  expect_identical(back$VAL[1], 1)
})

# ---- temporal ---------------------------------------------------------------

test_that("Date, POSIXct, and vport_time columns round-trip", {
  df <- data.frame(SUBJ = c("A", "B", "C"), stringsAsFactors = FALSE)
  df$DT <- as.Date(c("2020-01-01", NA, "2021-06-15"))
  df$DTM <- as.POSIXct(
    c("2020-01-01 08:30:00", "2020-12-31 23:59:59", NA),
    tz = "UTC"
  )
  df$TM <- vport_time(c(0, 30600, 90061)) # incl. > 86400 (elapsed past 24h)
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)

  expect_s3_class(back$DT, "Date")
  # Values identical; like every numeric column, a missing day reads back
  # with a "." sas_missing tag (consistent with the special-missings test).
  expect_identical(as.numeric(back$DT), as.numeric(df$DT))
  expect_s3_class(back$DTM, "POSIXct")
  expect_equal(as.numeric(back$DTM), as.numeric(df$DTM))
  expect_true(is_vport_time(back$TM))
  expect_identical(unclass(back$TM), unclass(df$TM))
})

test_that("a non-temporal numeric format is NOT realized to a date", {
  df <- data.frame(SUBJ = "A", N = 12.5, stringsAsFactors = FALSE)
  # Give N an explicit numeric format via a spec-less meta path: float stays
  # float; no date realization.
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_type(back$N, "double")
  expect_false(inherits(back$N, "Date"))
})

# ---- decimal / boolean dispatch (F3 / context #3) --------------------------

test_that("a decimal column (R character) writes as a SAS numeric", {
  # decimal storage is R character; vartype must come from dataType, not
  # is.character(). Build meta with a decimal column.
  df <- data.frame(
    SUBJ = c("A", "B"),
    AVAL = c("1.50", "100.000"),
    stringsAsFactors = FALSE
  )
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L
    ),
    AVAL = list(
      itemOID = "IT.T.AVAL",
      name = "AVAL",
      dataType = "decimal",
      displayFormat = "8.3"
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  # AVAL comes back as a SAS numeric (double), values intact.
  expect_type(back$AVAL, "double")
  expect_equal(back$AVAL, c(1.5, 100))
})

# ---- encoding ---------------------------------------------------------------

test_that("a windows-1252 value round-trips byte-for-byte via recorded encoding", {
  df <- data.frame(SUBJ = "A", TXT = "café ™", stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, encoding = "windows-1252", created = frozen)
  back <- read_xpt(p)
  expect_identical(back$TXT, "café ™")
  expect_identical(get_meta(back)@dataset$encoding, "WINDOWS-1252")
})

test_that("encoding = US-ASCII on a non-ASCII value aborts loudly", {
  df <- data.frame(SUBJ = "A", TXT = "café", stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(
    write_xpt(df, p, encoding = "US-ASCII"),
    class = "vport_error_codec"
  )
})

# ---- F1: never silently truncate character data ----------------------------

test_that("F1: a char value longer than its declared length widens, not truncates", {
  df <- data.frame(SUBJ = "A", LONGTXT = "ABCDEFGHIJ", stringsAsFactors = FALSE)
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L
    ),
    LONGTXT = list(
      itemOID = "IT.T.LONGTXT",
      name = "LONGTXT",
      dataType = "string",
      length = 3L
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_identical(back$LONGTXT, "ABCDEFGHIJ") # full 10 chars, not truncated to 3
})

# ---- F2: numeric precision (declared short length ignored) ------------------

test_that("F2: a spec-declared numeric length < 8 still writes full precision", {
  df <- data.frame(SUBJ = "A", PI = pi, stringsAsFactors = FALSE)
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L
    ),
    PI = list(itemOID = "IT.T.PI", name = "PI", dataType = "float", length = 3L)
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_equal(back$PI, pi) # full double precision, not a 3-byte truncation
})

# ---- v8 long name / long label override ------------------------------------

test_that("v8 round-trips a name > 8 chars and a label > 40 chars", {
  df <- data.frame(SUBJ = "A", VERYLONGVARNAME = 1, stringsAsFactors = FALSE)
  long_label <- strrep("X", 60L)
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L
    ),
    VERYLONGVARNAME = list(
      itemOID = "IT.T.V",
      name = "VERYLONGVARNAME",
      dataType = "float",
      label = long_label
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, version = 8, created = frozen)
  back <- read_xpt(p)
  expect_true("VERYLONGVARNAME" %in% names(back))
  expect_identical(get_meta(back)@columns$VERYLONGVARNAME$label, long_label)
})

# ---- v5 nobs padding trap (all-character) ----------------------------------

test_that("v5 reads the exact row count for an all-character short-record frame", {
  # obs_length 6 (two 3-byte char cols) < 80; padding spans > 1 record.
  df <- data.frame(
    A = c("aaa", "bbb", "ccc", "ddd", "eee"),
    B = c("111", "222", "333", "444", "555"),
    stringsAsFactors = FALSE
  )
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_identical(nrow(back), 5L)
  expect_identical(back$A, df$A)
})

# ---- edge cases -------------------------------------------------------------

test_that("0-row and all-NA character frames round-trip", {
  df <- data.frame(
    SUBJ = character(0),
    N = numeric(0),
    stringsAsFactors = FALSE
  )
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_identical(nrow(back), 0L)
  expect_identical(names(back), c("SUBJ", "N"))

  # all-NA char column (width floored at 1) + genuine "" -> NA (C4).
  df2 <- data.frame(
    SUBJ = c("A", "B"),
    EMP = c(NA_character_, ""),
    stringsAsFactors = FALSE
  )
  attr(df2, "dataset_name") <- "TEST"
  p2 <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df2, p2, created = frozen)
  back2 <- read_xpt(p2)
  expect_true(all(is.na(back2$EMP))) # "" is indistinguishable from NA in XPORT
})

test_that("-0.0 round-trips as 0", {
  df <- data.frame(SUBJ = "A", Z = -0.0, stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  expect_identical(read_xpt(p)$Z, 0)
})

# ---- error matrix -----------------------------------------------------------

test_that("a factor column aborts with vport_error_type", {
  df <- data.frame(SUBJ = "A", F = factor("x"))
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_snapshot(write_xpt(df, p), error = TRUE)
  expect_error(write_xpt(df, p), class = "vport_error_type")
})

test_that("a list column aborts with vport_error_type", {
  df <- data.frame(SUBJ = "A")
  df$L <- list(1:3)
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p), class = "vport_error_type")
})

test_that("an invalid v5 variable name aborts", {
  df <- data.frame(SUBJ = "A", `TOOLONGNAME` = 1, check.names = FALSE)
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p), class = "vport_error_codec")
})

test_that("a numeric value over the IBM-370 limit aborts", {
  df <- data.frame(SUBJ = "A", BIG = 1e76)
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p), class = "vport_error_codec")
})

test_that("a v5 char column over 200 bytes aborts", {
  df <- data.frame(
    SUBJ = "A",
    WIDE = strrep("x", 201L),
    stringsAsFactors = FALSE
  )
  attr(df, "dataset_name") <- "TEST"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p), class = "vport_error_codec")
})

test_that("a truncated xpt file aborts on read", {
  spec <- demo_spec()
  dm <- apply_spec(cdisc_dm, spec, "DM", check = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p, created = frozen)
  raw <- readBin(p, "raw", n = file.info(p)$size)
  writeBin(raw[1:120], p) # chop mid-header
  expect_error(read_xpt(p), class = "vport_error_codec")
})

# ---- coverage: defensive branches ------------------------------------------

test_that("an invalid version aborts", {
  df <- data.frame(SUBJ = "A", stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "T"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p, version = 99), class = "vport_error_input")
})

test_that("a 0-column frame writes and reads a valid empty member", {
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(data.frame(), p, created = frozen)
  back <- read_xpt(p)
  expect_identical(ncol(back), 0L)
})

test_that("a v5 label over 40 chars truncates with a warning", {
  df <- data.frame(SUBJ = "A", X = 1, stringsAsFactors = FALSE)
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L
    ),
    X = list(
      itemOID = "IT.T.X",
      name = "X",
      dataType = "float",
      label = strrep("L", 50L)
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_warning(
    write_xpt(df, p, created = frozen),
    class = "vport_warning_encoding"
  )
})

test_that("a non-numeric decimal value aborts on write", {
  df <- data.frame(SUBJ = "A", AVAL = "not-a-number", stringsAsFactors = FALSE)
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L
    ),
    AVAL = list(itemOID = "IT.T.AVAL", name = "AVAL", dataType = "decimal")
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p), class = "vport_error_codec")
})

test_that("a column absent from the meta is inferred from the frame", {
  df <- data.frame(SUBJ = "A", EXTRA = 42, stringsAsFactors = FALSE)
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_equal(back$EXTRA, 42)
})

test_that("read_xpt honours an explicit encoding override", {
  df <- data.frame(SUBJ = "A", TXT = "café", stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "T"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, encoding = "windows-1252", created = frozen)
  back <- read_xpt(p, encoding = "windows-1252")
  expect_identical(back$TXT, "café")
})

# ---- coverage: SAS-compat read paths (crafted fixtures) --------------------

test_that("the reader zero-pads numerics narrower than 8 bytes (real SAS)", {
  # Real SAS XPORT stores numerics at 2-8 bytes (high-order IBM bytes only).
  # Craft a v5 file with a single 5-byte numeric field holding 1.0.
  recs <- list(list(
    name = "N",
    label = "",
    vartype = 1L,
    length = 5L,
    format_name = "",
    formatl = 0L,
    formatd = 0L,
    bytes = raw(0)
  ))
  ibm5 <- vport:::.ieee_to_ibm(1.0)[1:5]
  bytes <- c(
    vport:::.xpt_library_header(5L, frozen),
    vport:::.xpt_member_header("T", "", 1L, 5L, frozen),
    vport:::.xpt_namestr_block(recs, 5L),
    vport:::.xpt_obs_header(1L, 5L),
    vport:::.pad_record(ibm5, 80L)
  )
  p <- withr::local_tempfile(fileext = ".xpt")
  writeBin(bytes, p)
  back <- read_xpt(p)
  expect_equal(back$N, 1.0)
})

test_that("the reader parses LABELV9 long-name/long-label extension records", {
  name <- "LONGVARNAME12345" # 16 > 8
  label <- strrep("Y", 50L) # > 40
  recs <- list(list(
    name = name,
    label = "",
    vartype = 2L,
    length = 3L,
    format_name = "",
    formatl = 0L,
    formatd = 0L,
    bytes = raw(0)
  ))
  ext_header <- vport:::.str_to_raw(
    paste0(
      "HEADER RECORD*******",
      vport:::.pad_to("LABELV9", 7L),
      " HEADER RECORD!!!!!!!",
      formatC(1L, width = 30L, format = "d", flag = " ")
    ),
    80L
  )
  chunk <- c(
    vport:::.int_to_pib2(1L),
    vport:::.int_to_pib2(nchar(name)),
    vport:::.int_to_pib2(nchar(label)),
    vport:::.int_to_pib2(0L),
    vport:::.int_to_pib2(0L),
    charToRaw(name),
    charToRaw(label)
  )
  bytes <- c(
    vport:::.xpt_library_header(8L, frozen),
    vport:::.xpt_member_header(name, "", 1L, 8L, frozen),
    vport:::.xpt_namestr_block(recs, 8L),
    ext_header,
    vport:::.pad_record(chunk, 80L),
    vport:::.xpt_obs_header(1L, 8L),
    vport:::.pad_record(charToRaw("abc"), 80L)
  )
  p <- withr::local_tempfile(fileext = ".xpt")
  writeBin(bytes, p)
  back <- read_xpt(p)
  expect_true(name %in% names(back))
  expect_identical(get_meta(back)@columns[[name]]$label, label)
})

test_that("a non-meta column with a label attr and a meta string without length", {
  df <- data.frame(SUBJ = "A", EXTRA = "hello", stringsAsFactors = FALSE)
  attr(df$EXTRA, "label") <- "An extra column"
  # meta describes SUBJ as a string WITHOUT a declared length.
  cols <- list(
    SUBJ = list(itemOID = "IT.T.SUBJ", name = "SUBJ", dataType = "string")
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_identical(back$EXTRA, "hello")
  expect_identical(get_meta(back)@columns$EXTRA$label, "An extra column")
})

# ---- review findings: regression tests -------------------------------------

test_that("a blank string in a decimal column writes as missing, not an abort", {
  # Review HIGH: "" in a character-backed numeric is an intended missing.
  df <- data.frame(
    SUBJ = c("A", "B", "C"),
    AVAL = c("1.5", "", "3.0"),
    stringsAsFactors = FALSE
  )
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L
    ),
    AVAL = list(
      itemOID = "IT.T.AVAL",
      name = "AVAL",
      dataType = "decimal",
      displayFormat = "8.1"
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_no_error(write_xpt(df, p, created = frozen))
  back <- read_xpt(p)
  expect_equal(back$AVAL[c(1, 3)], c(1.5, 3.0))
  expect_true(is.na(back$AVAL[2]))
})

test_that("an infinite numeric value aborts loudly (no silent missing)", {
  # Review LOW: Inf cannot be stored; fail loud like finite overflow.
  df <- data.frame(SUBJ = "A", X = Inf)
  attr(df, "dataset_name") <- "T"
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p), class = "vport_error_codec")
})

# ---- review 2026-06: header/label text through the encoding SSOT ------------

test_that("a non-ASCII dataset label keeps 80-byte framing and round-trips", {
  # Review BLOCKER: the member-header label was char-padded, not byte-padded,
  # so a multibyte label misaligned every following record.
  df <- data.frame(SUBJ = "A", N = 1, stringsAsFactors = FALSE)
  ds <- vport:::.assemble_dataset_meta(
    itemGroupOID = "IG.T",
    name = "T",
    label = "Étude de démographie"
  )
  meta <- vport:::vport_meta_class(dataset = ds, columns = list())
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  expect_identical(file.info(p)$size %% 80, 0)
  back <- read_xpt(p)
  expect_identical(
    get_meta(back)@dataset$label,
    "Étude de démographie"
  )
})

test_that("read_xpt survives windows-1252 variable labels (incl. its own output)", {
  # Review BLOCKER: .raw_to_str regexed header bytes without useBytes, so any
  # non-UTF-8 label byte crashed the reader with a raw base error.
  df <- data.frame(SUBJ = "A", PAYS = "FR", stringsAsFactors = FALSE)
  cols <- list(
    PAYS = list(
      itemOID = "IT.T.PAYS",
      name = "PAYS",
      dataType = "string",
      label = "Pays de résidence"
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, encoding = "windows-1252", created = frozen)
  back <- read_xpt(p)
  expect_identical(
    get_meta(back)@columns$PAYS$label,
    "Pays de résidence"
  )
})

test_that("v5 label truncation at 40 bytes backs off to a character boundary", {
  # Review BLOCKER companion: a byte-40 chop split a multibyte character,
  # leaving invalid UTF-8 on disk and an unreadable file.
  df <- data.frame(SUBJ = "A", X = 1, stringsAsFactors = FALSE)
  cols <- list(
    X = list(
      itemOID = "IT.T.X",
      name = "X",
      dataType = "float",
      label = paste0(strrep("a", 39L), "étude") # byte 40 = lead byte of e-acute
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_warning(
    write_xpt(df, p, created = frozen),
    class = "vport_warning_encoding"
  )
  back <- read_xpt(p)
  expect_identical(get_meta(back)@columns$X$label, strrep("a", 39L))
})

test_that("the header timestamp is locale-independent", {
  # Review BLOCKER: format(%b) used LC_TIME, so a French locale wrote
  # "JANV." (18-char datetime) and shifted every header field after it.
  probe <- tryCatch(
    withr::with_locale(c(LC_TIME = "fr_FR.UTF-8"), TRUE),
    condition = function(c) FALSE
  )
  skip_if_not(probe, "fr_FR.UTF-8 locale not available")
  df <- data.frame(SUBJ = "A", N = 1, stringsAsFactors = FALSE)
  attr(df, "dataset_name") <- "T"
  p_c <- withr::local_tempfile(fileext = ".xpt")
  p_fr <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p_c, created = frozen)
  withr::with_locale(
    c(LC_TIME = "fr_FR.UTF-8"),
    write_xpt(df, p_fr, created = frozen)
  )
  expect_identical(
    readBin(p_c, "raw", n = file.info(p_c)$size),
    readBin(p_fr, "raw", n = file.info(p_fr)$size)
  )
})

test_that("the v8 namestr label-length field counts bytes, not characters", {
  # Review: a multibyte label wrote nchar() (chars) into the 2-byte length
  # field, so third-party readers trusting it misread the label.
  label <- "café™ étude" # 11 chars, 15 UTF-8 bytes
  df <- data.frame(SUBJ = "A", stringsAsFactors = FALSE)
  cols <- list(
    SUBJ = list(
      itemOID = "IT.T.SUBJ",
      name = "SUBJ",
      dataType = "string",
      length = 1L,
      label = label
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, version = 8, created = frozen)
  bytes <- readBin(p, "raw", n = file.info(p)$size)
  # 8 header records (3 library + 5 member) = 640 bytes; the v8 namestr holds
  # the label-length field at offset 120 (after the 88-byte base + 32-byte
  # long name).
  label_len_field <- vport:::.pib2_to_int(bytes[(640L + 121L):(640L + 122L)])
  expect_identical(label_len_field, length(charToRaw(label)))
})

test_that("a non-ASCII dataset name aborts instead of corrupting the header", {
  df <- data.frame(SUBJ = "A", stringsAsFactors = FALSE)
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "ÉTUDE")
  meta <- vport:::vport_meta_class(dataset = ds, columns = list())
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p), class = "vport_error_codec")
})

test_that("a dataset label over 40 bytes truncates with a warning", {
  df <- data.frame(SUBJ = "A", stringsAsFactors = FALSE)
  ds <- vport:::.assemble_dataset_meta(
    itemGroupOID = "IG.T",
    name = "T",
    label = strrep("L", 50L)
  )
  meta <- vport:::vport_meta_class(dataset = ds, columns = list())
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_warning(
    write_xpt(df, p, created = frozen),
    class = "vport_warning_encoding"
  )
  back <- read_xpt(p)
  expect_identical(get_meta(back)@dataset$label, strrep("L", 40L))
})

test_that("encoding detection considers labels, not just data values", {
  # Data is pure ASCII but the label is windows-1252; detection must not
  # default to UTF-8 and mis-decode the label.
  df <- data.frame(SUBJ = "A", PAYS = "FR", stringsAsFactors = FALSE)
  cols <- list(
    PAYS = list(
      itemOID = "IT.T.PAYS",
      name = "PAYS",
      dataType = "string",
      label = "Résidence"
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, encoding = "windows-1252", created = frozen)
  back <- read_xpt(p)
  expect_identical(get_meta(back)@columns$PAYS$label, "Résidence")
})

test_that("a character-backed date column aborts on write, no garbage days (review B7)", {
  # "2014" used to coerce via as.numeric() and silently write SAS day 2014
  # (= 1965-07-07); the lost-coercion guard never saw it.
  df <- data.frame(
    SUBJ = c("A", "B"),
    ADT = c("2014", "2015"),
    stringsAsFactors = FALSE
  )
  cols <- list(
    ADT = list(
      itemOID = "IT.T.ADT",
      name = "ADT",
      dataType = "date",
      displayFormat = "DATE9."
    )
  )
  ds <- vport:::.assemble_dataset_meta(itemGroupOID = "IG.T", name = "T")
  meta <- vport:::vport_meta_class(dataset = ds, columns = cols)
  df <- set_meta(df, meta)
  p <- withr::local_tempfile(fileext = ".xpt")
  expect_error(write_xpt(df, p), class = "vport_error_codec")
})

test_that("special-missing tags survive a temporal round-trip (review codec C3)", {
  # .realize_temporal dropped the sas_missing attr on read, so a second write
  # degraded .A to plain missing.
  df <- data.frame(SUBJ = c("A", "B"), stringsAsFactors = FALSE)
  df$ADT <- as.Date(c("2020-01-01", NA))
  attr(df$ADT, "sas_missing") <- c(NA, ".A")
  attr(df, "dataset_name") <- "T"
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(df, p, created = frozen)
  back <- read_xpt(p)
  expect_s3_class(back$ADT, "Date")
  expect_identical(attr(back$ADT, "sas_missing"), c(NA, ".A"))
})
