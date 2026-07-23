# Tests for the artoo_meta spine: build meta from a spec, the single
# Dataset-JSON serializer + its inverse (round-trip identity), and the
# get_meta()/set_meta()/is_artoo_meta() frame bridge.

demo_spec <- function() {
  artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
}

# ---- .meta_from_spec --------------------------------------------------------

test_that(".meta_from_spec builds a artoo_meta for one dataset", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")

  expect_true(is_artoo_meta(meta))
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
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  studyid <- meta@columns$STUDYID

  expect_identical(studyid$name, "STUDYID")
  expect_identical(studyid$label, "Study Identifier")
  expect_identical(studyid$dataType, "string")
  expect_identical(studyid$length, 12L)
  expect_identical(studyid$itemOID, "IT.ADSL.STUDYID")
})

test_that(".meta_from_spec omits absent (NA) attributes", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  # STUDYID has no codelist / displayFormat in the demo spec; those keys
  # are dropped, not stored as NA (Dataset-JSON omits absent attributes).
  expect_false("codelist" %in% names(meta@columns$STUDYID))
  expect_false("displayFormat" %in% names(meta@columns$STUDYID))
  expect_false("targetDataType" %in% names(meta@columns$STUDYID))
})

test_that(".meta_from_spec rejects an unknown dataset", {
  spec <- demo_spec()
  expect_error(
    artoo:::.meta_from_spec(spec, "NOPE"),
    class = "artoo_error_input"
  )
})

# ---- serializer round-trip --------------------------------------------------

test_that(".meta_to_datasetjson produces parseable Dataset-JSON metadata", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  json <- artoo:::.meta_to_datasetjson(meta)

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
  # extensions = TRUE is how every production caller serializes (set_meta,
  # the parquet sidecar, the json/ndjson codecs under the default
  # strict = FALSE); the extension-less payload is the deliberately-lossy
  # strict mode, covered by its own tests.
  spec <- demo_spec()
  for (ds in spec_datasets(spec)) {
    meta <- artoo:::.meta_from_spec(spec, ds)
    back <- artoo:::.meta_from_datasetjson(
      artoo:::.meta_to_datasetjson(meta, extensions = TRUE)
    )
    expect_identical(back@columns, meta@columns, info = ds)
    expect_identical(back@dataset, meta@dataset, info = ds)
  }
})

test_that("integer column attributes survive the round-trip as integers", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  back <- artoo:::.meta_from_datasetjson(
    artoo:::.meta_to_datasetjson(meta, extensions = TRUE)
  )
  expect_type(back@columns$STUDYID$length, "integer")
})

# ---- C2: source-encoding extension (_artoo namespace) ----------------------

test_that("source encoding rides the _artoo extension, never a CDISC key", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  meta <- S7::set_props(
    meta,
    dataset = c(meta@dataset, list(encoding = "WINDOWS-1252"))
  )

  # extensions = TRUE: encoding emitted ONLY under _artoo, not top-level.
  ext <- jsonlite::fromJSON(
    artoo:::.meta_to_datasetjson(meta, extensions = TRUE),
    simplifyVector = FALSE
  )
  expect_identical(ext[["_artoo"]]$sourceEncoding, "WINDOWS-1252")
  expect_false("encoding" %in% names(ext))

  # extensions = FALSE (the default, Dataset-JSON FILE path): no _artoo,
  # and no stray encoding key — strict CDISC.
  strict <- jsonlite::fromJSON(
    artoo:::.meta_to_datasetjson(meta, extensions = FALSE),
    simplifyVector = FALSE
  )
  expect_false("_artoo" %in% names(strict))
  expect_false("encoding" %in% names(strict))
})

test_that("the _artoo sourceEncoding round-trips back into @dataset$encoding", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  meta <- S7::set_props(
    meta,
    dataset = c(meta@dataset, list(encoding = "WINDOWS-1252"))
  )
  json <- artoo:::.meta_to_datasetjson(meta, extensions = TRUE)
  back <- artoo:::.meta_from_datasetjson(json)
  expect_identical(back@dataset$encoding, "WINDOWS-1252")
})

