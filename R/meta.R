# meta.R -- the vport_meta spine.
#
# vport_meta is the CDISC-shaped metadata a conformed dataset carries: it
# is built once from a spec by .meta_from_spec(), serialized once to a
# Dataset-JSON v1.1 itemGroup string by .meta_to_datasetjson() (the SINGLE
# serializer every codec shares), and re-parsed by .meta_from_datasetjson().
# get_meta()/set_meta() bridge that string on/off an ordinary data frame's
# `metadata_json` attribute. Because there is exactly one serializer feeding
# the Dataset-JSON file codec AND every container's sidecar, the formats
# cannot drift, and any-to-any conversion is lossless by construction.

# ---- canonical field orders (frozen; round-trip identity depends on them) --
# Both .meta_from_spec() and .meta_from_datasetjson() build their lists in
# these orders so identical(meta, round_trip(meta)) holds.
.meta_col_fields <- c(
  "itemOID",
  "name",
  "label",
  "dataType",
  "targetDataType",
  "length",
  "displayFormat",
  "informat",
  "keySequence",
  "codelist",
  "significantDigits",
  "origin"
)
.meta_col_int_fields <- c("length", "keySequence", "significantDigits")
.meta_dataset_fields <- c(
  "itemGroupOID",
  "name",
  "label",
  "records",
  "studyOID",
  "metaDataVersionOID",
  "encoding",
  "keys"
)

# ---- small NA/NULL helpers --------------------------------------------------
.na_to_null <- function(x) {
  if (length(x) != 1L || is.na(x)) NULL else as.character(x)
}
.na_to_null_int <- function(x) {
  if (length(x) != 1L || is.na(x)) NULL else as.integer(x)
}
.drop_null <- function(x) x[!vapply(x, is.null, logical(1))]

# ---- build vport_meta from a spec ------------------------------------------

# One column entry (a list of present Dataset-JSON column attributes) from a
# single-row variable data frame slice. Absent (NA) attributes are dropped,
# matching Dataset-JSON's omit-when-absent convention -- which also makes the
# serializer round-trip an identity.
#' @noRd
.col_from_var_row <- function(row, dataset) {
  oid <- if (!is.na(row$itemoid)) {
    as.character(row$itemoid)
  } else {
    paste0("IT.", dataset, ".", row$variable)
  }
  col <- list(
    itemOID = oid,
    name = as.character(row$variable),
    label = .na_to_null(row$label),
    dataType = as.character(row$data_type),
    targetDataType = .na_to_null(row$target_data_type),
    length = .na_to_null_int(row$length),
    displayFormat = .na_to_null(row$display_format),
    informat = .na_to_null(row$informat),
    keySequence = .na_to_null_int(row$key_sequence),
    codelist = .na_to_null(row$codelist_id),
    significantDigits = .na_to_null_int(row$significant_digits),
    origin = .na_to_null(row$origin)
  )
  .drop_null(col)
}

# Derive the ordered sort-key variable names from per-column keySequence.
#' @noRd
.meta_keys <- function(cols) {
  ks <- vapply(cols, function(c) c$keySequence %||% NA_integer_, integer(1))
  keyed <- !is.na(ks)
  if (!any(keyed)) {
    return(character(0))
  }
  names(cols)[keyed][order(ks[keyed])]
}

# Assemble the dataset-level metadata list in canonical field order.
#' @noRd
.assemble_dataset_meta <- function(
  itemGroupOID,
  name,
  label = NULL,
  records = NULL,
  studyOID = NULL,
  metaDataVersionOID = NULL,
  encoding = NULL,
  keys = character(0)
) {
  .drop_null(list(
    itemGroupOID = itemGroupOID,
    name = name,
    label = label,
    records = records,
    studyOID = studyOID,
    metaDataVersionOID = metaDataVersionOID,
    encoding = encoding,
    keys = keys
  ))
}

