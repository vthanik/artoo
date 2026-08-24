# define_build_arm.R — Analysis Results Metadata (ARM v1.0).
#
# ONE code path for both Define-XML versions. The 2.0 and 2.1 ARM schemas are
# byte-identical apart from the def: namespace URI they import, so nothing
# here branches on version: the def: children (def:DocumentRef,
# def:WhereClauseRef, def:CommentOID) resolve against whichever namespace the
# document root declared.
#
# Two grains, both forced by the schema. An arm:ResultDisplay carries at most
# one display-level def:DocumentRef, so `arm_displays` is one row per
# display. An arm:AnalysisResult carries one or more arm:AnalysisDataset,
# each with its OWN def:WhereClauseRef and its own analysis variables, so
# `arm_results` is one row per result x dataset and the result-level fields
# repeat across them -- the same shape `codelists` uses for its list-level
# columns.
#
# Identifiers arrive as NAMES (a dataset, a variable) because that is what a
# workbook carries, and are resolved through the symbol table. A value that
# resolves to nothing is passed through verbatim: a spec read from a document
# whose ARM references an ItemGroup the spec does not carry keeps the OID
# rather than losing the reference.

#' @noRd
.dx_arm_displays <- function(spec, oids, p, call = rlang::caller_env()) {
  displays <- spec@arm_displays
  if (!nrow(displays)) {
    if (nrow(spec@arm_results)) {
      .artoo_abort(
        c(
          "The spec carries analysis results but no displays.",
          "x" = "{nrow(spec@arm_results)} row{?s} in {.code arm_results}, none in {.code arm_displays}.",
          "i" = "Every {.code arm:AnalysisResult} lives inside an {.code arm:ResultDisplay}."
        ),
        kind = "define",
        call = call
      )
    }
    return(NULL)
  }
  results <- spec@arm_results
  # A result whose display does not exist would simply never be visited by
  # the loop below. The reader cannot produce that shape, so no round trip
  # can see it -- but a workbook with a mistyped or missing Displays sheet
  # produces exactly it, and the rows would vanish without a word.
  orphaned <- setdiff(
    as.character(results$display_id),
    as.character(displays$display_id)
  )
  if (length(orphaned)) {
    .artoo_abort(
      c(
        "{length(orphaned)} analysis result{?s} name a display the spec does not define.",
        "x" = "{.val {orphaned}}.",
        "i" = "Add them to {.code arm_displays}, or correct {.code display_id}."
      ),
      kind = "define",
      call = call
    )
  }
  pairs <- unique(results[c("display_id", "result_id")])
  shared <- unique(pairs$result_id[duplicated(pairs$result_id)])
  if (length(shared)) {
    .artoo_abort(
      c(
        "{length(shared)} analysis result{?s} under more than one display.",
        "x" = "{.val {shared}}.",
        "i" = "An {.code arm:AnalysisResult} OID must be unique in the document; give each display its own result ids."
      ),
      kind = "define",
      call = call
    )
  }
  ord <- .dx_row_order(displays)
  .dx_node(
    "arm:AnalysisResultDisplays",
    kids = list(
      `arm:ResultDisplay` = lapply(ord, function(i) {
        .dx_arm_display(displays, i, results, oids, p, call)
      })
    )
  )
}

#' @noRd
.dx_arm_display <- function(
  displays,
  i,
  results,
  oids,
  p,
  call = rlang::caller_env()
) {
  id <- displays$display_id[[i]]
  name <- .dx_chr(displays, "name")[[i]]
  mine <- results[
    !is.na(results$display_id) & results$display_id == id,
    ,
    drop = FALSE
  ]
  if (!nrow(mine)) {
    .artoo_abort(
      c(
        "Analysis display {.val {id}} has no results.",
        "x" = "{.code arm:ResultDisplay} requires at least one {.code arm:AnalysisResult}.",
        "i" = "Add rows to {.code arm_results} naming this display, or drop the display."
      ),
      kind = "define",
      call = call
    )
  }
  # Results in emission order, then grouped: every row of one result_id is
  # one arm:AnalysisDataset of the same arm:AnalysisResult.
  mine <- mine[.dx_row_order(mine), , drop = FALSE]
  ids <- unique(as.character(mine$result_id))
  .dx_node(
    "arm:ResultDisplay",
    attrs = .dx_attrs(
      OID = id,
      # @Name is required; a display that names only its id still names it.
      Name = if (.dx_blank(name)) id else name
    ),
    kids = list(
      # Description is required, so it falls back rather than emitting empty.
      Description = .dx_desc(.dx_arm_text(
        .dx_chr(displays, "description")[[i]],
        name,
        id
      )),
      `def:DocumentRef` = .dx_docref(
        .dx_chr(displays, "document_id")[[i]],
        .dx_chr(displays, "pages")[[i]],
        .dx_chr(displays, "page_type")[[i]],
        p,
        call,
        title = .dx_chr(displays, "page_title")[[i]]
      ),
      `arm:AnalysisResult` = lapply(ids, function(rid) {
        .dx_arm_result(
          mine[as.character(mine$result_id) == rid, , drop = FALSE],
          oids,
          p,
          call
        )
      })
    )
  )
}

