# define_validate.R — validate_define(): schema-validate a Define-XML document.
#
# artoo ships the CDISC schema trees (inst/extdata/{2.0.0,2.1.0}/), so this
# runs offline, on the user's machine, with no network round trip on what is a
# submission-critical path.
#
# Three design facts, each measured rather than assumed:
#
#   * ALWAYS validate against the ARM root. It is a strict superset of the
#     define root -- verified in both directions, both versions -- so one root
#     per version suffices. Validating a document that carries arm: content
#     against the define root FAILS, and nothing in artoo should have to know
#     in advance whether ARM is present.
#
#   * xml2::xml_validate() returns TRUE with a NON-EMPTY errors attribute.
#     Schema-compilation chatter ("Skipping import ...") rides along on a
#     perfectly valid document, so the verdict is as.logical(), never
#     length(attr(res, "errors")) == 0.
#
#   * A partial install degrades silently to valid = FALSE rather than
#     erroring, which a user reads as "my define.xml is broken". The schema
#     tree is therefore pre-flighted, and a missing file raises
#     artoo_error_install -- a different kind, catchable separately, because
#     it is an artoo packaging problem and not a defect in the user's file.
#
# Two schema constraints are NOT enforced by libxml2 and so cannot be caught
# here; they are the writer's job (see .dx_origin() and the DefineVersion
# assert): 2.0's fixed="2.0.0" on def:DefineVersion is dropped through
# xs:redefine, and 2.0's def:Origin/@Type is odm:text rather than an enum.

# Public version labels, and where each version's assets live.
.define_versions <- c("2.0", "2.1")
.define_asset_dir <- c("2.0" = "2.0.0", "2.1" = "2.1.0")

# The ARM root for each version. Both are named arm1-0-0.xsd but they are NOT
# interchangeable: the 2.0 tree's targets def/v2.0 and the 2.1 tree's targets
# def/v2.1, and each resolves its imports relative to its own directory.
.define_schema_root <- c(
  "2.0" = "cdisc-arm-1.0/arm1-0-0.xsd",
  "2.1" = "cdisc-arm-1.0/arm1-0-0.xsd"
)

# The def namespace URI carried by each version's documents.
.define_ns_uri <- c(
  "2.0" = "http://www.cdisc.org/ns/def/v2.0",
  "2.1" = "http://www.cdisc.org/ns/def/v2.1"
)

# Single accessor for the bundled asset tree. Everything that reaches into
# inst/extdata/ goes through here, which keeps the install-failure paths
# reachable from tests via local_mocked_bindings().
#' @noRd
.artoo_extdata <- function(...) {
  system.file("extdata", ..., package = "artoo")
}

# Schema-compilation chatter, not a document error.
#' @noRd
.define_msg_informational <- function(x) {
  grepl("Skipping import", x, fixed = TRUE)
}

# A schema file artoo failed to read. An artoo packaging fault, never a
# property of the document under test.
#' @noRd
.define_msg_infrastructure <- function(x) {
  grepl("Failed to locate|failed to load", x)
}

# Detect the Define-XML version from the document's namespace declarations.
# Returns NA_character_ when no def namespace is present.
#' @noRd
.define_detect_version <- function(doc) {
  uris <- unlist(xml2::xml_ns(doc), use.names = FALSE)
  for (v in .define_versions) {
    if (any(uris == .define_ns_uri[[v]])) {
      return(v)
    }
  }
  NA_character_
}

# Resolve a version's schema root, pre-flighting the whole tree first so a
# partial install is reported as such.
#' @noRd
.define_schema_path <- function(version, call = rlang::caller_env()) {
  dir <- .define_asset_dir[[version]]
  root <- .artoo_extdata(dir, .define_schema_root[[version]])
  if (!nzchar(root)) {
    expected <- file.path("extdata", dir, .define_schema_root[[version]])
    .artoo_abort(
      c(
        "The Define-XML {version} schema tree is missing from the artoo install.",
        "x" = "Expected {.path {expected}}.",
        "i" = "Reinstall artoo; the schemas ship with the package."
      ),
      kind = "install",
      call = call
    )
  }
  .define_check_tree(dir, call)
  root
}

# Every file the manifest lists for this version must be present. Cheap, and
# it turns a confusing "your document is invalid" into an accurate
# "artoo's install is incomplete".
#' @noRd
.define_check_tree <- function(dir, call = rlang::caller_env()) {
  manifest <- .artoo_extdata("MANIFEST.sha256")
  if (!nzchar(manifest)) {
    return(invisible(NULL))
  }
  lines <- readLines(manifest, warn = FALSE)
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  paths <- sub("^\\S+\\s+", "", lines)
  paths <- paths[startsWith(paths, paste0(dir, "/"))]
  missing <- paths[
    !vapply(
      paths,
      function(p) nzchar(.artoo_extdata(p)),
      logical(1)
    )
  ]
  if (length(missing)) {
    .artoo_abort(
      c(
        "The Define-XML schema tree is incomplete in this artoo install.",
        "x" = "Missing {length(missing)} file{?s}, including {.path {missing[1]}}.",
        "i" = "Reinstall artoo. This is not a problem with your document."
      ),
      kind = "install",
      call = call
    )
  }
  invisible(NULL)
}

