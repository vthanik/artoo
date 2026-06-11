# aaa_codec_registry.R -- the codec registry, loaded early (aaa_ prefix).
#
# Each format is a codec: a record with an `encode`/`decode` pair (written
# against the S7 artoo_meta), the file extensions it claims, and a read/write
# mode. Every codec_<fmt>.R self-registers at its file bottom. The registry
# stays internal for v1 (clinical formats are a closed set; an open plugin
# API would invite codecs that break the lossless contract), but the record
# shape is designed so a future public register_codec() is a rename.

.artoo_codecs <- new.env(parent = emptyenv())

# Register a codec. `encode` and `decode` are the NAMES of the two contract
# functions -- `encode(x, meta, path, <codec args>, call) -> invisible(path)`
# and `decode(path, <codec args>, call) -> list(data, meta)`. Codecs take NO
# `...`: the dispatchers forward user arguments plus `call =` verbatim, so an
# argument a codec does not declare is a loud "unused argument" error, and
# `call` lands as the trailing formal. Resolved with match.fun() at
# dispatch time (storing the names, not the closures, keeps covr's
# instrumented bindings live and lets a codec be redefined). `extensions`
# are lowercase, dot-free; `mode` is "rw" or "r". `engine` names an optional
# Suggests package the codec needs (e.g. "nanoparquet"); NULL means the codec
# is pure-R and always available. artoo_formats() consults it.
#' @noRd
.register_codec <- function(
  format,
  encode,
  decode,
  extensions,
  mode = "rw",
  engine = NULL
) {
  .artoo_codecs[[format]] <- list(
    format = format,
    encode = encode,
    decode = decode,
    extensions = tolower(extensions),
    mode = mode,
    engine = engine
  )
  invisible(NULL)
}

# Whether a codec's optional engine package is installed (TRUE for pure-R
# codecs, which carry no engine).
#' @noRd
.codec_available <- function(codec) {
  is.null(codec$engine) || requireNamespace(codec$engine, quietly = TRUE)
}

# All registered format names, sorted.
#' @noRd
.registered_formats <- function() {
  sort(ls(.artoo_codecs))
}

# Resolve a stored codec function name to its live binding in the artoo
# namespace, independent of who calls the dispatcher (match.fun would search
# the caller's frame, which fails when a user calls write_dataset() directly).
# Namespace resolution also keeps covr's instrumented binding in play.
#' @noRd
.codec_fn <- function(name) {
  get(name, envir = topenv(environment()), inherits = TRUE, mode = "function")
}

# Resolve a format name to its codec record, or abort.
#' @noRd
.resolve_codec <- function(format, call = rlang::caller_env()) {
  if (
    !is.character(format) ||
      length(format) != 1L ||
      is.na(format) ||
      !exists(format, envir = .artoo_codecs, inherits = FALSE)
  ) {
    known <- .registered_formats()
    .artoo_abort(
      c(
        "Unknown format {.val {format}}.",
        "i" = "Registered formats: {.val {known}}."
      ),
      kind = "codec",
      call = call
    )
  }
  .artoo_codecs[[format]]
}

# Resolve a file extension (no dot, any case) to its codec record, or abort.
#' @noRd
.codec_for_ext <- function(ext, call = rlang::caller_env()) {
  ext <- tolower(ext)
  for (fmt in .registered_formats()) {
    codec <- .artoo_codecs[[fmt]]
    if (ext %in% codec$extensions) {
      return(codec)
    }
  }
  exts <- unlist(lapply(.registered_formats(), function(f) {
    .artoo_codecs[[f]]$extensions
  }))
  .artoo_abort(
    c(
      "No codec handles the {.val {ext}} extension.",
      "i" = "Known extensions: {.val {sort(unique(exts))}}."
    ),
    kind = "codec",
    call = call
  )
}
