# The any-to-any losslessness matrix -- the acceptance test of the flagship
# promise. Every ordered pair of full-metadata formats (json, parquet, rds)
# must round-trip the torture frame (all 10 dataTypes, non-ASCII, special
# missings on plain and temporal columns) with data, tags, and meta identical.
# xpt joins on its documented honesty contract (C3/C4): values, labels,
# formats, informats, and tags survive; dataType narrows to what NAMESTR can
# record (boolean/integer/decimal come back numeric, "" comes back NA).

.full_formats <- function() {
  fmts <- c("json", "rds")
  if (requireNamespace("nanoparquet", quietly = TRUE)) {
    fmts <- c(fmts, "parquet")
  }
  fmts
}

.write_read <- function(df, fmt) {
  p <- withr::local_tempfile(
    fileext = paste0(".", fmt),
    .local_envir = parent.frame()
  )
  write_dataset(df, p, format = fmt)
  read_dataset(p, format = fmt)
}

test_that("every full-metadata format round-trips the torture frame", {
  src <- .torture_frame()
  for (fmt in .full_formats()) {
    back <- .write_read(src, fmt)
    expect_lossless(src, back, via = fmt)
  }
})

test_that("every ordered pair of full-metadata formats chains losslessly", {
  src <- .torture_frame()
  fmts <- .full_formats()
  for (f in fmts) {
    a <- .write_read(src, f)
    for (g in setdiff(fmts, f)) {
      b <- .write_read(a, g)
      expect_lossless(src, b, via = paste(f, "->", g))
    }
  }
})

test_that("the conformed demo datasets chain through every format pair", {
  spec <- vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
  fmts <- .full_formats()
  for (ds in c("DM", "ADSL")) {
    src <- apply_spec(
      if (ds == "DM") cdisc_dm else cdisc_adsl,
      spec,
      ds,
      on_error = "off"
    )
    for (f in fmts) {
      a <- .write_read(src, f)
      for (g in setdiff(fmts, f)) {
        expect_lossless(src, .write_read(a, g), via = paste(ds, f, "->", g))
      }
    }
  }
})

test_that("xpt legs preserve values, tags, and the carried metadata", {
  # The xpt-representable slice of the torture frame (boolean/integer/decimal
  # narrow to numeric in NAMESTR -- the documented C3 contract -- so they are
  # exercised in the value comparison but not the meta-identity one).
  src <- .torture_frame()
  xpt_cols <- c("USUBJID", "AVAL", "DVAL", "ADT", "ADTM", "ATM", "REFURI")
  src <- set_meta(
    src[xpt_cols],
    vport:::.meta_select_columns(get_meta(src), xpt_cols)
  )

  for (mid in .full_formats()) {
    p1 <- withr::local_tempfile(fileext = ".xpt")
    write_xpt(src, p1, version = 8)
    a <- read_xpt(p1)
    b <- .write_read(a, mid)
    p2 <- withr::local_tempfile(fileext = ".xpt")
    write_xpt(b, p2, version = 8)
    c2 <- read_xpt(p2)
    # Frame-level identity between the two xpt reads: nothing decayed on the
    # way through the middle format.
    expect_lossless(a, c2, via = paste("xpt ->", mid, "-> xpt"))
    # And the xpt read itself preserved the source values and tags.
    for (nm in names(src)) {
      av <- a[[nm]]
      sv <- src[[nm]]
      attributes(av) <- NULL
      attributes(sv) <- NULL
      expect_identical(av, sv, label = paste("xpt values for", nm))
    }
    expect_identical(
      get_meta(a)@columns$ADT$informat,
      "YYMMDD10."
    )
  }
})
