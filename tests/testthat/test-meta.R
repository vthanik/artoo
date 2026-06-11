# Tests for the vport_meta spine: build meta from a spec, the single
# Dataset-JSON serializer + its inverse (round-trip identity), and the
# get_meta()/set_meta()/is_vport_meta() frame bridge.

demo_spec <- function() {
  vport_spec(
    cdisc_datasets,
    cdisc_variables,
    codelists = cdisc_codelists
  )
}

# ---- .meta_from_spec --------------------------------------------------------

test_that(".meta_from_spec builds a vport_meta for one dataset", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")

  expect_true(is_vport_meta(meta))
  # One column entry per ADSL variable, keyed by variable name.
  vars <- spec_variables(spec, "ADSL")$variable
  expect_identical(names(meta@columns), vars)
  # Dataset-level fields mirror the spec.
  expect_identical(meta@dataset$name, "ADSL")
  expect_identical(meta@dataset$label, "Subject-Level Analysis Dataset")
  expect_identical(meta@dataset$itemGroupOID, "IG.ADSL")
})

test_that(".meta_from_spec carries CDISC column attributes", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  studyid <- meta@columns$STUDYID

  expect_identical(studyid$name, "STUDYID")
  expect_identical(studyid$label, "Study Identifier")
  expect_identical(studyid$dataType, "string")
  expect_identical(studyid$length, 12L)
  expect_identical(studyid$itemOID, "IT.ADSL.STUDYID")
})

test_that(".meta_from_spec omits absent (NA) attributes", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  # STUDYID has no codelist / displayFormat in the demo spec; those keys
  # are dropped, not stored as NA (Dataset-JSON omits absent attributes).
  expect_false("codelist" %in% names(meta@columns$STUDYID))
  expect_false("displayFormat" %in% names(meta@columns$STUDYID))
  expect_false("targetDataType" %in% names(meta@columns$STUDYID))
})

test_that(".meta_from_spec rejects an unknown dataset", {
  spec <- demo_spec()
  expect_error(
    vport:::.meta_from_spec(spec, "NOPE"),
    class = "vport_error_input"
  )
})

# ---- serializer round-trip --------------------------------------------------

test_that(".meta_to_datasetjson produces parseable Dataset-JSON metadata", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  json <- vport:::.meta_to_datasetjson(meta)

  expect_type(json, "character")
  expect_length(json, 1L)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_identical(parsed$datasetJSONVersion, "1.1.0")
  expect_identical(parsed$itemGroupOID, "IG.ADSL")
  expect_identical(parsed$name, "ADSL")
  # columns is a JSON array, one entry per variable, in spec order.
  expect_length(parsed$columns, length(meta@columns))
  expect_identical(parsed$columns[[1]]$name, "STUDYID")
})

test_that("meta round-trips losslessly through Dataset-JSON", {
  spec <- demo_spec()
  for (ds in spec_datasets(spec)) {
    meta <- vport:::.meta_from_spec(spec, ds)
    back <- vport:::.meta_from_datasetjson(vport:::.meta_to_datasetjson(meta))
    expect_identical(back@columns, meta@columns, info = ds)
    expect_identical(back@dataset, meta@dataset, info = ds)
  }
})

test_that("integer column attributes survive the round-trip as integers", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  back <- vport:::.meta_from_datasetjson(vport:::.meta_to_datasetjson(meta))
  expect_type(back@columns$STUDYID$length, "integer")
})

# ---- C2: source-encoding extension (_vport namespace) ----------------------

test_that("source encoding rides the _vport extension, never a CDISC key", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  meta <- S7::set_props(
    meta,
    dataset = c(meta@dataset, list(encoding = "WINDOWS-1252"))
  )

  # extensions = TRUE: encoding emitted ONLY under _vport, not top-level.
  ext <- jsonlite::fromJSON(
    vport:::.meta_to_datasetjson(meta, extensions = TRUE),
    simplifyVector = FALSE
  )
  expect_identical(ext[["_vport"]]$sourceEncoding, "WINDOWS-1252")
  expect_false("encoding" %in% names(ext))

  # extensions = FALSE (the default, Dataset-JSON FILE path): no _vport,
  # and no stray encoding key -- strict CDISC.
  strict <- jsonlite::fromJSON(
    vport:::.meta_to_datasetjson(meta, extensions = FALSE),
    simplifyVector = FALSE
  )
  expect_false("_vport" %in% names(strict))
  expect_false("encoding" %in% names(strict))
})

test_that("the _vport sourceEncoding round-trips back into @dataset$encoding", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  meta <- S7::set_props(
    meta,
    dataset = c(meta@dataset, list(encoding = "WINDOWS-1252"))
  )
  json <- vport:::.meta_to_datasetjson(meta, extensions = TRUE)
  back <- vport:::.meta_from_datasetjson(json)
  expect_identical(back@dataset$encoding, "WINDOWS-1252")
})

