# Download the real SAS-written xpt fixture used by test-xpt-fixture.R.
#
# Source: the public CDISC SDTM/ADaM pilot submission package (cdiscpilot01),
# DM domain. It is genuine SAS PROC COPY XPORT output, freely redistributable,
# and lets the suite prove vport reads real SAS bytes -- not just its own.
#
# The file is committed under tests/testthat/fixtures/ so the test needs no
# network. Re-run this only to refresh it; the SHA256 below pins exactly what
# is committed, so an unexpected upstream change is caught here, not silently.

url <- paste0(
  "https://github.com/cdisc-org/sdtm-adam-pilot-project/raw/master/",
  "updated-pilot-submission-package/900172/m5/datasets/cdiscpilot01/",
  "tabulations/sdtm/dm.xpt"
)
sha256 <- "7327baea97fd532d02385248da0c7240402e770099507e2c3a88e2ac706c02a6"
dest <- file.path("tests", "testthat", "fixtures", "sas-dm.xpt")

dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
utils::download.file(url, dest, mode = "wb", quiet = TRUE)

got <- digest::digest(file = dest, algo = "sha256")
if (!identical(got, sha256)) {
  stop(
    "sas-dm.xpt SHA256 mismatch.\n  expected: ",
    sha256,
    "\n  got:      ",
    got,
    "\nUpstream changed; review before updating the pin."
  )
}
message("sas-dm.xpt downloaded and verified (", file.size(dest), " bytes).")