test_that("a meta without encoding is byte-identical across the round-trip", {
  # No regression: extensions default FALSE and encoding drops as NULL.
  spec <- artoo_spec(
    cdisc_sdtm_datasets,
    cdisc_sdtm_variables,
    codelists = cdisc_codelists
  )
  meta <- artoo:::.meta_from_spec(spec, "DM")
  back <- artoo:::.meta_from_datasetjson(artoo:::.meta_to_datasetjson(meta))
  expect_identical(back@dataset, meta@dataset)
  expect_false("encoding" %in% names(back@dataset))
})

# ---- get_meta / set_meta bridge --------------------------------------------

test_that("set_meta then get_meta round-trips through a frame attribute", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  x <- set_meta(cdisc_adsl, meta)

  expect_s3_class(x, "data.frame")
  expect_true(is.character(attr(x, "metadata_json")))
  got <- get_meta(x)
  expect_true(is_artoo_meta(got))
  expect_identical(got@columns, meta@columns)
})

test_that("get_meta aborts on a frame carrying no metadata", {
  expect_error(get_meta(cdisc_adsl), class = "artoo_error_input")
  expect_snapshot(get_meta(cdisc_adsl), error = TRUE)
})

# ---- Wave 3: set_meta projects label / format.sas onto columns -------------

test_that("set_meta projects the column label and SAS format onto the frame", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  x <- set_meta(cdisc_adsl, meta)
  # STUDYID carries a label in the spec; the projected attr matches the meta.
  expect_identical(
    attr(x$STUDYID, "label", exact = TRUE),
    meta@columns$STUDYID$label
  )
})

test_that("set_meta strips a stale label when the new meta has none", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  x <- set_meta(cdisc_adsl, meta)
  expect_false(is.null(attr(x$STUDYID, "label", exact = TRUE)))
  # Re-stamp with a meta whose STUDYID label is removed: the attr must clear,
  # else .col_meta_from_attrs would resurrect the lying label on a later write.
  cols <- meta@columns
  cols$STUDYID$label <- NULL
  meta2 <- artoo:::artoo_meta_class(dataset = meta@dataset, columns = cols)
  x2 <- set_meta(x, meta2)
  expect_null(attr(x2$STUDYID, "label", exact = TRUE))
})

test_that("set_meta projection is idempotent", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  once <- set_meta(cdisc_adsl, meta)
  twice <- set_meta(once, meta)
  expect_identical(once, twice)
})

test_that("get_meta aborts when the frame carries no metadata", {
  expect_error(get_meta(cdisc_adsl), class = "artoo_error_input")
})

test_that("set_meta validates its arguments", {
  spec <- demo_spec()
  meta <- artoo:::.meta_from_spec(spec, "ADSL")
  expect_error(set_meta(list(1), meta), class = "artoo_error_input")
  expect_error(set_meta(cdisc_adsl, "notmeta"), class = "artoo_error_input")
})

test_that("is_artoo_meta is FALSE for non-meta objects", {
  expect_false(is_artoo_meta(cdisc_adsl))
  expect_false(is_artoo_meta(list()))
})

# ---- informats ride _artoo.informats, never the CDISC columns array --------

