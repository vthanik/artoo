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
