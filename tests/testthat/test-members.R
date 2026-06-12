# Tests for members(): the format-neutral dataset inventory.

demo_dm <- function() {
  apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
}

test_that("members() on a single-dataset file reports one row", {
  dm <- demo_dm()
  for (ext in c("json", "rds")) {
    p <- withr::local_tempfile(fileext = paste0(".", ext))
    write_dataset(dm, p)
    m <- members(p)
    expect_s3_class(m, "artoo_members")
    expect_identical(nrow(m), 1L)
    expect_identical(m$member, "DM")
    expect_identical(m$records, nrow(dm))
    expect_identical(m$variables, ncol(dm))
    expect_identical(m$format, ext)
    expect_identical(m$file, basename(p))
  }
})

test_that("members() lists every member of a multi-member xpt, matching xpt_members()", {
  dm <- demo_dm()
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  p <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(dm, p)
  p2 <- withr::local_tempfile(fileext = ".xpt")
  write_xpt(adsl, p2)
  multi <- withr::local_tempfile(fileext = ".xpt")
  writeBin(
    c(
      readBin(p, "raw", file.size(p)),
      readBin(p2, "raw", file.size(p2))[-(1:240)]
    ),
    multi
  )
  m <- members(multi)
  xm <- xpt_members(multi)
  expect_identical(nrow(m), nrow(xm))
  expect_identical(m$member, xm$name)
  expect_identical(m$records, xm$nobs)
  expect_identical(m$variables, xm$nvars)
  expect_true(all(m$format == "xpt"))
})

test_that("members() inventories a directory, skipping non-dataset files", {
  dm <- demo_dm()
  d <- withr::local_tempdir()
  write_json(dm, file.path(d, "dm.json"))
  write_rds(dm, file.path(d, "dm.rds"))
  writeLines("not a dataset", file.path(d, "readme.txt"))
  m <- members(d)
  expect_identical(nrow(m), 2L)
  expect_setequal(m$file, c("dm.json", "dm.rds"))
  expect_true(all(m$member == "DM"))
  expect_setequal(m$format, c("json", "rds"))
})

test_that("members() on a directory with no dataset files returns zero rows", {
  d <- withr::local_tempdir()
  writeLines("hi", file.path(d, "notes.txt"))
  m <- members(d)
  expect_s3_class(m, "artoo_members")
  expect_identical(nrow(m), 0L)
})

test_that("members() aborts on an existing file whose extension no codec claims", {
  p <- withr::local_tempfile(fileext = ".docx")
  file.create(p)
  expect_error(members(p), class = "artoo_error_codec")
})

test_that("members() aborts on a path that does not exist", {
  expect_error(
    members(withr::local_tempfile(fileext = ".json")),
    class = "artoo_error_input"
  )
})

test_that("print is the left-aligned members pane (snapshot)", {
  dm <- demo_dm()
  d <- withr::local_tempdir()
  write_json(dm, file.path(d, "dm.json"))
  expect_snapshot(print(members(d)))
})