test_that("informat is stripped from emitted columns and rides _artoo", {
  spec <- artoo_spec(
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
  meta <- artoo:::.meta_from_spec(spec, "DM")
  expect_identical(meta@columns$BRTHDT$informat, "YYMMDD10.")

  payload <- artoo:::.meta_payload(meta, extensions = TRUE)
  emitted <- payload$columns[[1]]
  expect_false("informat" %in% names(emitted))
  expect_identical(payload[["_artoo"]]$informats$BRTHDT, "YYMMDD10.")
  expect_identical(payload[["_artoo"]]$artooMetaVersion, "1.0")

  # The strict payload drops the block entirely.
  strict <- artoo:::.meta_payload(meta, extensions = FALSE)
  expect_false("_artoo" %in% names(strict))

  # Round-trip identity through the serializer, informat back in canonical
  # position.
  back <- artoo:::.meta_from_datasetjson(
    artoo:::.meta_to_datasetjson(meta, extensions = TRUE)
  )
  expect_identical(back@columns, meta@columns)
})

test_that("origin, codelist, significantDigits are stripped from emitted columns and ride _artoo", {
  # Dataset-JSON v1.1's Column vocabulary is closed (additionalProperties:
  # false); these three must never appear inside the emitted `columns` array.
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "AGE",
      label = "Age",
      data_type = "decimal",
      origin = "Collected",
      codelist_id = "CL.AGEU",
      significant_digits = 2L,
      stringsAsFactors = FALSE
    ),
    codelists = data.frame(
      codelist_id = "CL.AGEU",
      term = "YEARS",
      stringsAsFactors = FALSE
    )
  )
  meta <- artoo:::.meta_from_spec(spec, "DM")
  expect_identical(meta@columns$AGE$origin, "Collected")
  expect_identical(meta@columns$AGE$codelist, "CL.AGEU")
  expect_identical(meta@columns$AGE$significantDigits, 2L)

  payload <- artoo:::.meta_payload(meta, extensions = TRUE)
  emitted <- payload$columns[[1]]
  expect_false(any(
    c("origin", "codelist", "significantDigits") %in% names(emitted)
  ))
  expect_identical(payload[["_artoo"]]$origins$AGE, "Collected")
  expect_identical(payload[["_artoo"]]$codelists$AGE, "CL.AGEU")
  expect_identical(payload[["_artoo"]]$significantDigits$AGE, 2L)

  # The strict payload drops the block entirely, columns stay schema-shaped.
  strict <- artoo:::.meta_payload(meta, extensions = FALSE)
  expect_false("_artoo" %in% names(strict))
  expect_false(any(
    c("origin", "codelist", "significantDigits") %in%
      names(strict$columns[[1]])
  ))

  # Round-trip identity through the serializer, all three back in canonical
  # position.
  back <- artoo:::.meta_from_datasetjson(
    artoo:::.meta_to_datasetjson(meta, extensions = TRUE)
  )
  expect_identical(back@columns, meta@columns)
})

test_that("every emitted column and the dataset carry a label key, empty when absent", {
  # `label` is required per Column and per Dataset in the v1.1 schema; an
  # unlabelled variable must serialise as label "", never an omitted key.
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = NA_character_),
    data.frame(
      dataset = "DM",
      variable = "DTHFL",
      label = NA_character_,
      data_type = "string",
      stringsAsFactors = FALSE
    )
  )
  meta <- artoo:::.meta_from_spec(spec, "DM")
  expect_false("label" %in% names(meta@columns$DTHFL))

  payload <- artoo:::.meta_payload(meta)
  expect_identical(payload$columns[[1]]$label, "")
  expect_identical(payload$label, "")
  # Canonical field order is preserved (label sits after name).
  expect_identical(
    names(payload$columns[[1]]),
    c("itemOID", "name", "label", "dataType")
  )

  # An empty label parses back to absent, so the round-trip stays an
  # identity.
  back <- artoo:::.meta_from_datasetjson(
    artoo:::.meta_to_datasetjson(meta, extensions = TRUE)
  )
  expect_identical(back@columns, meta@columns)
  expect_identical(back@dataset, meta@dataset)
})

test_that("write_json output uses only schema-legal Column keys with label always present", {
  # End-to-end pin of the two schema defects: apply a bundled spec (which
  # supplies origins, codelists, and unlabelled variables), write the file,
  # and inspect the raw JSON.
  dm <- suppressMessages(apply_spec(cdisc_dm, sdtm_spec, dataset = "DM"))
  path <- withr::local_tempfile(fileext = ".json")
  suppressWarnings(write_json(dm, path))
  j <- jsonlite::fromJSON(path, simplifyVector = FALSE)

  legal <- c(
    "itemOID",
    "name",
    "label",
    "dataType",
    "targetDataType",
    "length",
    "displayFormat",
    "keySequence"
  )
  keys <- unique(unlist(lapply(j$columns, names)))
  expect_in(keys, legal)
  expect_true(all(vapply(
    j$columns,
    function(c) is.character(c$label),
    logical(1)
  )))
  expect_true(is.character(j$label))

  # And the file still reads back losslessly.
  back <- read_json(path)
  expect_identical(get_meta(back)@columns, get_meta(dm)@columns)
})

