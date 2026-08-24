# an element with no declared order is refused

    Code
      emit_to_text(node)
    Condition
      Error in `emit_to_text()`:
      ! No child order is declared for "MadeUpElement".
      i Add it to the Define-XML 2.1 profile's order table.

# a child the version's sequence does not allow is refused

    Code
      emit_to_text(node)
    Condition
      Error in `emit_to_text()`:
      ! "ItemGroupDef" cannot carry "def:Standards" in Define-XML 2.1.
      i Its schema sequence is "Description", "ItemRef", "Alias", "def:Class", and "def:leaf".

# serialising without an XML declaration is refused

    Code
      artoo:::.dx_serialise(node, "define2-1.xsl")
    Condition
      Error:
      ! Could not place the stylesheet reference.
      x The serialised document does not begin with an XML declaration.
      i Pass `stylesheet = FALSE` to write the file without one.

# a def: attribute the version does not have is refused

    Code
      artoo:::.dx_emit(doc, node, artoo:::.define_profile("2.0"))
    Condition
      Error:
      ! "CodeList" cannot carry "def:StandardOID" in Define-XML 2.0.
      i That attribute does not exist in this version of the standard.

