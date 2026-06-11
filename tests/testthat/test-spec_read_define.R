# read_spec() on a native Define-XML v2.x document. Grounded against the
# official CDISC Define-XML 2.1.0 SDTM example (fixtures/define21-sdtm.xml,
# SHA-pinned in data-raw/download-fixtures.R).

skip_if_not_installed("xml2")

.define_fixture <- function() {
  p <- test_path("fixtures", "define21-sdtm.xml")
  skip_if_not(file.exists(p), "Define-XML fixture not present")
  p
}

test_that("read_spec parses the CDISC 2.1 example into a vport_spec", {
  spec <- read_spec(.define_fixture())
  expect_true(is_vport_spec(spec))
  ds <- spec@datasets
  expect_true(all(c("TS", "DM", "LB") %in% ds$dataset))
  expect_identical(ds$label[ds$dataset == "TS"], "Trial Summary")
  expect_identical(ds$class[ds$dataset == "TS"], "TRIAL DESIGN")
})

test_that("variables carry the Define attributes", {
  spec <- read_spec(.define_fixture())
  v <- spec_variables(spec, "DM")
  age <- v[v$variable == "AGE", ]
  expect_identical(age$label, "Age")
  expect_identical(age$data_type, "integer")
  expect_identical(age$length, 2L)
  expect_identical(age$origin, "Derived")
  expect_identical(age$itemoid, "IT.DM.AGE")
  sex <- v[v$variable == "SEX", ]
  expect_identical(sex$codelist_id, "CL.SEX")
  expect_identical(sex$origin, "Collected")
  ageu <- v[v$variable == "AGEU", ]
  expect_identical(ageu$comment_id, "COM.AGEU")
  expect_true(all(!is.na(v$order)))
  # KeySequence from the ItemRefs becomes both key_sequence and dataset keys.
  expect_identical(v$key_sequence[v$variable == "STUDYID"], 1L)
  expect_identical(spec_keys(spec, "DM")[1:2], c("STUDYID", "USUBJID"))
})

test_that("codelists carry terms, decodes, order, and extensibility", {
  spec <- read_spec(.define_fixture())
  cl <- spec@codelists
  armcd <- cl[cl$codelist_id == "CL.ARMCD", ]
  expect_identical(
    armcd$decode[armcd$term == "WONDER10"],
    "Miracle Drug 10 mg"
  )
  expect_identical(armcd$order[armcd$term == "WONDER10"], 1L)
  # def:ExtendedValue = "Yes" marks a sponsor term.
  lbresu <- cl[cl$codelist_id == "CL.LBRESU", ]
  expect_true(lbresu$extended[lbresu$term == "X10^9/L"])
  expect_false(any(lbresu$extended[lbresu$term == "%"]))
  # An enumerated codelist has terms with no decode.
  ageu <- cl[cl$codelist_id == "CL.AGEU", ]
  expect_true("YEARS" %in% ageu$term)
  expect_true(is.na(ageu$decode[ageu$term == "YEARS"]))
})

test_that("an external-dictionary codelist is dropped from variable refs", {
  spec <- read_spec(.define_fixture())
  # CL.ISO.COUNTRY is an ExternalCodeList (ISO-3166): not an enumerable
  # membership list, so it appears nowhere in the spec's codelists and no
  # variable references it.
  expect_false("CL.ISO.COUNTRY" %in% spec@codelists$codelist_id)
  expect_false(any(
    spec@variables$codelist_id %in% "CL.ISO.COUNTRY",
    na.rm = TRUE
  ))
})

test_that("methods, comments, and documents are carried", {
  spec <- read_spec(.define_fixture())
  m <- spec@methods
  age <- m[m$method_id == "MT.AGE", ]
  expect_identical(age$type, "Computation")
  expect_match(age$description, "Age at Screening")
  expect_identical(age$document_id, "LF.ComplexAlgorithms")

  cm <- spec@comments
  expect_identical(
    cm$description[cm$comment_id == "COM.AGEU"],
    "Defaulted to YEARS"
  )

  d <- spec@documents
  expect_identical(d$href[d$document_id == "LF.TS"], "ts.xpt")
  expect_identical(d$title[d$document_id == "LF.TS"], "ts.xpt")
})

test_that("value-level metadata lands in @values with where clauses", {
  spec <- read_spec(.define_fixture())
  vl <- spec@values
  expect_s3_class(vl, "data.frame")
  lb <- vl[vl$dataset == "LB" & vl$variable == "LBORRES", ]
  expect_true(nrow(lb) >= 3L)
  expect_match(lb$where_clause[1], "LBTESTCD")
  expect_true(all(nzchar(lb$where_clause)))
})

