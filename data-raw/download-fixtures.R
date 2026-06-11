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

# ---- Define-XML 2.1 example (official CDISC release example) ----------------
# The defineV21-SDTM.xml example from the CDISC Define-XML 2.1.0 release
# package (mirrored on GitHub), used to ground read_spec()'s xml branch.
def_url <- paste0(
  "https://raw.githubusercontent.com/rubentalstra/Trial-Submission-Studio/",
  "master/resources/Define-XML_2.1/examples/DefineXML-2-1-SDTM/",
  "defineV21-SDTM.xml"
)
def_dest <- file.path("tests", "testthat", "fixtures", "define21-sdtm.xml")
def_sha256 <- "24c97a570d1f905435e815ff7e3199b2e17a5e5d6c58b4fabdf1439bf10d5d21"
if (!file.exists(def_dest)) {
  utils::download.file(def_url, def_dest, mode = "wb", quiet = TRUE)
}
def_got <- digest::digest(file = def_dest, algo = "sha256")
if (!identical(def_got, def_sha256)) {
  stop("define21-sdtm.xml checksum mismatch: ", def_got, " != ", def_sha256)
}
message("define21-sdtm.xml OK (", def_sha256, ")")

# ---- Additional SDTM domains (repeated-measures realism) --------------------
# AE (adverse events; multiple records per subject, wider than DM) is
# committed alongside DM. LB (laboratory; ~60k rows) is large, so it is
# download-only (gitignored) and the stress tests skip when it is absent.
sdtm_base <- paste0(
  "https://github.com/cdisc-org/sdtm-adam-pilot-project/raw/master/",
  "updated-pilot-submission-package/900172/m5/datasets/cdiscpilot01/",
  "tabulations/sdtm/"
)
sdtm_fixtures <- list(
  list(
    file = "sas-ae.xpt",
    url = paste0(sdtm_base, "ae.xpt"),
    sha = "05cf23dadadf1b6a11f4474c76724f870de389ba6a4312c825b30e299cb1e4d9"
  ),
  list(
    file = "sas-lb.xpt",
    url = paste0(sdtm_base, "lb.xpt"),
    sha = "47394de7c6484bdf3d5b15c5fe580ca49125707475e6352d30afd5d75c2d7830"
  )
)
for (fx in sdtm_fixtures) {
  d <- file.path("tests", "testthat", "fixtures", fx$file)
  if (!file.exists(d)) {
    utils::download.file(fx$url, d, mode = "wb", quiet = TRUE)
  }
  got <- digest::digest(file = d, algo = "sha256")
  if (!identical(got, fx$sha)) {
    stop(fx$file, " SHA256 mismatch: ", got, " != ", fx$sha)
  }
  message(fx$file, " OK (", file.size(d), " bytes)")
}