# Build a vport_meta for one dataset from a validated spec. `records` is the
# row count; apply_spec()'s stamp step passes nrow(x), other callers leave it
# NULL (omitted from the metadata).
#' @noRd
.meta_from_spec <- function(
  spec,
  dataset,
  records = NULL,
  call = rlang::caller_env()
) {
  .check_dataset_arg(spec, dataset, call = call)

  vars <- spec_variables(spec, dataset)
  cols <- lapply(seq_len(nrow(vars)), function(i) {
    .col_from_var_row(vars[i, , drop = FALSE], dataset)
  })
  names(cols) <- vars$variable

  dat <- spec@datasets
  drow <- dat[!is.na(dat$dataset) & dat$dataset == dataset, , drop = FALSE]
  label <- if (nrow(drow) && "label" %in% names(drow)) {
    .na_to_null(drow$label[[1]])
  } else {
    NULL
  }

  study <- spec@study
  study_oid <- if ("studyid" %in% names(study) && nrow(study)) {
    .na_to_null(study$studyid[[1]])
  } else {
    NULL
  }

  ds_meta <- .assemble_dataset_meta(
    itemGroupOID = paste0("IG.", dataset),
    name = dataset,
    label = label,
    records = if (is.null(records)) NULL else as.integer(records),
    studyOID = study_oid,
    keys = .meta_keys(cols)
  )

  vport_meta_class(dataset = ds_meta, columns = cols)
}

# ---- build vport_meta from a bare frame (no spec) ---------------------------

# One column entry derived from a data frame column's attributes and R class
# (the no-spec path). A user/haven `label`/`format.sas` attribute wins;
# otherwise the dataType and default displayFormat are inferred from the class
# so a plain frame still writes with sensible metadata.
#' @noRd
.col_from_frame_col <- function(name, col, dataset) {
  ti <- .infer_frame_type(col)
  fmt_attr <- attr(col, "format.sas", exact = TRUE) %||%
    attr(col, "format", exact = TRUE)
  display_format <- if (!is.null(fmt_attr) && nzchar(fmt_attr)) {
    as.character(fmt_attr)
  } else {
    ti$display_format
  }
  len_attr <- attr(col, "SASlength", exact = TRUE) %||%
    attr(col, "width", exact = TRUE) %||%
    attr(col, "sas.length", exact = TRUE)
  label <- attr(col, "label", exact = TRUE)
  inf_attr <- attr(col, "informat.sas", exact = TRUE)
  col_meta <- list(
    itemOID = paste0("IT.", dataset, ".", name),
    name = name,
    label = .na_to_null(label %||% NA),
    dataType = ti$data_type,
    targetDataType = NULL,
    length = .resolve_xpt_length(len_attr, col),
    displayFormat = display_format,
    informat = if (!is.null(inf_attr) && nzchar(inf_attr)) {
      as.character(inf_attr)
    } else {
      NULL
    },
    keySequence = NULL,
    codelist = NULL,
    significantDigits = NULL,
    origin = NULL
  )
  .drop_null(col_meta)
}

# Build a vport_meta from a data frame that carries no metadata_json -- from
# its per-column attributes and R classes -- so write_*() preserves labels,
# formats, and types even without a spec. Returns NULL for a 0-column frame.
#' @noRd
.meta_from_frame <- function(x) {
  if (ncol(x) == 0L) {
    return(NULL)
  }
  raw_name <- attr(x, "dataset_name", exact = TRUE)
  ds_name <- if (
    is.character(raw_name) && length(raw_name) == 1L && nzchar(raw_name)
  ) {
    toupper(raw_name)
  } else {
    "DATA"
  }
  cols <- lapply(names(x), function(nm) {
    .col_from_frame_col(nm, x[[nm]], ds_name)
  })
  names(cols) <- names(x)

  ds_label <- attr(x, "label", exact = TRUE)
  ds_meta <- .assemble_dataset_meta(
    itemGroupOID = paste0("IG.", ds_name),
    name = ds_name,
    label = .na_to_null(ds_label %||% NA),
    records = nrow(x),
    keys = .meta_keys(cols)
  )
  vport_meta_class(dataset = ds_meta, columns = cols)
}

# ---- serializer: vport_meta <-> Dataset-JSON metadata string ----------------

