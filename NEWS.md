# artoo 0.2.0.9000

* `members()` reads a gzipped dataset. `members("dm.ndjson.gz")` aborted with
  `No codec handles the "gz" extension` on a file `write_ndjson()` produces
  and `read_dataset()` reads. Gzip is peeled for the codecs that support it,
  so `dm.json.gz` inventories as `dm` and `dm.parquet.gz` stays unhandled,
  which is what `read_dataset()` does with it too.

* `write_spec()` to Define-XML accepts a folder for `data =`, not only a
  named list of frames. Each dataset the spec names is matched to a file
  whose basename is that name, ignoring case, so a submission folder of
  `dm.xpt` and `ae.xpt` no longer has to be retyped as
  `list(DM = dm, AE = ae)`. The folder is inventoried, not descended. A
  dataset with no file is reported, not an error; a file the spec does not
  name is left alone; a dataset matching two files aborts rather than
  choosing, because two formats can disagree about byte width and picking
  one silently would change the document.

* `write_spec()` to Define-XML gains `data_format =`, restricting a folder
  to the named formats. It takes format names as `artoo_formats()` lists
  them. Adding it means `write_spec()` no longer accepts `dat =` as an
  abbreviation of `data =`, which R had been resolving by partial matching.

* `members()` gains `format =`, restricting the inventory to the named
  formats. It takes format names as `artoo_formats()` lists them, not file
  extensions, so `"parquet"` claims both `.parquet` and `.pq`; several names
  are a set rather than a precedence order. The default `NULL` inventories
  every format, which is what `members()` did before. The reason to pass it
  is a directory holding one dataset in two formats, where the full
  inventory reports both.

# artoo 0.2.0

* `read_spec()` refuses an `Analysis Criteria` sheet missing `Display`,
  `Result` or `Dataset`, naming the column. It used to tolerate the absence
  silently: the join key matched nothing, the whole sheet was discarded
  without a word, and the failure surfaced later at write time naming the
  analysis results rather than the sheet that caused it. `Variables` and
  `Where Clause` stay optional, which is the split the format itself
  declares.

* `read_spec()` links each dataset to the standard its `Standard` cell
  names, minting a `standards` row where none defines it — so a
  workbook-sourced define carries `def:StandardOID` on every `ItemGroupDef`
  and the rendered dataset headings show the standard, as CDISC's own
  examples do. A `Standard` column naming several standards no longer
  aborts: each row keeps its own and `@standard` holds only the primary.
  `write_spec()` to `.xlsx` accordingly writes each dataset's own standard
  rather than stamping the primary over every row.

* `read_spec()` reads an `Analysis Criteria` sheet that omits its optional
  columns — one naming only datasets used to die mid-read — and warns when
  that sheet overrides a result's non-blank `Selection Criteria` cell
  instead of discarding the cell silently.

* `read_spec()` keeps a sheet's own `Description` column when `Label`
  supplied the label: it is unconsumed sponsor text, not a second spelling
  of one. `write_spec()` to `.xlsx` likewise no longer overwrites a
  foreign `Description` on the ValueLevel sheet with the label.

* `write_spec()` to Define-XML derives a dataset's archive location
  (`LF.<DATASET>` pointing at `<dataset>.xpt`) when the spec states none,
  reusing a document already carrying that id rather than minting a second
  leaf beside it — two leaves with one `xs:ID` failed schema validation on
  artoo's own workbook round trip. A dataset flagged as having no data
  derives none, the carve-out CDISC's own examples make.

