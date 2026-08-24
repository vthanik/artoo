# Re-derive Define-XML child order from the BUNDLED schemas.
#
# The version profiles in R/define_profile.R hard-code the xs:sequence of
# every element artoo emits, because a data table is the only form the
# emitter can check a builder against. A hard-coded copy of someone else's
# schema goes stale silently, so this helper reads the sequences back out of
# the XSDs that ship with the package and the test compares the two.
#
# Three schema facts make this more than an XPath:
#
#   * Define-XML redefines the ODM foundation through xs:redefine, so an
#     element's real sequence is ODM's with the def: extension groups spliced
#     in at the position the ODM type refers to them.
#   * a redefined group opens with a self-reference to the ORIGINAL group,
#     which is empty in ODM; it is skipped rather than resolved.
#   * def: elements live in their own schema under a different complexType
#     naming convention, and refer to ODM children with an odm: prefix.

.schema_dir <- function(version) {
  dir <- c("2.0" = "2.0.0", "2.1" = "2.1.0")[[version]]
  root <- system.file("extdata", dir, package = "artoo")
  if (!nzchar(root)) {
    root <- testthat::test_path("..", "..", "inst", "extdata", dir)
  }
  root
}

.xsd_kids <- function(node) {
  # Document order, elements and group references alike.
  hits <- xml2::xml_find_all(
    node,
    ".//*[local-name()='element' or local-name()='group']"
  )
  vapply(
    hits,
    function(h) {
      ref <- xml2::xml_attr(h, "ref")
      nm <- xml2::xml_attr(h, "name")
      kind <- xml2::xml_name(h)
      paste0(kind, ":", if (is.na(ref)) nm else ref)
    },
    character(1)
  )
}

# XSD text with comments stripped. Deprecated attribute references are
# COMMENTED OUT rather than removed (def:Label, def:DomainKeys, def:Rank in
# 2.0), so a derivation that reads the raw text would report attributes no
# document may use.
.xsd_text <- function(path) {
  gsub("<!--.*?-->", "", paste(readLines(path, warn = FALSE), collapse = "\n"))
}

# The def:-namespaced attributes each element may carry, per version. Mirrors
# the `def_attrs` table in R/define_profile.R.
.dx_schema_def_attrs <- function(version) {
  dir <- .schema_dir(version)
  defdir <- file.path(dir, paste0("cdisc-define-", version))
  out <- list()
  pull <- function(txt, pattern, prefix) {
    for (m in regmatches(txt, gregexpr(pattern, txt, perl = TRUE))[[1]]) {
      el <- sub(pattern, "\\1", m, perl = TRUE)
      # ATTRIBUTE references only. A bare ref="def:..." also matches the
      # element and group references these blocks are full of.
      refs <- regmatches(
        m,
        gregexpr('<xs:attribute ref="def:[^"]+"', m)
      )[[1]]
      refs <- sort(unique(sub('<xs:attribute ref="', "", sub('"$', "", refs))))
      if (length(refs)) {
        out[[paste0(prefix, el)]] <<- refs
      }
    }
  }
  pull(
    .xsd_text(file.path(defdir, "define-extension.xsd")),
    '(?s)<xs:attributeGroup name="([A-Za-z]+)AttributeExtension">.*?</xs:attributeGroup>',
    ""
  )
  pull(
    .xsd_text(file.path(defdir, "define-ns.xsd")),
    '(?s)<xs:complexType name="DEFINEcomplexTypeDefinition-([A-Za-z]+)">.*?</xs:complexType>',
    "def:"
  )
  # ARM declares its elements inline rather than as named complexTypes, and
  # arm:AnalysisDatasets is the one that borrows a def: attribute.
  pull(
    .xsd_text(file.path(dir, "cdisc-arm-1.0", "arm-ns.xsd")),
    '(?s)<xs:element name = "([A-Za-z]+)">.*?</xs:element>',
    "arm:"
  )
  out
}

