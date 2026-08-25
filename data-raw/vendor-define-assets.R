# vendor-define-assets.R — vendor the CDISC Define-XML schema and stylesheet
# trees into inst/extdata/, and the official example documents into
# tests/testthat/fixtures/.
#
# These are frozen artefacts of a published standard: they will never change,
# and they are runtime assets (validate_define() reads the schemas from the
# installed package; the writer copies a stylesheet next to the user's
# define.xml). So they SHIP rather than being downloaded at test time.
#
# Provenance, per tree:
#
#   inst/extdata/2.0.0/cdisc-define-2.0   CDISC Define-XML 2.0 release package
#   inst/extdata/2.0.0/cdisc-odm-1.3.2    ditto
#   inst/extdata/2.0.0/cdisc-xsl          ditto (MIT, (c) Lex Jansen)
#   inst/extdata/2.0.0/cdisc-arm-1.0      ARM v1.0 for Define-XML v2.0, the
#                                         def/v2.0-targeted set (see the
#                                         ARM_20_ROOT comment below).
#   inst/extdata/2.1.0/*                  CDISC Define-XML 2.1.11 release package
#
# Two deliberate exclusions:
#   * define-enumerations.html — documentation, not schema. (The .xsd IS
#     vendored: define-ns.xsd:22 includes it, so the chain needs it.)
#   * Dataset-XML schemas — out of scope.
#
# The two version trees have DIFFERENT internal shapes and must not be merged:
# 2.0 keeps xml/xlink/xmldsig inside cdisc-odm-1.3.2/, 2.1 moves them to a
# sibling core/. Each tree replicates its own source package's layout exactly,
# because every xs:import and xs:redefine is a relative path.
#
# Usage: point the two roots at unpacked CDISC release packages and source
# this file. It is idempotent, and it verifies every byte against the pins
# below, so a re-vendor from a different package version fails loudly.

DEFINE_20_ROOT <- Sys.getenv(
  "ARTOO_DEFINE20_ROOT",
  "~/Downloads/define_xml_2_0_releasepackage20140424"
)
DEFINE_21_ROOT <- Sys.getenv(
  "ARTOO_DEFINE21_ROOT",
  "~/Downloads/DefineV2111_0 (2)"
)
# The def/v2.0-targeted ARM v1.0 schemas. CDISC's Define-XML 2.0 release
# package ships no ARM schemas at all, and the set in the 2.1 package is
# re-pointed to def/v2.1, so this tree must come from a separate CC0-licensed
# redistribution of "Analysis Results Metadata v1.0 for Define-XML v2.0".
# Set ARTOO_ARM20_ROOT to a directory holding arm1-0-0.xsd, arm-extension.xsd
# and arm-ns.xsd; the sha256 pins below confirm you have the right ones.
ARM_20_ROOT <- Sys.getenv("ARTOO_ARM20_ROOT", "")