#' Validate a Define-XML document against its CDISC schema
#'
#' Schema-validates a `define.xml` against the Clinical Data Interchange
#' Standards Consortium (CDISC) XML Schema that artoo bundles, offline. Use it
#' on a document from any source, whether or not artoo wrote it, as the first
#' gate before a submission package leaves your hands.
#'
#' @details
#' **The version is detected, not assumed.** Define-XML 2.0 and 2.1 declare
#' different `def` namespaces, so the document says which schema applies.
#' Passing `version` overrides that, which is how you confirm a file really is
#' the version it claims.
#'
#' **Schema validity is a floor, not a ceiling.** A document can satisfy the
#' schema and still be unfit to submit. Two whole classes of defect are
#' invisible here: a reference that points at nothing, and a definition that
#' nothing points at. Neither is expressible in XML Schema. Use
#' [lint_define()] for those.
#'
#' @param path *Define-XML document to validate.* `<character(1)>: required`.
#' @param version *Define-XML version to validate against.*
#'   `<character(1)> | NULL`. `NULL` (default) reads it from the document's
#'   `def` namespace. Supply `"2.0"` or `"2.1"` to assert a version instead,
#'   which turns a version mismatch into findings rather than silent success.
#'
#' @return *An `artoo_check` object.* Its `@findings` data frame has columns
#'   `check`, `dimension`, `severity`, `dataset`, `variable`, `message`, and is
#'   empty when the document is valid. Print it for the sectioned report.
#'
#' @examples
#' # ---- Example 1: a conforming document ----
#' #
#' # artoo bundles both CDISC schema trees, so validation runs offline. The
#' # bundled minimal example conforms, so the findings table comes back empty
#' # and the summary records which version was detected.
#' minimal <- system.file("extdata", "define-minimal.xml", package = "artoo")
#' report <- validate_define(minimal)
#' nrow(report@findings)
#' report@summary[c("define_version", "valid")]
#'
#' # ---- Example 2: a document that breaks the schema ----
#' #
#' # Give ItemGroupDef/@Repeating a value outside its enumeration. The schema
#' # catches it, and each violation becomes one finding naming the element and
#' # the line it sits on.
#' broken <- tempfile(fileext = ".xml")
#' writeLines(
#'   sub('Repeating="No"', 'Repeating="Maybe"', readLines(minimal), fixed = TRUE),
#'   broken
#' )
#' bad <- validate_define(broken)
#' bad@summary$valid
#' substr(bad@findings$message[1], 1, 60)
#'
#' @seealso
#' **Check further:** [lint_define()] for reference integrity, which schema
#' validation cannot see.
#'
#' **Specs:** [read_spec()] reads a Define-XML document into an
#' [artoo_spec()].
#'
#' @export
validate_define <- function(path, version = NULL) {
  call <- rlang::current_env()
  rlang::check_installed("xml2", reason = "to validate Define-XML documents.")
  .check_path(path, call = call)

  if (!file.exists(path)) {
    .artoo_abort(
      c(
        "{.path {path}} does not exist.",
        "i" = "Check the path, or pass the file artoo should validate."
      ),
      kind = "input",
      call = call
    )
  }
  doc <- tryCatch(
    xml2::read_xml(path),
    error = function(e) {
      msg <- .safe_msg(e)
      .artoo_abort(
        c(
          "{.path {path}} is not parseable XML.",
          "x" = "{msg}"
        ),
        kind = "input",
        call = call
      )
    }
  )

  version <- .define_resolve_version(doc, version, path, call)
  schema <- xml2::read_xml(.define_schema_path(version, call))

  res <- xml2::xml_validate(doc, schema)
  msgs <- as.character(attr(res, "errors"))

  infra <- msgs[.define_msg_infrastructure(msgs)]
  if (length(infra)) {
    .artoo_abort(
      c(
        "artoo could not load its bundled Define-XML {version} schema.",
        "x" = "{infra[1]}",
        "i" = "Reinstall artoo. This is not a problem with {.path {path}}."
      ),
      kind = "install",
      call = call
    )
  }

  real <- msgs[!.define_msg_informational(msgs)]
  findings <- .finding(
    "define_schema_invalid",
    dataset = NA_character_,
    variable = NA_character_,
    message = real
  )

  artoo_check_class(
    findings = findings,
    scope = character(0),
    study = basename(path),
    summary = list(
      define_version = version,
      valid = as.logical(res) && !length(real),
      n_errors = length(real)
    )
  )
}

# Decide which version to validate against, and refuse the documents artoo
# cannot help with rather than drowning the user in schema errors.
#' @noRd
.define_resolve_version <- function(doc, version, path, call) {
  if (!is.null(version)) {
    version <- as.character(version)
    if (length(version) != 1L || !version %in% .define_versions) {
      # Bind to a local: cli reads `{.val {.define_versions}}` as an inline
      # style named ".define_versions" because the expression starts with a dot.
      known <- .define_versions
      .artoo_abort(
        c(
          "{.arg version} must be {.val {known[1]}} or {.val {known[2]}}.",
          "x" = "You supplied {.val {version}}."
        ),
        kind = "input",
        call = call
      )
    }
    return(version)
  }

  detected <- .define_detect_version(doc)
  if (!is.na(detected)) {
    return(detected)
  }

  uris <- unlist(xml2::xml_ns(doc), use.names = FALSE)
  if (any(grepl("cdisc.org/ns/def/v1", uris, fixed = FALSE))) {
    .artoo_abort(
      c(
        "{.path {path}} is a Define-XML v1.0 document.",
        "x" = "artoo validates Define-XML 2.0 and 2.1.",
        "i" = "Re-export the define from a 2.x-capable tool."
      ),
      kind = "input",
      call = call
    )
  }
  .artoo_abort(
    c(
      "{.path {path}} is not a Define-XML document.",
      "x" = "It declares no CDISC {.field def} namespace.",
      "i" = "Pass {.arg version} to validate it as Define-XML anyway."
    ),
    kind = "input",
    call = call
  )
}