# The first non-blank of a chain, for a schema-required text element.
#' @noRd
.dx_arm_text <- function(...) {
  for (v in c(...)) {
    if (!.dx_blank(v)) {
      return(v)
    }
  }
  NA_character_
}

#' @noRd
.dx_arm_result <- function(rows, oids, p, call = rlang::caller_env()) {
  id <- rows$result_id[[1]]
  # The result-level columns repeat across a result's dataset rows, the way
  # the codelist slot repeats its list-level fields. .dx_one() takes the one
  # non-blank value; two DIFFERENT values mean the spec says two things, and
  # picking the first would contradict the refusal below to choose at all.
  .dx_check_result_headers(rows, id, call)
  reason <- .dx_one(.dx_chr(rows, "reason"))
  purpose <- .dx_one(.dx_chr(rows, "purpose"))
  missing <- c(
    if (.dx_blank(reason)) "reason",
    if (.dx_blank(purpose)) "purpose"
  )
  if (length(missing)) {
    # Both are schema-REQUIRED, and both are sponsor assertions about why an
    # analysis was run. Supplying a default would put a claim in the document
    # that nobody made.
    .artoo_abort(
      c(
        "Analysis result {.val {id}} is missing {.field {missing}}.",
        "x" = "{.code AnalysisReason} and {.code AnalysisPurpose} are required by the ARM schema.",
        "i" = "Set them on the {.code arm_results} row; artoo will not choose them for you."
      ),
      kind = "define",
      call = call
    )
  }
  .dx_node(
    "arm:AnalysisResult",
    attrs = .dx_attrs(
      OID = id,
      ParameterOID = .dx_one(.dx_chr(rows, "parameter_id")),
      AnalysisReason = reason,
      AnalysisPurpose = purpose
    ),
    kids = list(
      Description = .dx_desc(.dx_arm_text(
        .dx_one(.dx_chr(rows, "description")),
        id
      )),
      `arm:AnalysisDatasets` = .dx_node(
        "arm:AnalysisDatasets",
        attrs = .dx_attrs(
          "def:CommentOID" = .dx_one(.dx_chr(rows, "datasets_comment_id"))
        ),
        kids = list(
          `arm:AnalysisDataset` = lapply(seq_len(nrow(rows)), function(j) {
            .dx_arm_dataset(rows, j, oids, id, call)
          })
        )
      ),
      `arm:Documentation` = .dx_arm_documentation(rows, p, id, call),
      `arm:ProgrammingCode` = .dx_arm_code(rows, p, call)
    )
  )
}

# The columns that describe the RESULT rather than one of its datasets.
.dx_arm_result_headers <- c(
  "description",
  "parameter_id",
  "reason",
  "purpose",
  "datasets_comment_id",
  "documentation",
  "documentation_document_id",
  "documentation_pages",
  "documentation_page_type",
  "documentation_page_title",
  "programming_context",
  "programming_code",
  "programming_document_id",
  "programming_pages",
  "programming_page_type",
  "programming_page_title"
)

#' @noRd
.dx_check_result_headers <- function(rows, id, call = rlang::caller_env()) {
  if (nrow(rows) < 2L) {
    return(invisible(NULL))
  }
  split <- vapply(
    .dx_arm_result_headers,
    function(column) {
      values <- .dx_chr(rows, column)
      length(unique(values[!.dx_blank(values)])) > 1L
    },
    logical(1)
  )
  if (!any(split)) {
    return(invisible(NULL))
  }
  columns <- names(split)[split]
  .artoo_abort(
    c(
      "Analysis result {.val {id}} describes itself two ways.",
      "x" = "Its rows disagree on {.val {columns}}.",
      "i" = "Those columns describe the result, so they repeat on each of its dataset rows and must agree."
    ),
    kind = "define",
    call = call
  )
}