# ---- sha256 pins: every vendored asset ---------------------------------
.define_asset_sha256 <- c(
  "2.0.0/cdisc-arm-1.0/arm-extension.xsd" =
    "5f86f524999f335eac8207fe044c4a856ee9f5607639cb337136a297ca6e9767",
  "2.0.0/cdisc-arm-1.0/arm-ns.xsd" =
    "bcabcfbf1496d4792a307bbd4432117e935b8efa27254178850382b89c36ee53",
  "2.0.0/cdisc-arm-1.0/arm1-0-0.xsd" =
    "2f7b3b668c463b3d6e1f4bde2bd7067a93bc774c2a458cef688be102b9ff9852",
  "2.0.0/cdisc-define-2.0/define-extension.xsd" =
    "ef027e5fdf9d387d17af8701dd8caa7444733009875c12bfbc7d4799cc41dfb4",
  "2.0.0/cdisc-define-2.0/define-ns.xsd" =
    "1c4b9d89d53953fb78b9117e6de3a0f1007557c245daa0e1b4b571c5ae2f8947",
  "2.0.0/cdisc-define-2.0/define2-0-0.xsd" =
    "d8f48821ca44cc4e8d16f832c90420a5db79da6d37dca6052c6e50ea0ba7f28f",
  "2.0.0/cdisc-odm-1.3.2/ODM1-3-2-foundation.xsd" =
    "c592ebf9eaa9a837cfa04b67c1fd9dd954e22890989dddd93a6a8092f140fce0",
  "2.0.0/cdisc-odm-1.3.2/ODM1-3-2.xsd" =
    "59c7cb42a1165a225492dbd06b2faf5419a9938d6ae8ececa9f2a2fac10d7371",
  "2.0.0/cdisc-odm-1.3.2/xlink.xsd" =
    "e4b134b25c547bc74808bbcc0818febd2f4a58b759556443999365ec4d53d594",
  "2.0.0/cdisc-odm-1.3.2/xml.xsd" =
    "aa62e51de1e420d56f6b4504266f06a26c1e6b2e22ea75c873ef3cce298a81a5",
  "2.0.0/cdisc-odm-1.3.2/xmldsig-core-schema.xsd" =
    "af0dd510289531203736a0426609c4492c1df180d289ef938929778bd03b9132",
  "2.0.0/cdisc-xsl/define2-0-0.xsl" =
    "95544f4352d7de3feb43af96a1266afc940b9c9ffafb632635ad768f38cb434e",
  "2.0.0/cdisc-xsl/define2-0-0.xsl.LICENSE.TXT" =
    "0319124b8c78193670ef34d27abde686ed8f9076c4fa4ce681787e92ef4ed1ae",
  "2.1.0/cdisc-arm-1.0/arm-extension.xsd" =
    "5cc1802dc543d147d8f439a6f466d1567cd6c8a42f6bd1f73dbf8abb435528e7",
  "2.1.0/cdisc-arm-1.0/arm-ns.xsd" =
    "d924781b8c88c8cf47251ac469ed23b4bb8b8611d9d028da5cfad5ac642b31da",
  "2.1.0/cdisc-arm-1.0/arm1-0-0.xsd" =
    "ff0b4d123e3190d1ed454c22d0b7859ccbe3f684f27eabb2b9c781a15ad38b94",
  "2.1.0/cdisc-define-2.1/define-enumerations.xsd" =
    "7c78087e3d11cdd376154db16d5d067c5ce904cc2c194a1eecd3e2c3db0cdcbf",
  "2.1.0/cdisc-define-2.1/define-extension.xsd" =
    "c5f6f2ed8cf9da071da3edbfc20e0ed7f68fcab473cdbbe9ecdd443ecdd18690",
  "2.1.0/cdisc-define-2.1/define-ns.xsd" =
    "398e8accd6a6892353362e6ed89f409c2d593495b178719a5b8130fbdcb1e157",
  "2.1.0/cdisc-define-2.1/define2-1-0.xsd" =
    "6d3145ad22bff9ea91b3711f5e458bcc66b470b2809f6693e439b89dd2174747",
  "2.1.0/cdisc-odm-1.3.2/ODM1-3-2-foundation.xsd" =
    "ccf3776b9754e29c359cd45d820043a1213cf242c7f8a9db4e40858739c704bd",
  "2.1.0/cdisc-odm-1.3.2/ODM1-3-2.xsd" =
    "8410af65a6dcda189755a3a6b443e7621efa870e577c52d18ef94d17a947ddcf",
  "2.1.0/cdisc-xsl/define2-1.xsl" =
    "d288f0ad2dd4d536b6258932027013936f0e047dc586cce840aef9c0d7ced23d",
  "2.1.0/cdisc-xsl/define2-1.xsl.LICENSE.TXT" =
    "115a938fc8d184e257f3d0988cc42b4a9c9aa9b58987b7858ac1a280963d7d70",
  "2.1.0/core/xlink.xsd" =
    "e7fe2c998eaaece13ef63271a58e347a0db2534f80b6ed02723b233668570832",
  "2.1.0/core/xml.xsd" =
    "aa62e51de1e420d56f6b4504266f06a26c1e6b2e22ea75c873ef3cce298a81a5",
  "2.1.0/core/xmldsig-core-schema.xsd" =
    "af0dd510289531203736a0426609c4492c1df180d289ef938929778bd03b9132"
)

# ---- sha256 pins: the four official example documents ------------------
.define_fixture_sha256 <- c(
  "define20-sdtm.xml" =
    "467d4a934792fb5b0dce4469d3230c63e933d70b3e78799c1a13b82b30793371",
  "define20-adam.xml" =
    "04f69cfd7a0526ea9d1e4b1b31829028874b4fc89e9587babeef5625387d6f96",
  "define21-sdtm.xml" =
    "24c97a570d1f905435e815ff7e3199b2e17a5e5d6c58b4fabdf1439bf10d5d21",
  "define21-adam.xml" =
    "36c347fc480546cc545bfec9879bc401ab68e1e6f391b1aa531d9fcbf5481dc6"
)

.verify <- function(paths, pins, what) {
  bad <- character(0)
  for (nm in names(pins)) {
    p <- file.path(paths, nm)
    if (!file.exists(p)) {
      bad <- c(bad, sprintf("%s: MISSING", nm))
      next
    }
    got <- digest::digest(p, algo = "sha256", file = TRUE)
    if (!identical(got, unname(pins[[nm]]))) {
      bad <- c(bad, sprintf("%s:\n  expected %s\n  got      %s", nm, pins[[nm]], got))
    }
  }
  if (length(bad)) {
    stop(sprintf("%s sha256 mismatch:\n%s", what, paste(bad, collapse = "\n")), call. = FALSE)
  }
  message(sprintf("%s: %d file%s verified", what, length(pins), if (length(pins) == 1) "" else "s"))
}