* `write_spec()` to Define-XML writes the partly-decoded and duplicated
  codelist shapes real sponsor specifications carry, instead of refusing
  them at the schema gate as an artoo defect: a term without a decode in a
  decoded list gets an empty `Decode` (never the string `"NA"`), a coded
  value listed twice identically collapses to its first row with a warning,
  one defined two ways is refused naming the codelist and values, and a
  codelist seating two terms at one `OrderNumber` is written in source
  order without the attribute. Identical repeated method and comment rows
  collapse the same way; contradictory ones are refused by id.
  of tooling imports. The study sheet is named `Study`, a value-level row
  names its condition by ID and a `WhereClauses` sheet defines it, an
  analysis result's datasets sit on an `Analysis Criteria` sheet, and a
  label is carried under both `Label` and `Description`. Measured against
  the importer that the open-source edition of the reference tooling ships:
  it makes the study sheet its initialising sheet and therefore required, so
  a workbook naming it `Define` was refused before a row was read, and it
  treats the value-level cell as a foreign key, so a condition written there
  as an expression cost every value-level row.

* `read_spec()` reads a value-level label from a `Description` column, which
  is how the older workbook generation spells it. Reading one used to give
  every value-level row no label, and artoo's own submission-grade notice
  then reported the absence, on a workbook that had them.

* `read_spec()` and `write_spec()` round-trip a workbook artoo wrote. A
  workbook-sourced spec carries its value-level link in a different column
  from a define-sourced one, and the writer only understood the second, so
  its own output could not be read back. No test covered it; one does now.

* `read_spec()` on a define.xml keeps a variable's reference to an external
  dictionary. The referential scrub predates dictionaries being modelled and
  stripped every such binding, so an adverse-events define came back with
  `AEDECOD` naming no terminology at all while the dictionary it named was
  written out beside it.

* `check_spec()` no longer aborts on a variable whose terminology is an
  external dictionary. A dictionary enumerates nothing, so there is no
  membership to check; checking anyway stopped the conformance run on every
  adverse-events dataset.

* `write_spec()` writes an external dictionary as the `ExternalCodeList` it
  is, and `read_spec()` on a define.xml reads one back. A variable naming
  MedDRA or WHODrug used to write a `CodeListRef` pointing at nothing --
  schema-valid, and rejected by artoo's own reference check -- while a
  document carrying one lost it and every reference to it on the way in.

* `read_spec()` on a workbook reads the `Analysis Criteria` sheet, which is
  where the older workbook generation keeps an analysis result's datasets.
  artoo recognised the sheet name and never read the sheet, so a result
  authored that way reached the writer naming no analysis dataset and the
  write refused it.

* `write_spec()` to `.xlsx` no longer re-homes a where-clause check that
  names a variable in another dataset. Which dataset an unqualified name
  belongs to is decided by the row the condition sits on, and the writer was
  deciding it from the condition's first check instead -- so a VS value
  conditioned on `DM.COUNTRY` came back conditioned on `VS.COUNTRY`,
  selecting different records, with nothing said.

* `read_spec()` and `write_spec()` handle a where-clause value containing
  the word `and` or `or`. `"Nausea and vomiting"` is a real preferred term,
  and the condition splitter was blind to quotes, so reading artoo's own
  workbook turned one check into two whose values were `"Nausea` and
  `vomiting"`.

* `write_spec()` to `.xml` writes a page list separated by spaces. A page
  cell written `4, 5` shipped its comma into `PageRefs`, which is a
  space-separated list.

* `write_spec()` to `.xlsx` writes the study sheet in the format's own
  vocabulary. A spec read from a define.xml carries the document's
  identifiers, and none of them had a workbook spelling, so the sheet went
  out reading `define_version`, `study_oid` and `metadata_version_oid` --
  artoo's internal column names on a sheet a person reads and another tool
  imports. It also states `StandardName` and `StandardVersion`, which artoo
  read and never wrote back, so a workbook it produced could not say which
  standard it described.

* `read_spec()` on a workbook resolves the standard its Study sheet states.
  The sheet carries a name and a version as two attributes; artoo kept both
  as unmodelled study fields, so `spec_standard()` was `NA` and writing
  Define-XML 2.0 refused for want of the standard the sheet had named. A
  Study sheet that names one now also yields the `def:Standards` row
  Define-XML 2.1 asks for.

* `read_spec()` on a workbook works out which documents are the annotated
  CRF from their filenames, since the sheet has no column for it. A
  document whose name ends in `crf` is the annotated CRF, one with no
  filename belongs to no category, and an explicit `Role` still wins.

