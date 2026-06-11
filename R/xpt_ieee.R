# xpt_ieee.R -- IEEE 754 <-> IBM 370 floating-point conversion.
#
# The byte-level core of the xpt codec, ported from the herald archive
# (identical float math in both archives; herald chosen per the "latest wins"
# rule). artoo's additions over the port: no vctrs dependency, and an optional
# `missing` tag vector so extended special missings (.A-.Z, ._) survive the
# WRITE path -- the one place v0 was lossy (it read them but wrote them all
# back as the standard "." indicator).
#
# IBM 370 double (8 bytes): bit 0 sign, bits 1-7 exponent (bias 64, base-16),
# bits 8-63 fraction (56 bits, base-16 normalised).
# IEEE 754 double (8 bytes): bit 0 sign, bits 1-11 exponent (bias 1023,
# base-2), bits 12-63 fraction (52 bits, implicit leading 1).

# Standard SAS missing (.) byte pattern: indicator byte then seven zeros.
#' @noRd
.sas_missing_raw <- function() {
  as.raw(c(0x2E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
}

# Map SAS missing tags ("." / "._" / ".A"-".Z") to their indicator byte
# (integer), NA for an untagged / unrecognised entry.
#' @noRd
.sas_indicator_byte <- function(tags) {
  out <- rep(NA_integer_, length(tags))
  if (!length(tags)) {
    return(out)
  }
  ok <- !is.na(tags)
  out[ok & tags == "."] <- 0x2EL
  out[ok & tags == "._"] <- 0x5FL
  letr <- ok & grepl("^\\.[A-Z]$", tags)
  if (any(letr)) {
    out[letr] <- vapply(substr(tags[letr], 2L, 2L), utf8ToInt, integer(1))
  }
  out
}

# TRUE when 8 raw bytes are a SAS missing value (bytes 2-8 zero, byte 1 is a
# recognised indicator: 0x2E ".", 0x5F "._", or 0x41-0x5A ".A"-".Z").
#' @noRd
.is_sas_missing <- function(raw8) {
  if (!all(raw8[2:8] == as.raw(0x00))) {
    return(FALSE)
  }
  first <- as.integer(raw8[1L])
  first == 0x2EL || first == 0x5FL || (first >= 0x41L && first <= 0x5AL)
}

# Convert IEEE 754 doubles to IBM 370 bytes (vectorised). `missing`, when
# given, is a character vector aligned to `x` carrying the SAS missing tag for
# each NA position so the exact indicator byte (.A-.Z, ._) is written back;
# untagged NAs and non-finite values write the standard "." missing.
#' @noRd
.ieee_to_ibm <- function(x, missing = NULL) {
  x <- as.double(x)
  n <- length(x)
  if (n == 0L) {
    return(raw(0L))
  }

  result <- raw(8L * n)

  # Special values -> SAS missing (NA, NaN, Inf, -Inf).
  is_special <- !is.finite(x)
  if (any(is_special)) {
    sp_pos <- which(is_special)
    dest_sp <- as.integer(outer(0L:7L, (sp_pos - 1L) * 8L + 1L, "+"))
    result[dest_sp] <- rep(.sas_missing_raw(), length(sp_pos))
    # Stamp the exact special-missing indicator where one was supplied.
    if (!is.null(missing)) {
      ind <- .sas_indicator_byte(missing[sp_pos])
      tagged <- !is.na(ind)
      if (any(tagged)) {
        first_pos <- (sp_pos[tagged] - 1L) * 8L + 1L
        result[first_pos] <- as.raw(ind[tagged])
      }
    }
  }

  # Non-zero regular values (zeros stay zero-initialised).
  is_nz <- !is_special & x != 0
  if (!any(is_nz)) {
    return(result)
  }

  xnz <- x[is_nz]
  nnz <- length(xnz)

  # All IEEE big-endian bytes at once (one writeBin for the whole vector).
  ieee_bytes <- writeBin(xnz, raw(), size = 8L, endian = "big")
  m <- matrix(as.integer(ieee_bytes), nrow = 8L) # 8 x nnz integer matrix

  b1 <- m[1L, ]
  b2 <- m[2L, ]

  sign_bit <- bitwShiftR(b1, 7L)
  ieee_exp <- bitwOr(bitwShiftL(bitwAnd(b1, 0x7FL), 4L), bitwShiftR(b2, 4L))
  fexp <- ieee_exp - 1023L

  # IEEE: value = 2^fexp x mantissa; IBM: value = 16^(ibm_exp-64) x frac/2^56.
  # ibm_exp = 64 + ceil((fexp+1)/4); lshift = fexp+4 - 4(ibm_exp-64) in {0..3}.
  ibm_exp <- 64L + ((fexp + 4L) %/% 4L)
  lshift <- fexp + 4L - 4L * (ibm_exp - 64L)

  is_subnorm <- ieee_exp == 0L # treat as zero (leave zeroed)
  is_overflow <- ibm_exp > 127L # -> SAS missing
  is_underflow <- ibm_exp < 0L # -> zero (leave zeroed)
  is_reg <- !is_subnorm & !is_overflow & !is_underflow

  if (any(is_overflow)) {
    ov_global <- which(is_nz)[is_overflow]
    dest_ov <- as.integer(outer(0L:7L, (ov_global - 1L) * 8L + 1L, "+"))
    result[dest_ov] <- rep(.sas_missing_raw(), sum(is_overflow))
  }

  if (!any(is_reg)) {
    return(result)
  }

  # Regular values: build the 8 x nreg output matrix.
  frac_m <- m[2:8, is_reg, drop = FALSE] # 7 x nreg (bytes 2-8 = mantissa)
  ib_exp <- ibm_exp[is_reg]
  ls <- lshift[is_reg]
  sb <- sign_bit[is_reg]

  # Set implicit leading 1, clear exponent bits from byte 2 (row 1 of frac_m).
  frac_m[1L, ] <- bitwOr(bitwAnd(frac_m[1L, ], 0x0FL), 0x10L)

  # Left-shift the 7-byte mantissa by ls bits (0-3) to align to IBM hex digits.
  # When ls == 0: (x << 0 | y >> 8) & 0xFF = x (no-op, correct).
  for (j in seq_len(6L)) {
    frac_m[j, ] <- bitwAnd(
      bitwOr(
        bitwShiftL(frac_m[j, ], ls),
        bitwShiftR(frac_m[j + 1L, ], 8L - ls)
      ),
      0xFFL
    )
  }
  frac_m[7L, ] <- bitwAnd(bitwShiftL(frac_m[7L, ], ls), 0xFFL)

  # Assemble: byte1 = sign|ibm_exp, bytes 2-8 = shifted mantissa.
  out_m <- rbind(bitwOr(bitwShiftL(sb, 7L), ib_exp), frac_m) # 8 x nreg

  reg_global <- which(is_nz)[is_reg]
  dest_reg <- as.integer(outer(0L:7L, (reg_global - 1L) * 8L + 1L, "+"))
  result[dest_reg] <- as.raw(as.integer(out_m))

  result
}

# Convert IBM 370 bytes back to IEEE 754 doubles (vectorised). Missing values
# decode to NA with their SAS tag recorded in the `sas_missing` attribute
# (".", "._", or ".A"-".Z"), so a subsequent .ieee_to_ibm() can write them
# back exactly.
#' @noRd
.ibm_to_ieee <- function(raw_vec) {
  n <- length(raw_vec) %/% 8L
  if (n == 0L) {
    return(numeric(0L))
  }

  m <- matrix(as.integer(raw_vec), nrow = 8L) # 8 x n: each column one double
  b1 <- m[1L, ]

  col_sums <- colSums(m)
  lower_sums <- colSums(m[2:8, , drop = FALSE])
  is_zero <- col_sums == 0L
  is_missing <- lower_sums == 0L &
    (b1 == 0x2EL | b1 == 0x5FL | (b1 >= 0x41L & b1 <= 0x5AL))
  regular <- !is_zero & !is_missing

  result <- numeric(n)
  result[is_missing] <- NA_real_

  # Tag each missing slot with its SAS indicator; NA elsewhere.
  if (any(is_missing)) {
    tags <- rep(NA_character_, n)
    miss_b1 <- b1[is_missing]
    tags[is_missing] <- ifelse(
      miss_b1 == 0x2EL,
      ".",
      ifelse(
        miss_b1 == 0x5FL,
        "._",
        paste0(".", intToUtf8(miss_b1, multiple = TRUE))
      )
    )
    attr(result, "sas_missing") <- tags
  }

  if (!any(regular)) {
    return(result)
  }

  # IBM 370: value = (-1)^s x 16^(E-64) x F, F the base-256 fraction of bytes
  # 2-8. Pure floating-point arithmetic, no bit-shifting.
  reg_m <- m[, regular, drop = FALSE]
  reg_b1 <- b1[regular]

  sign_v <- ifelse(reg_b1 >= 128L, -1, 1)
  ibm_exp <- reg_b1 %% 128L # low 7 bits = exponent
  weights <- 256^(6:0)
  frac_val <- colSums(reg_m[2:8, , drop = FALSE] * weights) / (256^7)

  result[regular] <- sign_v * (16^(ibm_exp - 64L)) * frac_val

  result
}