# The ONE serializer's structural core. Builds the Dataset-JSON v1.1 itemGroup
# metadata block as a named list (no `rows` -- the data lives natively in each
# container; the .json file codec appends `rows` to this same list). Sharing
# this single payload builder between the sidecar string and the .json file
# codec is what keeps the formats from drifting (plan F4/4.0).
#
# Dataset-JSON v1.1 has closed vocabularies at the top level AND inside the
# `columns` array, so everything vport-specific rides a single namespaced
# `_vport` object instead of the standard block: `sourceEncoding` (the on-disk
# source-charset record), `informats` (a {variable: "DATE9."} map -- the
# column entries carry `informat` in-memory but it is stripped from the
# emitted array), and `specialMissings` (row-aligned .A-.Z/._ tags, passed by
# codecs as `special=`; see sas_missing.R for why they never enter the
# set_meta() sidecar). Whenever `_vport` is emitted it is stamped with
# `vportMetaVersion` for forward compatibility.
#' @noRd
.meta_payload <- function(meta, extensions = FALSE, special = NULL) {
  ds <- meta@dataset
  cols <- meta@columns
  informats <- .drop_null(lapply(cols, function(c) c$informat))
  cols <- lapply(cols, function(c) c[setdiff(names(c), "informat")])
  payload <- c(
    list(datasetJSONVersion = "1.1.0"),
    # keys derivable from keySequence; encoding is a vport extension. Neither
    # is spread into the standard CDISC block.
    ds[setdiff(names(ds), c("keys", "encoding"))],
    list(columns = unname(cols))
  )
  ext <- list()
  if (isTRUE(extensions)) {
    if (!is.null(ds$encoding)) {
      ext$sourceEncoding <- ds$encoding
    }
    if (length(informats)) {
      ext$informats <- informats
    }
    if (length(special)) {
      ext$specialMissings <- special
    }
  }
  if (length(ext)) {
    payload <- c(
      payload,
      list(`_vport` = c(list(vportMetaVersion = "1.0"), ext))
    )
  }
  payload
}

# The ONE serializer. Emits the metadata block as a JSON string; every codec
# embeds this exact string verbatim into its container's KV/attribute slot.
#' @noRd
.meta_to_datasetjson <- function(meta, extensions = FALSE, special = NULL) {
  jsonlite::toJSON(
    .meta_payload(meta, extensions, special = special),
    auto_unbox = TRUE,
    null = "null"
  )
}

# Pull the specialMissings block out of an already-parsed payload, re-typed
# to the .apply_special_missings() shape; NULL when the file carries none.
#' @noRd
.special_from_parsed <- function(p) {
  sm <- p[["_vport"]]$specialMissings
  if (is.null(sm) || !length(sm)) {
    return(NULL)
  }
  lapply(sm, function(e) {
    list(
      rows = as.integer(unlist(e$rows)),
      tags = as.character(unlist(e$tags))
    )
  })
}

# Coerce a parsed JSON scalar list back to a typed column entry in canonical
# field order, with integer attributes re-integerised.
#' @noRd
.col_from_parsed <- function(p) {
  col <- p[intersect(.meta_col_fields, names(p))]
  for (f in intersect(.meta_col_int_fields, names(col))) {
    col[[f]] <- as.integer(col[[f]])
  }
  for (f in setdiff(names(col), .meta_col_int_fields)) {
    col[[f]] <- as.character(col[[f]])
  }
  col
}

# Rebuild a vport_meta from an ALREADY-parsed Dataset-JSON object (the shape
# jsonlite::fromJSON(simplifyVector = FALSE) returns). The .json file codec,
# which parses the file once to also read `rows`, reuses this directly; the
# string entry point .meta_from_datasetjson() parses then delegates here.
#' @noRd
.meta_from_parsed <- function(p) {
  cols <- lapply(p$columns, .col_from_parsed)
  names(cols) <- vapply(cols, function(c) c$name, character(1))

  # Informats ride _vport (the CDISC columns vocabulary is closed); merge them
  # back into the column entries, re-ordered to the canonical field order so
  # the round-trip stays an identity.
  informats <- p[["_vport"]]$informats
  if (!is.null(informats) && length(informats)) {
    for (nm in intersect(names(informats), names(cols))) {
      cols[[nm]]$informat <- as.character(informats[[nm]])
      cols[[nm]] <- cols[[nm]][intersect(.meta_col_fields, names(cols[[nm]]))]
    }
  }

  records <- if (!is.null(p$records)) as.integer(p$records) else NULL
  enc <- if (
    !is.null(p[["_vport"]]) && !is.null(p[["_vport"]]$sourceEncoding)
  ) {
    as.character(p[["_vport"]]$sourceEncoding)
  } else {
    NULL
  }
  ds_meta <- .assemble_dataset_meta(
    itemGroupOID = as.character(p$itemGroupOID),
    name = as.character(p$name),
    label = .na_to_null(p$label %||% NA),
    records = records,
    studyOID = .na_to_null(p$studyOID %||% NA),
    metaDataVersionOID = .na_to_null(p$metaDataVersionOID %||% NA),
    encoding = enc,
    keys = .meta_keys(cols)
  )

  vport_meta_class(dataset = ds_meta, columns = cols)
}