* `write_spec()` to `.xml` gives a method, comment, codelist, document or
  standard named on a workbook sheet an OID of its own kind, so a method
  called `EXTRT` is written as `MT.EXTRT`. Names taken straight from the
  sheet collided across kinds and the document failed its own schema. The
  spec keeps the names the author wrote.

* `read_spec()` on a workbook reads a method's formal expression. The
  `Methods` sheet carries one, in its expression context and code columns,
  and artoo read those into the spec and then used them nowhere: a method
  authored with a formal expression produced a define.xml with none. Writing
  a workbook puts the expression back in the same two columns.

* `read_spec()` and `write_spec()` now use the current Pinnacle 21 workbook
  shape for conditions. A value-level row states its condition as an
  expression in the `ValueLevel` sheet's `Where Clause` cell, and an analysis
  result states one bracket group per analysis dataset in `Selection
  Criteria`; the separate `WhereClauses` sheet, which that generation
  dropped, is still read but no longer written.

* `read_spec()` on a workbook no longer loses a value-level row's
  `Assigned Value`, `Source`, `Pages` or `Predecessor`. All four are
  columns of the sheet, and all four were mapped for `Variables` and not for
  `ValueLevel`, so a value-level `Origin = Predecessor` wrote an origin
  describing nothing.

* `read_spec()` on a workbook no longer keeps the quote characters that
  delimit a where-clause value. `AVISIT EQ "Week 24"` selected records whose
  AVISIT was the eight characters `"Week 24"` rather than the seven.

* `read_spec()` on a workbook reads a codelist's `Comment` as the comment
  reference it is, and a variable may name an external dictionary in its
  `Codelist` column, which is where a workbook puts it. Reading an adverse
  events spec aborted asking for terms a dictionary does not have.

* `read_spec()` and `write_spec()` keep an analysis variable's dataset
  qualifier straight, and a where-clause check that leaves its own dataset
  now says so.

* `define_lint()` is now `lint_define()`, matching the verb-first grammar of
  every other export. The function is new in this development version and has
  never been released, so nothing that ran before breaks.

* `read_spec()` with `datasets =` no longer keeps the codelists, methods,
  comments and documents belonging to the datasets it dropped. Scoping
  removes the referrers, so what was left over was an orphan artoo had just
  created: a spec narrowed to two ADaM datasets wrote a define.xml its own
  linter flagged 32 times. An orphan in an unscoped spec is left exactly
  where the author put it.

* `read_spec()` on a define.xml is about four times faster and no longer
  grows super-linearly. Every XPath matches by `local-name()`, but `xml2`
  rebuilt a namespace prefix table from the whole document on each one.

* `read_spec()` on a define.xml reads a value-level `ItemRef/@Role`, and
  reports the codelist aliases, `CodeList` descriptions and declared
  languages it has no column for, rather than dropping them in silence.

* `write_spec()` to `.xml` no longer aborts when `data =` covers only some
  of the datasets sharing an `ItemDef` OID; the widest measurement applies
  to the whole group.

* `write_spec()` to `.xml` no longer reports an ADaM spec as missing
  `datasets$domain`, which is an SDTM concept ADaM leaves blank.

* `write_spec()` to `.xml` says what a bare data frame is when `data =` gets
  one. A data frame is a named list, so it reached the per-element check and
  was refused for a column not being a data frame, naming the column.

* The bundled `sdtm-spec.xlsx` and `adam-spec.xlsx` are rebuilt. They were
  written before the where-clause fix below, so reading the package's own
  example workbook warned that 23 value-level rows named a clause it did not
  define.

* `write_spec()` on a Pinnacle 21 workbook now names the individual columns
  a workbook cannot carry, not just the one slot it has no sheet for. The
  sheets added for Define-XML closed the slot-level gaps and opened
  column-level ones: `Standards` has no column for which standard is primary,
  and none of the sheets has one for an ItemOID.

