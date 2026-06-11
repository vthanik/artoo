#' @keywords internal
#' @importFrom rlang %||%
"_PACKAGE"

# Register S7 classes and methods when the namespace loads. Required so
# S7 generics dispatch on artoo's classes after `library(artoo)` or
# `devtools::load_all()`.
.onLoad <- function(libname, pkgname) {
  S7::methods_register()
  .encoding_onload()
}

# Quiet R CMD check for symbols used via NSE / referenced only in roxygen.
utils::globalVariables(character(0))
