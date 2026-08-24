# define_emit.R — build XML as an ordered node-spec tree, then emit it.
#
# Builders never touch xml2. They return .dx_node() specs whose children are a
# NAMED list, and .dx_emit() writes those children in the order the version
# profile declares for that element's xs:sequence.
#
# The consequence is the point: a builder cannot get element order wrong,
# because it never chooses the order. Assigning node$kids[["def:Class"]]
# before or after the ItemRef slot produces byte-identical output. The prior
# art emitted def:Class before ItemRef -- invalid against the schema -- and
# shipped it through 116 tests, because there the order lived in the statement
# sequence of one very long function where nothing could check it.
#
# Two further guards fall out of the same design:
#   * a child name the sequence does not mention ABORTS, so a 2.1-only element
#     cannot leak into a 2.0 document.
#   * an attribute outside the element's legal set ABORTS, for the same reason.
# Both fire at build time, naming the element, rather than surfacing later as
# a schema error against a line number.

# One node in the tree. `kids` is a NAMED list; a name may hold one node or a
# list of nodes (repeated elements).
#' @noRd
.dx_node <- function(name, attrs = list(), kids = list(), text = NULL) {
  list(name = name, attrs = attrs, kids = kids, text = text)
}

# Drop NA / empty attributes: an absent attribute and one set to "" are
# different in XML, and emitting the latter breaks enumerated types.
#' @noRd
.dx_attrs <- function(...) {
  a <- list(...)
  keep <- vapply(
    a,
    function(v) {
      length(v) == 1L && !is.na(v) && nzchar(as.character(v))
    },
    logical(1)
  )
  lapply(a[keep], as.character)
}

# A Description/TranslatedText wrapper, the shape ODM uses for every piece of
# human-readable text.
#' @noRd
.dx_desc <- function(text, lang = "en") {
  if (is.null(text) || is.na(text) || !nzchar(text)) {
    return(NULL)
  }
  .dx_node(
    "Description",
    kids = list(
      TranslatedText = .dx_node(
        "TranslatedText",
        attrs = list(`xml:lang` = lang),
        text = as.character(text)
      )
    )
  )
}

# Recursively write a node spec into an xml2 parent.
#' @noRd
.dx_emit <- function(parent, node, p, call = rlang::caller_env()) {
  args <- c(list(parent, node$name), node$attrs)
  el <- do.call(xml2::xml_add_child, args)
  if (!is.null(node$text)) {
    xml2::xml_text(el) <- node$text
  }

  kids <- Filter(Negate(is.null), node$kids)
  if (!length(kids)) {
    return(invisible(el))
  }

  ord <- p$order[[node$name]]
  if (is.null(ord)) {
    .artoo_abort(
      c(
        "No child order is declared for {.val {node$name}}.",
        "i" = "Add it to the Define-XML {p$version} profile's order table."
      ),
      kind = "define",
      call = call
    )
  }
  stray <- setdiff(names(kids), ord)
  if (length(stray)) {
    .artoo_abort(
      c(
        "{.val {node$name}} cannot carry {.val {stray}} in Define-XML {p$version}.",
        "i" = "Its schema sequence is {.val {ord}}."
      ),
      kind = "define",
      call = call
    )
  }

  # THE guarantee: children are written in the profile's order, never the
  # order the builder happened to assign them in.
  for (nm in ord) {
    kid <- kids[[nm]]
    if (is.null(kid)) {
      next
    }
    if (!is.null(kid$name)) {
      kid <- list(kid)
    }
    for (k in kid) {
      if (!is.null(k)) {
        .dx_emit(el, k, p, call)
      }
    }
  }
  invisible(el)
}

# Serialise a document node spec to a character vector, injecting the
# stylesheet processing instruction.
#
# xml2 has no API for a processing instruction before the root element, so the
# PI is spliced into the serialised text. The XML declaration is asserted
# rather than reconstructed: inventing one when xml2's output changed shape
# would silently produce a malformed document.
#' @noRd
.dx_serialise <- function(doc, stylesheet_href, call = rlang::caller_env()) {
  txt <- as.character(doc)
  if (is.null(stylesheet_href)) {
    return(txt)
  }
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  if (!length(lines) || !grepl("^<\\?xml ", lines[[1]])) {
    .artoo_abort(
      c(
        "Could not place the stylesheet reference.",
        "x" = "The serialised document does not begin with an XML declaration.",
        "i" = "Pass {.code stylesheet = NULL} to write the file without one."
      ),
      kind = "define",
      call = call
    )
  }
  pi <- sprintf('<?xml-stylesheet type="text/xsl" href="%s"?>', stylesheet_href)
  paste(c(lines[[1]], pi, lines[-1]), collapse = "\n")
}
