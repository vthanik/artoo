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
  # The bundled pilot spec declares STUDYID length 7; the data needs 12
  # bytes, so the writer widens and says so.
  expect_warning(write_xpt(dm, p), class = "artoo_warning_encoding")
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

test_that("format = restricts a mixed directory to the named formats", {
  # The motivating case: one dataset stored twice. The full inventory reports
  # both, because it reports what is on disk; the restriction picks a half.
  dm <- demo_dm()
  d <- withr::local_tempdir()
  write_json(dm, file.path(d, "dm.json"))
  write_rds(dm, file.path(d, "dm.rds"))
  write_xpt(dm, file.path(d, "dm.xpt"))

  expect_identical(nrow(members(d)), 3L)
  expect_identical(members(d, format = "json")$file, "dm.json")

  # Several names are a SET, not a precedence order: both are listed, and
  # nothing about the call says which one wins.
  both <- members(d, format = c("json", "rds"))
  expect_setequal(both$file, c("dm.json", "dm.rds"))
  expect_setequal(both$format, c("json", "rds"))
})

test_that("format = names a format, not an extension", {
  # The registry maps one name to several extensions, so "parquet" must claim
  # .pq as well. An extension-shaped argument would inventory half a folder.
  skip_if_not_installed("nanoparquet")
  dm <- demo_dm()
  d <- withr::local_tempdir()
  write_parquet(dm, file.path(d, "dm.parquet"))
  file.copy(file.path(d, "dm.parquet"), file.path(d, "other.pq"))

  expect_setequal(
    members(d, format = "parquet")$file,
    c("dm.parquet", "other.pq")
  )
  # And the extension spelling is refused, in the same words read_dataset()
  # uses for it.
  expect_error(members(d, format = "pq"), class = "artoo_error_codec")
})

test_that("naming a file the restriction excludes aborts", {
  # Not an empty inventory: that is indistinguishable from an empty
  # directory, and the two mean opposite things -- one is an honest answer
  # about a folder, the other is two arguments contradicting each other.
  dm <- demo_dm()
  # A stable basename: the message names the file, and a random tempfile name
  # would churn the snapshot on every run.
  p <- file.path(withr::local_tempdir(), "dm.json")
  write_json(dm, p)

  expect_identical(nrow(members(p, format = "json")), 1L)
  expect_snapshot(members(p, format = "xpt"), error = TRUE)
  expect_error(members(p, format = "xpt"), class = "artoo_error_input")

  # A DIRECTORY holding nothing of the named format is a real result, and
  # still returns the empty inventory.
  d <- withr::local_tempdir()
  write_json(dm, file.path(d, "dm.json"))
  expect_identical(nrow(members(d, format = "xpt")), 0L)
})

test_that("an unusable format restriction aborts", {
  d <- withr::local_tempdir()
  expect_snapshot(members(d, format = character(0)), error = TRUE)
  expect_error(members(d, format = character(0)), class = "artoo_error_input")
  expect_error(members(d, format = 1L), class = "artoo_error_input")
  expect_error(members(d, format = "nosuch"), class = "artoo_error_codec")
  expect_error(members(d, format = NA_character_), class = "artoo_error_codec")
})

test_that("format = NULL is the released behaviour, unchanged", {
  # members() shipped in 0.1.3 without this argument. The default must return
  # exactly what it returned then, or every caller on CRAN changes meaning.
  dm <- demo_dm()
  d <- withr::local_tempdir()
  write_json(dm, file.path(d, "dm.json"))
  write_rds(dm, file.path(d, "dm.rds"))
  expect_identical(members(d), members(d, format = NULL))
  expect_identical(nrow(members(d)), 2L)
})