#' @noRd
.dx_arm_dataset <- function(rows, j, oids, id, call = rlang::caller_env()) {
  dataset <- .dx_chr(rows, "dataset")[[j]]
  group <- .dx_get(oids$dataset, dataset)
  if (is.na(group)) {
    # Not an error on its own: a spec read from a document whose ARM points
    # at an ItemGroup the spec does not carry keeps the OID verbatim rather
    # than losing the reference. define_lint() reports it as dangling.
    group <- dataset
  }
  if (.dx_blank(group)) {
    .artoo_abort(
      c(
        "Analysis result {.val {id}} names no analysis dataset.",
        "x" = "{.code arm:AnalysisDataset/@ItemGroupOID} is required.",
        "i" = "Set {.code dataset} on the {.code arm_results} row."
      ),
      kind = "define",
      call = call
    )
  }
  analysis_vars <- .dx_arm_variables(.dx_chr(rows, "variables")[[j]])
  wc <- .dx_chr(rows, "where_clause_id")[[j]]
  .dx_node(
    "arm:AnalysisDataset",
    attrs = .dx_attrs(ItemGroupOID = group),
    kids = list(
      `def:WhereClauseRef` = if (.dx_blank(wc)) {
        NULL
      } else {
        .dx_node("def:WhereClauseRef", attrs = .dx_attrs(WhereClauseOID = wc))
      },
      `arm:AnalysisVariable` = lapply(analysis_vars, function(v) {
        oid <- .dx_get(oids$variable, .dx_key(dataset, v))
        .dx_node(
          "arm:AnalysisVariable",
          attrs = .dx_attrs(ItemOID = if (is.na(oid)) v else oid)
        )
      })
    )
  )
}

# The analysis variables of one dataset, from the space-separated column.
#' @noRd
.dx_arm_variables <- function(x) {
  if (.dx_blank(x)) {
    return(character(0))
  }
  v <- strsplit(trimws(x), "[[:space:]]+")[[1]]
  v[nzchar(v)]
}

#' @noRd
.dx_arm_documentation <- function(rows, p, id, call = rlang::caller_env()) {
  text <- .dx_one(.dx_chr(rows, "documentation"))
  ref <- .dx_docref(
    .dx_one(.dx_chr(rows, "documentation_document_id")),
    .dx_one(.dx_chr(rows, "documentation_pages")),
    .dx_one(.dx_chr(rows, "documentation_page_type")),
    p,
    call,
    title = .dx_one(.dx_chr(rows, "documentation_page_title"))
  )
  if (.dx_blank(text)) {
    if (is.null(ref)) {
      return(NULL)
    }
    # Description is required inside arm:Documentation, so a reference with
    # nothing to say cannot be written.
    .artoo_abort(
      c(
        "Analysis result {.val {id}} documents a reference but says nothing.",
        "x" = "{.code arm:Documentation} requires a Description.",
        "i" = "Set {.code documentation}, or clear {.code documentation_document_id}."
      ),
      kind = "define",
      call = call
    )
  }
  .dx_node(
    "arm:Documentation",
    kids = list(Description = .dx_desc(text), `def:DocumentRef` = ref)
  )
}

#' @noRd
.dx_arm_code <- function(rows, p, call = rlang::caller_env()) {
  code <- .dx_one(.dx_chr(rows, "programming_code"))
  context <- .dx_one(.dx_chr(rows, "programming_context"))
  ref <- .dx_docref(
    .dx_one(.dx_chr(rows, "programming_document_id")),
    .dx_one(.dx_chr(rows, "programming_pages")),
    .dx_one(.dx_chr(rows, "programming_page_type")),
    p,
    call,
    title = .dx_one(.dx_chr(rows, "programming_page_title"))
  )
  if (.dx_blank(code) && .dx_blank(context) && is.null(ref)) {
    return(NULL)
  }
  .dx_node(
    "arm:ProgrammingCode",
    attrs = .dx_attrs(Context = context),
    kids = list(
      `arm:Code` = if (.dx_blank(code)) {
        NULL
      } else {
        .dx_node("arm:Code", text = code)
      },
      `def:DocumentRef` = ref
    )
  )
}