test_that("a meta without encoding is byte-identical across the round-trip", {
  # No regression: extensions default FALSE and encoding drops as NULL.
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "DM")
  back <- vport:::.meta_from_datasetjson(vport:::.meta_to_datasetjson(meta))
  expect_identical(back@dataset, meta@dataset)
  expect_false("encoding" %in% names(back@dataset))
})

# ---- get_meta / set_meta bridge --------------------------------------------

test_that("set_meta then get_meta round-trips through a frame attribute", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  x <- set_meta(cdisc_adsl, meta)

  expect_s3_class(x, "data.frame")
  expect_true(is.character(attr(x, "metadata_json")))
  got <- get_meta(x)
  expect_true(is_vport_meta(got))
  expect_identical(got@columns, meta@columns)
})

test_that("get_meta aborts on a frame carrying no metadata", {
  expect_error(get_meta(cdisc_adsl), class = "vport_error_input")
  expect_snapshot(get_meta(cdisc_adsl), error = TRUE)
})

# ---- Wave 3: set_meta projects label / format.sas onto columns -------------

test_that("set_meta projects the column label and SAS format onto the frame", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  x <- set_meta(cdisc_adsl, meta)
  # STUDYID carries a label in the spec; the projected attr matches the meta.
  expect_identical(
    attr(x$STUDYID, "label", exact = TRUE),
    meta@columns$STUDYID$label
  )
})

test_that("set_meta strips a stale label when the new meta has none", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  x <- set_meta(cdisc_adsl, meta)
  expect_false(is.null(attr(x$STUDYID, "label", exact = TRUE)))
  # Re-stamp with a meta whose STUDYID label is removed: the attr must clear,
  # else .col_meta_from_attrs would resurrect the lying label on a later write.
  cols <- meta@columns
  cols$STUDYID$label <- NULL
  meta2 <- vport:::vport_meta_class(dataset = meta@dataset, columns = cols)
  x2 <- set_meta(x, meta2)
  expect_null(attr(x2$STUDYID, "label", exact = TRUE))
})

test_that("set_meta projection is idempotent", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  once <- set_meta(cdisc_adsl, meta)
  twice <- set_meta(once, meta)
  expect_identical(once, twice)
})

test_that("get_meta aborts when the frame carries no metadata", {
  expect_error(get_meta(cdisc_adsl), class = "vport_error_input")
})

test_that("set_meta validates its arguments", {
  spec <- demo_spec()
  meta <- vport:::.meta_from_spec(spec, "ADSL")
  expect_error(set_meta(list(1), meta), class = "vport_error_input")
  expect_error(set_meta(cdisc_adsl, "notmeta"), class = "vport_error_input")
})

test_that("is_vport_meta is FALSE for non-meta objects", {
  expect_false(is_vport_meta(cdisc_adsl))
  expect_false(is_vport_meta(list()))
})

# ---- informats ride _vport.informats, never the CDISC columns array --------

test_that("informat is stripped from emitted columns and rides _vport", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "BRTHDT",
      label = "Birth Date",
      data_type = "date",
      display_format = "DATE9.",
      informat = "YYMMDD10.",
      stringsAsFactors = FALSE
    )
  )
  meta <- vport:::.meta_from_spec(spec, "DM")
  expect_identical(meta@columns$BRTHDT$informat, "YYMMDD10.")

  payload <- vport:::.meta_payload(meta, extensions = TRUE)
  emitted <- payload$columns[[1]]
  expect_false("informat" %in% names(emitted))
  expect_identical(payload[["_vport"]]$informats$BRTHDT, "YYMMDD10.")
  expect_identical(payload[["_vport"]]$vportMetaVersion, "1.0")

  # The strict payload drops the block entirely.
  strict <- vport:::.meta_payload(meta, extensions = FALSE)
  expect_false("_vport" %in% names(strict))

  # Round-trip identity through the serializer, informat back in canonical
  # position.
  back <- vport:::.meta_from_datasetjson(
    vport:::.meta_to_datasetjson(meta, extensions = TRUE)
  )
  expect_identical(back@columns, meta@columns)
})

test_that("set_meta projects informat.sas like format.sas", {
  spec <- vport_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "BRTHDT",
      label = "Birth Date",
      data_type = "date",
      display_format = "DATE9.",
      informat = "YYMMDD10.",
      stringsAsFactors = FALSE
    )
  )
  meta <- vport:::.meta_from_spec(spec, "DM")
  df <- data.frame(BRTHDT = as.Date("1980-04-12"))
  stamped <- set_meta(df, meta)
  expect_identical(attr(stamped$BRTHDT, "informat.sas"), "YYMMDD10.")
  # And a bare frame carrying the attribute feeds it back into the meta.
  bare <- data.frame(BRTHDT = as.Date("1980-04-12"))
  attr(bare$BRTHDT, "informat.sas") <- "YYMMDD10."
  expect_identical(
    vport:::.meta_from_frame(bare)@columns$BRTHDT$informat,
    "YYMMDD10."
  )
})
