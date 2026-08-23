# spec_migrate.R — bring a spec saved by an older artoo up to the current class.
#
# An S7 object embeds a COMPLETE COPY of its class -- the property list and the
# validator -- in attr(x, "S7_class"). So a spec saved to .rds by an earlier
# artoo, or stored in another package's data/, keeps the class it was built
# with. When artoo later gains a property, that object becomes a zombie:
#
#   is_artoo_spec(x)   TRUE          <- passes every type guard
#   class(x)           unchanged     <- looks right
#   x@datasets         works         <- old properties still resolve
#   x@standards        Can't find property   <- dies here, in user code
#
# and S7::set_props() on it silently runs the OLD validator, so new invariants
# are quietly bypassed. Getting past every guard and failing deep inside a
# call is the worst available failure mode, which is why this exists.
#
# MECHANISM: rebuild through the constructor. Two other approaches look right
# and are not:
#
#   * S7::set_props(stale, new_prop = ...) ERRORS -- you cannot set a property
#     the embedded class does not declare.
#   * stamping attr(x, "S7_class") <- artoo_spec_class is a SILENT WRONG
#     ANSWER: S7 applies `default` only at construction, so the new property
#     reads back NULL rather than its declared empty table, and no validator
#     runs. The failure then surfaces far away as "argument is of length zero".
#
# Rebuilding costs a re-validation, which is the point: the object that comes
# out satisfies the CURRENT invariants, not the ones in force when it was
# saved.

# Has this object's embedded class fallen behind the live one?
#' @noRd
.spec_stale <- function(x) {
  cls <- attr(x, "S7_class", exact = TRUE)
  if (is.null(cls)) {
    return(FALSE)
  }
  have <- tryCatch(
    names(S7::prop(cls, "properties")),
    error = function(e) NULL
  )
  if (is.null(have)) {
    return(FALSE)
  }
  want <- names(S7::prop(artoo_spec_class, "properties"))
  length(setdiff(want, have)) > 0L
}

# Warn once per session rather than on every accessor call: a script that
# touches a stale spec twenty times should say so once.
.spec_migrate_env <- new.env(parent = emptyenv())

#' @noRd
.spec_migrate <- function(x, call = rlang::caller_env()) {
  if (!.spec_stale(x)) {
    return(x)
  }
  have <- names(S7::prop(attr(x, "S7_class", exact = TRUE), "properties"))
  # Read the old properties off the object directly. They are attributes, so
  # this works without the class declaring them.
  old <- function(nm) if (nm %in% have) attr(x, nm, exact = TRUE) else NULL

  if (is.null(.spec_migrate_env$told)) {
    .artoo_inform(
      c(
        "Upgrading a spec saved by an older version of artoo.",
        "i" = "Save it again with {.fn write_spec} to avoid this on every read."
      ),
      kind = "spec"
    )
    .spec_migrate_env$told <- TRUE
  }

  artoo_spec(
    datasets = old("datasets"),
    variables = old("variables"),
    codelists = old("codelists"),
    study = old("study"),
    values = old("values"),
    methods = old("methods"),
    comments = old("comments"),
    documents = old("documents"),
    standard = .spec_migrate_standard(old("standard")),
    standards = old("standards"),
    where_clauses = old("where_clauses"),
    method_expressions = old("method_expressions"),
    arm_displays = old("arm_displays"),
    arm_results = old("arm_results"),
    dictionaries = old("dictionaries")
  )
}

# `standard` is a scalar that may legitimately be NA; the constructor treats
# NULL as "unspecified" and NA as a value, so normalise.
#' @noRd
.spec_migrate_standard <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[[1]])) {
    return(NULL)
  }
  as.character(x[[1]])
}