* `write_spec()` on a Pinnacle 21 workbook keys a ValueLevel row to the
  `WhereClauses` sheet by ID. It wrote the rendered expression there, which
  left every value-level row of an SDTM define naming a clause the same
  workbook did not define.

* `write_spec()` renders HTML through the stylesheet the document's
  processing instruction actually names, so `stylesheet = "acme.xsl"` and
  `html = TRUE` no longer render through the bundled sheet and disagree with
  the browser.

* `write_spec()` writes Define-XML when given a `.xml` path, so a Pinnacle 21
  workbook or a native JSON spec becomes a submission-grade define.xml in one
  call. The document is schema-validated before it reaches its destination, so
  an invalid one never overwrites a good file. Value-level metadata is emitted
  whole: the parent variable's `def:ValueListRef`, the `def:ValueListDef`, an
  `ItemDef` per value-level row, and the `def:WhereClauseRef` and
  `def:WhereClauseDef` behind it. External dictionaries are the one thing not
  written yet; a populated `dictionaries` table is reported rather than
  emitted. Needs the `xml2` package.

* `read_spec()` and `write_spec()` no longer lose a multi-value `IN` where
  clause through a Pinnacle 21 workbook. The workbook holds one row per range
  check and the spec holds one per value, and writing them row for row made
  `PARAMCD IN (A, B, C)` read back as three ANDed one-value checks, which
  select nothing.

* `read_spec()` on a Pinnacle 21 workbook reads an `Origin Document` column
  on the Variables sheet, so a page reference keeps what it points at.
  `read_spec()` on a Define-XML document now records which dataset defines a
  where clause's target, which a workbook has a column for and an OID does
  not.

* Reading a spec scoped to some datasets no longer leaves its where clauses
  and analysis results referencing the others.

* `write_spec()` now emits a variable's predecessor and assigned value.
  Define-XML has no attribute for either, so both go in the origin's
  description, which is where the CDISC stylesheet renders them; artoo read
  them and wrote an empty origin, so an ADaM define lost its traceability.

* `write_spec()` now emits CRF page references from a workbook. A page number
  with no document defaults to the annotated CRF when the spec names one, and
  is refused rather than dropped when it does not. `read_spec()` on a
  Pinnacle 21 workbook reads a `Role` column on the Documents sheet, so an
  author can designate which document is the annotated CRF.

* `write_spec()` refuses a value-level row with no where clause. Written out
  it was an `ItemRef` with no children: schema-valid, nothing dangling, and
  asserting that the definition applies to every row of its parent.

* `lint_define()` gains `define_unconditional_value` and
  `define_no_data_uncommented`. Both catch things the schema cannot see (a
  well-formed element, an optional attribute) and the reference checks cannot
  see (nothing to dangle).

* `write_spec()` on a `.xlsx` path now writes the `WhereClauses`,
  `Dictionaries`, `Standards` and analysis-results sheets. `read_spec()`
  learned them when the Define-XML work landed, so a workbook round trip was
  losing exactly what artoo had just taught itself to read.

* `write_spec()` gains `data`, which lets the datasets a define describes
  inform what it says. A blank `length` is filled from the real maximum byte
  width and a stated one shorter than the data is widened, because a length
  below the real maximum is a conformance finding; a length longer than the
  data is left alone, because it is a claim about the domain rather than about
  one extract. Value-level metadata is derived for the standard findings shapes
  (a result keyed by its test code, `TSVAL` by `TSPARMCD`, `QVAL` by `QNAM`,
  `AVAL` and `AVALC` by `PARAMCD`), each derived row carrying the type and width
  of the rows it covers, and a variable the spec already describes is never
  touched. A dataset with no records is flagged `def:HasNoData` when it carries
  a comment explaining the absence.

* `write_template()` writes a blank Pinnacle 21 workbook with the sheets and
  headers `read_spec()` recognises, so a specification can be authored from the
  shape the reader wants rather than guessed at. Every header comes from the
  reader's own maps, so the template cannot offer a column that would be
  silently ignored. A `version = "2.0"` template omits the four columns
  Define-XML 2.1 introduced.