# Inverse of .meta_to_datasetjson(): parse the metadata string back to a
# vport_meta, reconstructed in the same canonical orders so the round-trip
# is an identity.
#' @noRd
.meta_from_datasetjson <- function(json) {
  .meta_from_parsed(jsonlite::fromJSON(json, simplifyVector = FALSE))
}

# ---- public frame bridge ----------------------------------------------------

#' Test for a vport_meta object
#'
#' Report whether an object is a `vport_meta` -- the CDISC-shaped metadata a
#' conformed dataset carries through the vport workflow (spec -> apply_spec ->
#' read_/write_). [get_meta()] returns one; this is the type guard before you
#' inspect its `@dataset` and `@columns` slots.
#'
#' @param x *Object to test.* `<any>`.
#'
#' @return *A `<logical(1)>`*: `TRUE` when `x` is a `vport_meta`, else `FALSE`.
#'
#' @examples
#' # ---- Example 1: guard before inspecting metadata ----
#' #
#' # get_meta() yields a vport_meta; is_vport_meta() confirms the type before
#' # you reach into its slots.
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL")
#' meta <- get_meta(adsl)
#' is_vport_meta(meta)
#'
#' # ---- Example 2: a bare data frame carries no meta object ----
#' #
#' # The raw frame itself is not a vport_meta -- only the object get_meta()
#' # returns is.
#' is_vport_meta(cdisc_adsl)
#'
#' @seealso [get_meta()] and [set_meta()] to read and attach metadata.
#' @export
is_vport_meta <- function(x) {
  S7::S7_inherits(x, vport_meta_class)
}