test_that("set_meta projects informat.sas like format.sas", {
  spec <- artoo_spec(
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
  meta <- artoo:::.meta_from_spec(spec, "DM")
  df <- data.frame(BRTHDT = as.Date("1980-04-12"))
  stamped <- set_meta(df, meta)
  expect_identical(attr(stamped$BRTHDT, "informat.sas"), "YYMMDD10.")
  # And a bare frame carrying the attribute feeds it back into the meta.
  bare <- data.frame(BRTHDT = as.Date("1980-04-12"))
  attr(bare$BRTHDT, "informat.sas") <- "YYMMDD10."
  expect_identical(
    artoo:::.meta_from_frame(bare)@columns$BRTHDT$informat,
    "YYMMDD10."
  )
})

# ---- sync_meta(): metadata after attribute-dropping transforms --------------

test_that("sync_meta narrows, reorders, and refreshes records", {
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  meta <- get_meta(adsl)

  # A base-R pipeline that drops the frame attributes entirely.
  worked <- as.data.frame(adsl)
  attr(worked, "metadata_json") <- NULL
  worked <- worked[worked$SAFFL == "Y", c("AGE", "USUBJID", "STUDYID")]

  out <- sync_meta(worked, meta)
  m2 <- get_meta(out)
  expect_identical(names(m2@columns), c("AGE", "USUBJID", "STUDYID"))
  expect_identical(m2@dataset$records, nrow(worked))
  expect_identical(m2@columns$AGE, meta@columns$AGE)
})

test_that("sync_meta synthesizes entries for new columns with a message", {
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  adsl$AGEGR9 <- ifelse(adsl$AGE > 65, ">65", "<=65")
  expect_message(out <- sync_meta(adsl), "AGEGR9")
  m2 <- get_meta(out)
  expect_identical(m2@columns$AGEGR9$dataType, "string")
  expect_identical(m2@columns$AGEGR9$name, "AGEGR9")
})

test_that("sync_meta with no meta and no attribute aborts with guidance", {
  bare <- data.frame(A = 1)
  expect_error(sync_meta(bare), class = "artoo_error_input")
})

test_that("sync_meta defaults to the frame's own metadata", {
  spec <- artoo_spec(
    cdisc_adam_datasets,
    cdisc_adam_variables,
    codelists = cdisc_codelists
  )
  adsl <- apply_spec(cdisc_adsl, spec, "ADSL", conformance = "off")
  sub <- adsl
  sub$AGE <- NULL
  # The metadata_json attribute survives $<- so sync_meta(x) self-serves.
  out <- sync_meta(sub)
  expect_false("AGE" %in% names(get_meta(out)@columns))
})

test_that("sync_meta validates its inputs", {
  expect_error(sync_meta("not a frame"), class = "artoo_error_input")
  expect_error(
    sync_meta(data.frame(A = 1), meta = "nope"),
    class = "artoo_error_input"
  )
})

test_that(".meta_from_spec respects a spec-supplied itemOID and studyid", {
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "USUBJID",
      itemoid = "IT.CUSTOM.OID",
      label = "Subject",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    study = data.frame(studyid = "ARTOO-001", stringsAsFactors = FALSE)
  )
  meta <- artoo:::.meta_from_spec(spec, "DM")
  expect_identical(meta@columns$USUBJID$itemOID, "IT.CUSTOM.OID")
  expect_identical(meta@dataset$studyOID, "ARTOO-001")
})

test_that(".meta_from_spec stamps studyOID from a Define-sourced study frame", {
  # Regression: the Define-XML reader emits study_name; the studyOID must
  # come from the canonical field, not the legacy studyid spelling.
  spec <- artoo_spec(
    data.frame(dataset = "DM", label = "Demographics"),
    data.frame(
      dataset = "DM",
      variable = "USUBJID",
      label = "Subject",
      data_type = "string",
      stringsAsFactors = FALSE
    ),
    study = data.frame(study_name = "CDISC-Sample", stringsAsFactors = FALSE)
  )
  meta <- artoo:::.meta_from_spec(spec, "DM")
  expect_identical(meta@dataset$studyOID, "CDISC-Sample")
})