# The LOCAL (unprefixed) attributes each def: element declares. Used to pin
# the claim that def:Origin/@Source is the only local attribute the two
# versions disagree about -- the emitter's def: guard cannot see local ones.
.dx_schema_local_attrs <- function(version) {
  dir <- .schema_dir(version)
  txt <- .xsd_text(file.path(
    dir,
    paste0("cdisc-define-", version),
    "define-ns.xsd"
  ))
  out <- list()
  pattern <- '(?s)<xs:complexType name="DEFINEcomplexTypeDefinition-([A-Za-z]+)">.*?</xs:complexType>'
  for (m in regmatches(txt, gregexpr(pattern, txt, perl = TRUE))[[1]]) {
    el <- sub(pattern, "\\1", m, perl = TRUE)
    nm <- regmatches(m, gregexpr('<xs:attribute name="[^"]+"', m))[[1]]
    out[[paste0("def:", el)]] <- sort(unique(sub(
      '<xs:attribute name="',
      "",
      sub('"$', "", nm)
    )))
  }
  out
}

.xsd_type <- function(doc, name) {
  xml2::xml_find_first(
    doc,
    sprintf("//*[local-name()='complexType'][@name='%s']", name)
  )
}

# The def: extension group of a given name, as a plain vector of element refs.
.xsd_ext_group <- function(ext, name) {
  g <- xml2::xml_find_first(
    ext,
    sprintf("//*[local-name()='group'][@name='%s']", name)
  )
  if (is.na(g)) {
    return(character(0))
  }
  refs <- xml2::xml_attr(
    xml2::xml_find_all(g, ".//*[local-name()='element']"),
    "ref"
  )
  refs[!is.na(refs)]
}

# Every element order artoo could need, keyed the way the profile keys it.
.dx_schema_order <- function(version) {
  dir <- .schema_dir(version)
  defdir <- file.path(dir, paste0("cdisc-define-", version))
  odm <- xml2::read_xml(file.path(
    dir,
    "cdisc-odm-1.3.2",
    "ODM1-3-2-foundation.xsd"
  ))
  ext <- xml2::read_xml(file.path(defdir, "define-extension.xsd"))
  ns <- xml2::read_xml(file.path(defdir, "define-ns.xsd"))

  out <- list()

  odm_elements <- c(
    "Study",
    "GlobalVariables",
    "MetaDataVersion",
    "ItemGroupDef",
    "ItemDef",
    "ItemRef",
    "CodeList",
    "CodeListItem",
    "EnumeratedItem",
    "MethodDef",
    "RangeCheck",
    "Description",
    "Decode"
  )
  for (el in odm_elements) {
    ty <- .xsd_type(odm, paste0("ODMcomplexTypeDefinition-", el))
    if (is.na(ty)) {
      next
    }
    kids <- character(0)
    for (k in .xsd_kids(ty)) {
      kind <- sub(":.*$", "", k)
      what <- sub("^[^:]*:", "", k)
      if (kind == "group") {
        if (grepl("ElementExtension$", what)) {
          kids <- c(kids, .xsd_ext_group(ext, what))
        }
      } else {
        kids <- c(kids, what)
      }
    }
    out[[el]] <- kids
  }

  def_types <- xml2::xml_find_all(
    ns,
    "//*[local-name()='complexType'][starts-with(@name, 'DEFINEcomplexTypeDefinition-')]"
  )
  for (ty in def_types) {
    el <- sub("^DEFINEcomplexTypeDefinition-", "", xml2::xml_attr(ty, "name"))
    kids <- .xsd_kids(ty)
    kids <- sub("^element:", "", kids[startsWith(kids, "element:")])
    # An ODM child is referenced with an odm: prefix here; a locally declared
    # child (def:leaf's title) carries no prefix at all and IS in def:.
    kids <- ifelse(
      grepl("^(odm|def):", kids),
      sub("^odm:", "", kids),
      paste0("def:", kids)
    )
    out[[paste0("def:", el)]] <- kids
  }
  out
}
