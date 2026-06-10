# Shared across the xpt oracle tests: locate a python3 that can import
# pyreadstat, or "" when none is available. Lives in a helper so every test
# file (the round-trip oracle and the real-SAS fixture) reuses one definition.
py_with_pyreadstat <- function() {
  py <- Sys.which("python3")
  if (py == "") {
    return("")
  }
  ok <- tryCatch(
    system2(
      py,
      c("-c", shQuote("import pyreadstat")),
      stdout = FALSE,
      stderr = FALSE
    ) ==
      0,
    error = function(e) FALSE
  )
  if (isTRUE(ok)) py else ""
}