* `write_spec()` gains `html`, which renders the define.xml through its own
  CDISC stylesheet into real HTML. Browsers are dropping XSLT support, so a
  document that renders only by being opened in one is on its way to being
  unreadable. Needs the `xslt` and `callr` packages; the transform runs in a
  separate process because libxslt and libxml2's schema validator corrupt each
  other's state in one session.

* `write_spec()` no longer overwrites a stylesheet already sitting beside the
  output, so a customised rendering survives a rewrite.

* `write_spec()` warns when the define.xml it wrote is valid but not
  submission-grade, naming every column nothing fills. None of them is required
  by the schema, and every one draws a conformance finding, so a spec that is
  incomplete partway through a study is still written rather than refused.

* `read_spec()` on a Pinnacle 21 workbook now forward-fills the merged cells on
  the analysis-results sheets, as it already did for every other sheet. A
  workbook merges the display cell across a display's results and the result id
  across a result's analysis datasets; without the fill those rows were dropped.

* A where clause may now qualify a variable in a different dataset, which is
  what a value-level condition on `DM.COUNTRY` means. A variable two datasets
  define is refused rather than resolved to one of them.

* `read_spec()` on a Define-XML 2.0 document now reads its standard as a
  `standards` row rather than one concatenated string. A version containing a
  space (`3.1.2 Amendment 1` is a real one) used to have half of it moved into
  the standard's name on the way back out, and a document naming no standard
  at all used to be written back asserting the standard was `NA`.

* `read_spec()` on a Define-XML document now reports every place it reads one
  of several: a second `def:DocumentRef`, `def:PDFPageRef`, or
  `TranslatedText`. All four bundled CDISC examples lose a `def:DocumentRef`
  this way, and the loss was invisible because the writer dropped it too.

* `read_spec()` and `write_spec()` now carry the document's build provenance
  (`Originator`, `SourceSystem`, `SourceSystemVersion`) and the
  MetaDataVersion's own comment.

* Analysis Results Metadata (ARM v1.0) is read and written, in both
  Define-XML versions. `read_spec()` fills `arm_displays` and `arm_results`
  from `arm:AnalysisResultDisplays`, and `write_spec()` emits them back. One
  analysis result over several analysis datasets keeps each dataset's own
  where clause and analysis variables, which is why `arm_results` is one row
  per result and dataset. Before this, reading an ADaM define and writing it
  back orphaned every leaf, where clause and comment that only its analysis
  results referenced.

* `read_spec()` on a Define-XML document now reads `def:PDFPageRef/@Title`,
  which names the table or listing a page holds. Every analysis-results page
  reference in the CDISC ADaM example carries one. It is 2.1-only, and is
  withheld when writing 2.0.