#' Read the metadata a dataset carries
#'
#' Pull the `vport_meta` off a data frame produced by [apply_spec()] or read
#' back by any `read_*()` codec. The metadata travels as a single
#' Dataset-JSON string in the frame's `metadata_json` attribute; `get_meta()`
#' parses it to the S7 object, the form every codec writes from. This is the
#' read half of the lossless round-trip.
#'
#' @param x *A data frame carrying vport metadata.* `<data.frame>: required`.
#'   Typically the output of [apply_spec()] or a `read_*()` codec.
#'
#'   **Requirement:** `x` must carry a `metadata_json` attribute (set by
#'   [set_meta()], [apply_spec()], or a reader); a bare frame aborts with
#'   `vport_error_input`.
#'
#' @return *A `<vport_meta>`* with dataset-level (`@dataset`) and per-column
#'   (`@columns`) CDISC attributes. Pass it to [set_meta()] to re-attach, or
#'   inspect it directly.
#'
#' @examples
#' # ---- Example 1: read metadata off a conformed dataset ----
#' #
#' # apply_spec() stamps the metadata; get_meta() reads it back as the S7
#' # object whose @columns holds one CDISC attribute set per variable.
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL")
#' meta <- get_meta(adsl)
#' meta@columns$STUDYID
#'
#' # ---- Example 2: round-trip metadata across two frames ----
#' #
#' # The metadata is a portable object: read it off one frame and stamp it
#' # onto another with set_meta().
#' bare <- as.data.frame(adsl)
#' attr(bare, "metadata_json") <- NULL
#' restamped <- set_meta(bare, meta)
#' identical(get_meta(restamped)@columns, meta@columns)
#'
#' @seealso [set_meta()] for the write half; [apply_spec()] which stamps it.
#' @export
get_meta <- function(x) {
  call <- rlang::caller_env()
  json <- attr(x, "metadata_json", exact = TRUE)
  if (!is.character(json) || length(json) != 1L) {
    cli::cli_abort(
      c(
        "{.arg x} carries no vport metadata.",
        "x" = "No {.field metadata_json} attribute was found.",
        "i" = "Run {.fn apply_spec} or {.fn set_meta} to attach metadata first."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  .meta_from_datasetjson(json)
}

#' Attach metadata to a dataset
#'
#' Stamp a `vport_meta` onto a data frame as a single Dataset-JSON string in
#' its `metadata_json` attribute. Every `write_*()` codec reads that string
#' back with [get_meta()] and embeds it verbatim, so the metadata survives
#' the trip to any format. Use it to attach metadata to a bare frame before a
#' write, or to re-stamp after a tidyverse verb has dropped attributes.
#'
#' @param x *The data frame to stamp.* `<data.frame>: required`.
#' @param meta *The metadata to attach.* `<vport_meta>: required`. Usually
#'   from [get_meta()] or built by [apply_spec()].
#'
#' @return *The data frame `x`*, with its `metadata_json` attribute set. Pass
#'   it on to a `write_*()` codec or back through [get_meta()].
#'
#' @examples
#' # ---- Example 1: re-stamp metadata a dplyr verb would drop ----
#' #
#' # Conform a dataset, capture its metadata, then re-attach after an
#' # attribute-dropping transform so the write stays lossless.
#' spec <- vport_spec(cdisc_datasets, cdisc_variables, codelists = cdisc_codelists)
#' adsl <- apply_spec(cdisc_adsl, spec, "ADSL")
#' meta <- get_meta(adsl)
#' trimmed <- head(as.data.frame(adsl), 5)
#' attr(trimmed, "metadata_json") <- NULL
#' set_meta(trimmed, meta)
#'
#' # ---- Example 2: stamp a bare frame straight from a spec ----
#' #
#' # A writer with a raw frame and no apply step can build metadata from the
#' # spec and attach it directly.
#' meta_dm <- vport:::.meta_from_spec(spec, "DM")
#' dm <- set_meta(cdisc_dm, meta_dm)
#' is_vport_meta(get_meta(dm))
#'
#' @seealso [get_meta()] for the read half; [apply_spec()] which stamps it.
#' @export
set_meta <- function(x, meta) {
  call <- rlang::caller_env()
  if (!is.data.frame(x)) {
    cli::cli_abort(
      c(
        "{.arg x} must be a data frame.",
        "x" = "You supplied {.obj_type_friendly {x}}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  if (!is_vport_meta(meta)) {
    cli::cli_abort(
      c(
        "{.arg meta} must be a {.cls vport_meta}.",
        "x" = "You supplied {.obj_type_friendly {meta}}.",
        "i" = "Get one from {.fn get_meta} or {.fn apply_spec}."
      ),
      class = "vport_error_input",
      call = call
    )
  }
  attr(x, "metadata_json") <- .meta_to_datasetjson(meta, extensions = TRUE)
  .project_col_attrs(x, meta)
}

# Project the per-column label and SAS display format from the meta onto the
# matching frame columns, so labelled/gtsummary/viewer tooling reads them like
# haven. The meta stays the SSOT; the attrs are a projection -- set when the
# meta carries a value, strip when it does not, so a meta update never leaves a
# stale attr that .col_meta_from_attrs would later resurrect on a bare-frame
# write. Idempotent: set_meta(set_meta(x, m), m) == set_meta(x, m).
#' @noRd
.project_col_attrs <- function(x, meta) {
  cols <- meta@columns
  for (nm in names(x)) {
    cm <- cols[[nm]]
    # A column the meta does not describe: it has no opinion, leave any
    # user/haven attrs (e.g. a label that is the column's only metadata) alone.
    if (is.null(cm)) {
      next
    }
    lbl <- cm$label
    fmt <- cm$displayFormat
    inf <- cm$informat
    attr(x[[nm]], "label") <- if (!is.null(lbl) && nzchar(lbl)) lbl else NULL
    attr(x[[nm]], "format.sas") <- if (!is.null(fmt) && nzchar(fmt)) {
      fmt
    } else {
      NULL
    }
    attr(x[[nm]], "informat.sas") <- if (!is.null(inf) && nzchar(inf)) {
      inf
    } else {
      NULL
    }
  }
  x
}

# Reduce a meta to a column subset (col_select). Columns are reordered to
# `keep` (the data's file order); keys are recomputed so a dropped key column
# simply leaves the key set. Rebuilt via the constructor (the codebase never
# mutates an S7 meta in place).
#' @noRd
.meta_select_columns <- function(meta, keep) {
  cols <- meta@columns[keep]
  ds <- meta@dataset
  ds$keys <- .meta_keys(cols)
  vport_meta_class(dataset = ds, columns = cols)
}

# Sync a meta's record count to the rows actually read (n_max). `records` is
# always present in decoder-produced meta, so the field is replaced in place.
#' @noRd
.meta_set_records <- function(meta, n) {
  ds <- meta@dataset
  ds$records <- as.integer(n)
  vport_meta_class(dataset = ds, columns = meta@columns)
}

# Record a source-encoding name on a meta's dataset block (the on-disk
# `_vport.sourceEncoding` field). Rebuilt via the constructor (the codebase
# never mutates an S7 meta in place).
#' @noRd
.meta_set_encoding <- function(meta, encoding) {
  ds <- meta@dataset
  ds$encoding <- encoding
  vport_meta_class(dataset = ds, columns = meta@columns)
}
