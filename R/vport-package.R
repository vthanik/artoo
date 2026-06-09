#' @keywords internal
#' @importFrom rlang %||%
"_PACKAGE"

# Register S7 classes and methods when the namespace loads. Required so
# S7 generics dispatch on vport's classes after `library(vport)` or
# `devtools::load_all()`.
.onLoad <- function(libname, pkgname) {
  S7::methods_register()
}

# Quiet R CMD check for symbols used via NSE / referenced only in roxygen.
utils::globalVariables(character(0))