* `write_spec()` writes Define-XML 2.0 as well as 2.1, and converts between
  them. The version follows the spec's own `define_version` unless `version`
  says otherwise. The switch is exactly what the two standards renamed:
  `def:Standards` against `def:StandardName`/`def:StandardVersion`,
  `def:Class` as an element against an attribute, `def:Context` and
  `def:Origin/@Source` in 2.1 only, and the origin vocabulary (2.0's `CRF` and
  `eDT` are 2.1's `Collected`). A downgrade warns once, naming everything 2.0
  cannot carry; a 2.1 origin with no 2.0 spelling is refused rather than
  approximated.

* `read_spec()` on a Define-XML document now reads a PDF page RANGE. A
  `def:PDFPageRef` states its pages as either a `PageRefs` list or a
  `FirstPage`/`LastPage` range, and only the list was read, so every range was
  dropped silently. Both now land in `pages`, a range written as `"4-5"`.

* `write_spec()` gains `...`, which the Define-XML path reads for `version`,
  `created`, `stylesheet`, and `validate`. Freeze `created` for a
  byte-reproducible submission build.

* `read_spec()` on a Define-XML document now keeps the document's own
  identity: `Study/@OID`, `FileOID`, the MetaDataVersion's OID, name and
  description, and the ODM `@Context`. `write_spec()` writes them back, so a
  document read and written keeps every identifier an external reference may
  already name, rather than having fresh ones minted from the study name.

* `read_spec()` on a Define-XML document now reports what it drops. An
  external codelist (`MedDRA`, WHODrug, ISO 3166) and every reference to it
  are still dropped, and an `ItemDef` carrying more than one `def:Origin`
  still keeps only the first, but both now warn: a loss that reader and
  writer share is invisible to a round trip, and one nothing reports is worse
  than one that fails. A value-level item selected by more than one
  `def:WhereClauseRef` is now refused outright, because those are combined
  with OR and keeping the first silently narrows which rows the definition
  applies to.

* `read_spec()` on a Define-XML document now carries a value-level row's whole
  `ItemDef`: its origin, comment, display format, significant digits, and SAS
  field name, alongside the `def:WhereClauseRef` it names. Previously only the
  label, type, length and codelist survived, so a document read and written
  back lost every value-level origin.

* `read_spec()` on a Pinnacle 21 workbook now reads the `WhereClauses`,
  `Dictionaries`, `Standards`, and analysis-results sheets. A workbook with no
  `WhereClauses` sheet has its value-level conditions parsed from the free-text
  column instead, so both workbook generations are read.

* Where-clause values are now parsed correctly for every comparator. A value
  list is split only outside quotes, so a value containing a comma survives,
  and parentheses are stripped from scalar comparisons as well as list ones.
  An unknown comparator, or a disjunction that Define-XML cannot express, is
  refused with an explanation rather than silently reinterpreted.

* `artoo_spec()` gains six tables: `standards`, `where_clauses`,
  `method_expressions`, `arm_displays`, `arm_results`, and a reserved
  `dictionaries`. `read_spec()` on a Define-XML document now fills the first
  three, so the `def:Standards` block, the structured `RangeCheck`s behind every
  value-level condition, and each method's formal expressions survive a read
  instead of being discarded.

* A specification saved by an earlier version of artoo is upgraded
  automatically the first time any artoo function touches it, and says so once.
  Previously such an object passed every type check and then failed on the first
  new field. Save it again with `write_spec()` to make the upgrade permanent.

* The native spec JSON format is now version 2, carrying the six new tables.
  Reading a version 1 file still works.

* `read_spec()` on a Define-XML document now reads the metadata it previously
  discarded: `SASFieldName`, `def:Origin/@Source`, the Origin document and page
  reference, NCI controlled-terminology codes at both codelist and term level,
  codelist `Name`/`DataType`/`SASFormatName`, and the `ItemGroupDef` attributes
  a submission needs (`Domain`, `SASDatasetName`, `Purpose`, `Repeating`,
  `IsReferenceData`, `ArchiveLocationID`). Each document leaf now records which
  container owns it.

* `read_spec()` no longer loses `class` on Define-XML 2.0 documents. `def:Class`
  is a child element in 2.1 but an attribute in 2.0, and only the element was
  read, so every 2.0 document came back with an empty `class` column.

* `lint_define()` reports the reference-integrity defects XML Schema cannot
  express: an OID reference that resolves to nothing, and a definition nothing
  references. Findings are directional, and an orphaned `def:ValueListDef` is an
  error rather than a warning because every value-level definition it holds then
  renders nowhere. Codelists backed by an external dictionary, and those reached
  through `RoleCodeListOID`, are exempt from the orphan check.

* `validate_define()` schema-validates a Define-XML 2.0 or 2.1 document against
  the CDISC schemas, which artoo now bundles, so validation runs offline with no
  network round trip. The version is detected from the document's namespace
  unless you assert one. Note that schema validity is a floor: a reference that
  points at nothing, and a definition nothing points at, are both invisible to
  XML Schema.

* `write_json()` and `write_ndjson()` now emit columns that conform to the
  Dataset-JSON v1.1 schema's closed Column vocabulary: `origin`, `codelist`,
  and `significantDigits` moved out of the `columns` array into the
  namespaced `_artoo` extension block (joining `informats`), and `label` is
  always emitted, as `""` when a variable or dataset has none, instead of
  being omitted. `strict = TRUE` output now validates against the official
  CDISC schema, and third-party Dataset-JSON readers that require the
  per-column `label` key can read artoo's files. Reads map an empty label
  back to absent, so round-trips remain lossless.

# artoo 0.1.3

* `artoo_checks()` gained an `invalid_encoding` dimension (on by default):
  `check_spec()` flags character values whose bytes are not valid UTF-8, the
  signature of a source read under a mis-declared encoding, before a writer
  aborts on them.

* `artoo_encodings()` name resolution now accepts the SAS OEM/DOS encoding
  names (`pcoem437`, `pcoem850`, `pcoem852`, `pcoem858`, `pcoem862`,
  `pcoem866`, `msdos737`), and the reference table lists the `PCOEM437` /
  `PCOEM850` rows.

* `write_xpt()`, `write_json()`, `write_ndjson()`, and `write_parquet()`
  accept `on_invalid = "translit"`, folding smart punctuation (curly quotes,
  en/em dashes, ellipsis, bullet) to its exact ASCII form per the SAS NLS
  punctuation table; characters with no fold still abort loudly.

* `write_xpt()`, `write_json()`, `write_ndjson()`, and `write_parquet()`
  also accept `on_invalid = "fold"`: the punctuation fold plus the ICU
  Latin-ASCII accent strip (`Ö` to `O`, `ß` to `ss`, `Æ` to `AE`), pinned
  as data so the result is identical on every platform; characters neither
  table maps (the Euro sign) still abort.

* `write_xpt()` now warns (`artoo_warning_encoding`) when a value forces a
  column wider than its spec-declared length, instead of widening silently;
  data is still never truncated.

* `write_xpt()` and the other writers' `on_invalid = "replace"` now
  substitutes one `?` per unrepresentable character instead of one per byte
  (a curly quote previously became `???`).

* New article: *Migrating clinical data from WLATIN1 to UTF-8*, including
  the smart-punctuation fold table and the byte-length migration recipe.

# artoo 0.1.2

* Guarded the decimal full-precision JSON round-trip test on
  `capabilities("long.double")` so it skips on noLD builds, where bit-exact
  double-to-string round-trips are not guaranteed by the platform C library.

# artoo 0.1.1

Initial CRAN release. artoo is a lightweight, lossless, CDISC-native reader and
writer for clinical-trial datasets, built around one canonical metadata model
(`artoo_meta`) so that conversion between any two supported formats is lossless
by construction. Pure R and lightweight, with no external SAS or Java runtime.

## Formats

* Reads and writes SAS XPORT (v5 and v8), CDISC Dataset-JSON v1.1, NDJSON,
  Apache Parquet, and RDS. Every codec carries the full `artoo_meta` — labels,
  CDISC data types, lengths, SAS display formats, controlled-terminology
  references, and sort keys — so any-to-any conversion preserves the complete
  metadata. For Parquet the metadata rides as a `metadata_json` sidecar; a file
  written by another tool with no sidecar degrades gracefully to a bare frame
  rather than an error.

* Generic `read_dataset()` / `write_dataset()` dispatch on the file extension,
  with `read_xpt()` / `write_xpt()` and the matching `read_json()`,
  `read_ndjson()`, `read_parquet()`, and `read_rds()` pairs as direct entry
  points. Cross-cutting `encoding`, `checks`, and `created` arguments flow
  through `...`.

* Partial reads (`col_select`, `n_max`) on every reader; gzip-transparent JSON
  and NDJSON; multi-member SAS XPORT libraries via `xpt_members()` plus
  `read_xpt(member = )`.

* Numeric fidelity is exact end to end: a `decimal` value is exchanged as a
  string at IEEE round-trip precision, `integer` values beyond R's 32-bit range
  stay numeric rather than overflowing, and `NaN` / infinite values are
  rejected as invalid CDISC numerics. Rows are sorted in C-locale (byte) order,
  so a written file is deterministic across locales and matches SAS `PROC SORT`
  for ASCII keys.

* Encodings follow the IANA and SAS standards: the readers and writers accept a
  charset name in either the SAS or R spelling (see `artoo_encodings()`),
  character columns are transcoded to UTF-8 and NFC-normalized on read, and the
  `on_invalid = c("error", "replace", "ignore")` policy governs invalid bytes
  uniformly across every writer.

## Specifications

* `artoo_spec()` builds the canonical metadata model from a Pinnacle 21 Excel
  workbook, a Define-XML 2.0 / 2.1 file, or a native artoo JSON spec.
  `read_spec()` / `write_spec()` dispatch on the file extension: `.xlsx` writes
  a Pinnacle 21 workbook (Define-XML to P21 is one composition), and the native
  JSON form is the lossless interchange that round-trips a spec identically.

* The spec is single-standard by construction: `@standard` is resolved once
  from the explicit argument or the source, and study-level fields are
  canonicalized to the CDISC ODM vocabulary. Accessors include
  `spec_standard()`, `spec_variables()`, `spec_codelists()`, `spec_methods()`,
  and `spec_comments()`.

* `set_type()` returns a spec with one or more variables retyped through the
  CDISC vocabulary; `repair_spec()` retypes every variable a `check_spec()` run
  flags as fractional or out-of-range under an `integer` data type, so a frame
  the original spec would refuse coerces after one call.

## Conform and check

* `apply_spec(x, spec, dataset, conformance = , na_position = )` coerces each
  column to its CDISC data type, orders the columns and sorts the rows by the
  spec's keys, and stamps the `artoo_meta`. `extra = c("keep", "drop")`
  controls whether undeclared columns survive; `on_coercion_loss =
  c("error", "keep")` governs a coercion that would lose data. The pipeline
  never silently fabricates or drops a column: an undeclared column is reported
  and kept, a declared-but-absent column is reported and left absent.

* `check_spec()` validates a data frame against its spec across conformance
  dimensions toggled by `artoo_checks()`; `check_study()` runs it over a whole
  study and returns one stacked findings frame; `conformance()` reads the
  findings back off a stamped frame. `validate_spec()` checks a spec for
  internal consistency against a bundled rule catalog, with no external
  dependency.

* `decode_column()` translates coded values to or from their codelist decodes;
  `sync_meta()` reconciles a stamped frame's metadata after manual edits.

## Inspect

* `members()` is the format-neutral inventory of the dataset(s) a path holds,
  one row per dataset, dispatched through the codec registry. `columns()` is the
  SAS PROC CONTENTS / Universal Viewer variable pane over a stamped frame, a
  plain data frame, or a file path. `get_meta()` / `set_meta()` read and attach
  the `artoo_meta`.

## Errors

* Every condition artoo raises carries a three-level class chain —
  `artoo_<severity>_<kind>`, `artoo_<severity>`, `artoo_condition` — so a
  handler can catch a specific kind, a whole severity, or every artoo
  condition. The data-protection conditions attach their evidence as data
  (`cnd$variables`, `cnd$findings`) for programmatic inspection.

## Data

* Bundled demo specs `adam_spec` (ADaMIG 1.1) and `sdtm_spec` (SDTMIG 3.1.2),
  built reproducibly from the official CDISC Define-XML 2.1 release examples and
  shipped also as Pinnacle 21 workbooks under `inst/extdata/`. Demo datasets
  come from the PHUSE Test Data Factory; the constructor tables
  `cdisc_adam_datasets` / `cdisc_adam_variables`, `cdisc_sdtm_datasets` /
  `cdisc_sdtm_variables`, and the shared `cdisc_codelists` build a spec by hand.
  Every bundled dataset conforms to its bundled spec, gated at build and test
  time.

## Documentation

* An introductory `vignette("artoo")` plus task-oriented web articles
  (specifications; conform and validate; formats and lossless conversion;
  recipes), and a pkgdown reference site.