.copy_tree <- function(from, to, pattern = "[.]xsd$") {
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  fs <- list.files(from, pattern = pattern, full.names = TRUE)
  stopifnot(length(fs) > 0)
  file.copy(fs, to, overwrite = TRUE)
}

vendor_define_assets <- function() {
  d20 <- path.expand(DEFINE_20_ROOT)
  d21 <- path.expand(DEFINE_21_ROOT)
  arm <- path.expand(ARM_20_ROOT)
  if (!nzchar(ARM_20_ROOT)) {
    stop(
      "Set ARTOO_ARM20_ROOT to a directory holding the def/v2.0-targeted ",
      "ARM v1.0 schemas (arm1-0-0.xsd, arm-extension.xsd, arm-ns.xsd). ",
      "See the comment above ARM_20_ROOT for why they are not in the CDISC ",
      "Define-XML 2.0 release package.",
      call. = FALSE
    )
  }

  # ---- 2.0.0 ----
  .copy_tree(file.path(d20, "schema/cdisc-define-2.0"), "inst/extdata/2.0.0/cdisc-define-2.0")
  .copy_tree(file.path(d20, "schema/cdisc-odm-1.3.2"),  "inst/extdata/2.0.0/cdisc-odm-1.3.2")
  .copy_tree(arm,                                       "inst/extdata/2.0.0/cdisc-arm-1.0")
  dir.create("inst/extdata/2.0.0/cdisc-xsl", recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(d20, "stylesheets/define2-0-0.xsl"),
            "inst/extdata/2.0.0/cdisc-xsl", overwrite = TRUE)
  file.copy(file.path(d20, "define2-0-0.xsl.LICENSE.TXT"),
            "inst/extdata/2.0.0/cdisc-xsl", overwrite = TRUE)

  # ---- 2.1.0 ----
  .copy_tree(file.path(d21, "schema/cdisc-define-2.1"), "inst/extdata/2.1.0/cdisc-define-2.1")
  .copy_tree(file.path(d21, "schema/cdisc-odm-1.3.2"),  "inst/extdata/2.1.0/cdisc-odm-1.3.2")
  .copy_tree(file.path(d21, "schema/core"),             "inst/extdata/2.1.0/core")
  .copy_tree(file.path(d21, "schema/cdisc-arm-1.0"),    "inst/extdata/2.1.0/cdisc-arm-1.0")
  dir.create("inst/extdata/2.1.0/cdisc-xsl", recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(d21, "stylesheets/define2-1.xsl"),
            "inst/extdata/2.1.0/cdisc-xsl", overwrite = TRUE)
  file.copy(file.path(d21, "stylesheets/define2-1.xsl.LICENSE.TXT"),
            "inst/extdata/2.1.0/cdisc-xsl", overwrite = TRUE)

  # ---- the four official example documents ----
  fx <- "tests/testthat/fixtures"
  file.copy(file.path(d20, "sdtm/define2-0-0-example-sdtm.xml"),
            file.path(fx, "define20-sdtm.xml"), overwrite = TRUE)
  file.copy(file.path(d20, "adam/define2-0-0-example-adam.xml"),
            file.path(fx, "define20-adam.xml"), overwrite = TRUE)
  file.copy(file.path(d21, "examples/Define-XML-2-1-ADaM/adam/defineV21-ADaM.xml"),
            file.path(fx, "define21-adam.xml"), overwrite = TRUE)
  # define21-sdtm.xml predates this script; see data-raw/download-fixtures.R.

  .verify("inst/extdata", .define_asset_sha256, "Vendored assets")
  .verify(fx, .define_fixture_sha256, "Example documents")
  .write_manifest()
  invisible(TRUE)
}

# The shipped manifest is what tests verify against, so a corrupted or
# line-ending-normalised asset fails in CI. It is generated here rather than
# hand-written; the pins above are the authoritative copy and catch a
# re-vendor from the wrong release package.
.write_manifest <- function() {
  fs <- sort(list.files("inst/extdata", pattern = "[.](xsd|xsl|TXT)$",
                        recursive = TRUE))
  lines <- vapply(fs, function(f) {
    paste(digest::digest(file.path("inst/extdata", f), algo = "sha256",
                         file = TRUE), f)
  }, character(1))
  writeLines(
    c("# sha256 of every vendored CDISC asset. Generated by",
      "# data-raw/vendor-define-assets.R -- do not hand-edit.",
      unname(lines)),
    "inst/extdata/MANIFEST.sha256"
  )
  message(sprintf("Manifest: %d entries written", length(fs)))
}

if (identical(environment(), globalenv())) {
  vendor_define_assets()
}