test_that("the study block carries name and standard", {
  spec <- read_spec(.define_fixture())
  st <- spec@study
  expect_identical(st$study_name, "CDISC01_1")
  expect_match(st$standard, "SDTMIG")
})

test_that("the parsed spec validates", {
  spec <- read_spec(.define_fixture())
  chk <- validate_spec(spec)
  # Findings are fine (the example exercises edge features); a hard failure
  # in validation is not.
  expect_s3_class(chk@findings, "data.frame")
})

test_that("a Define-XML v1.0 document aborts with guidance", {
  p <- withr::local_tempfile(fileext = ".xml")
  writeLines(
    c(
      "<?xml version=\"1.0\"?>",
      "<ODM xmlns=\"http://www.cdisc.org/ns/odm/v1.2\"",
      "  xmlns:def=\"http://www.cdisc.org/ns/def/v1.0\">",
      "<Study OID=\"X\"><MetaDataVersion OID=\"M\"/></Study></ODM>"
    ),
    p
  )
  expect_error(read_spec(p), class = "vport_error_input")
})

test_that("a non-Define XML document aborts cleanly", {
  p <- withr::local_tempfile(fileext = ".xml")
  writeLines("<root><child/></root>", p)
  expect_error(read_spec(p), class = "vport_error_input")
  p2 <- withr::local_tempfile(fileext = ".xml")
  writeLines("not xml at all <<<", p2)
  expect_error(read_spec(p2), class = "vport_error_input")
})

# ---- a minimal Define-XML 2.0 document (edge coverage) ----------------------

.mini_define <- function(body) {
  paste0(
    "<?xml version=\"1.0\"?>\n",
    "<ODM xmlns=\"http://www.cdisc.org/ns/odm/v1.3\"\n",
    "  xmlns:def=\"http://www.cdisc.org/ns/def/v2.0\"\n",
    "  xmlns:xlink=\"http://www.w3.org/1999/xlink\">\n",
    "<Study OID=\"S1\"><GlobalVariables>",
    "<StudyName>MINI</StudyName>",
    "<StudyDescription>x</StudyDescription>",
    "<ProtocolName>MINI-01</ProtocolName>",
    "</GlobalVariables>\n",
    "<MetaDataVersion OID=\"M1\" Name=\"mini\"",
    " def:DefineVersion=\"2.0.0\"",
    " def:StandardName=\"SDTMIG\" def:StandardVersion=\"3.2\">\n",
    body,
    "</MetaDataVersion></Study></ODM>\n"
  )
}

test_that("a Define 2.0 document with no codelists or supporting slots reads", {
  body <- paste0(
    "<ItemGroupDef OID=\"IG.DM\" Name=\"DM\" Purpose=\"Tabulation\"",
    " def:Structure=\"One record per subject\">",
    "<Description><TranslatedText>Demographics</TranslatedText></Description>",
    "<ItemRef ItemOID=\"IT.DM.USUBJID\" Mandatory=\"Yes\" OrderNumber=\"1\"/>",
    "</ItemGroupDef>",
    "<ItemDef OID=\"IT.DM.USUBJID\" Name=\"USUBJID\" DataType=\"text\"",
    " Length=\"12\" def:DisplayFormat=\"$12.\">",
    "<Description><TranslatedText>Subject</TranslatedText></Description>",
    "</ItemDef>"
  )
  p <- withr::local_tempfile(fileext = ".xml")
  writeLines(.mini_define(body), p)
  spec <- read_spec(p)
  # The 2.0 standard rides the MetaDataVersion attributes.
  expect_identical(spec@study$standard, "SDTMIG 3.2")
  # def:DisplayFormat (a namespaced attribute) is recovered.
  v <- spec_variables(spec, "DM")
  expect_identical(v$display_format, "$12.")
  expect_identical(nrow(spec@codelists), 0L)
  expect_identical(nrow(spec@methods), 0L)
  expect_null(spec@values)
})

test_that("an ItemRef without its ItemDef aborts as inconsistent", {
  body <- paste0(
    "<ItemGroupDef OID=\"IG.DM\" Name=\"DM\">",
    "<ItemRef ItemOID=\"IT.GONE\" Mandatory=\"Yes\" OrderNumber=\"1\"/>",
    "</ItemGroupDef>"
  )
  p <- withr::local_tempfile(fileext = ".xml")
  writeLines(.mini_define(body), p)
  expect_error(read_spec(p), class = "vport_error_input")
})

test_that("a MetaDataVersion without ItemGroupDefs aborts", {
  p <- withr::local_tempfile(fileext = ".xml")
  writeLines(.mini_define(""), p)
  expect_error(read_spec(p), class = "vport_error_input")
})
