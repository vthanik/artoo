# a result with no reason or purpose is refused

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Warning:
      The `def:Standards` block was not written.
      x The spec names "ADaMIG 1.1" but carries no `standards` table.
      i Define-XML 2.1 needs a name, version, type and status for each standard.
      Error:
      ! Analysis result "AR.T1.R1" is missing reason and purpose.
      x `AnalysisReason` and `AnalysisPurpose` are required by the ARM schema.
      i Set them on the `arm_results` row; artoo will not choose them for you.

# a display with no results is refused

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Warning:
      The `def:Standards` block was not written.
      x The spec names "ADaMIG 1.1" but carries no `standards` table.
      i Define-XML 2.1 needs a name, version, type and status for each standard.
      Error:
      ! Analysis display "RD.ORPHAN" has no results.
      x `arm:ResultDisplay` requires at least one `arm:AnalysisResult`.
      i Add rows to `arm_results` naming this display, or drop the display.

# documentation that references a page but says nothing is refused

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Warning:
      The `def:Standards` block was not written.
      x The spec names "ADaMIG 1.1" but carries no `standards` table.
      i Define-XML 2.1 needs a name, version, type and status for each standard.
      Error:
      ! Analysis result "AR.T1.R1" documents a reference but says nothing.
      x `arm:Documentation` requires a Description.
      i Set `documentation`, or clear `documentation_document_id`.

# an unresolvable ItemGroup is kept verbatim, an absent one refused

    Code
      write_spec(none, out, created = FROZEN_ARM)
    Condition
      Warning:
      The `def:Standards` block was not written.
      x The spec names "ADaMIG 1.1" but carries no `standards` table.
      i Define-XML 2.1 needs a name, version, type and status for each standard.
      Error:
      ! Analysis result "AR.T1.R1" names no analysis dataset.
      x `arm:AnalysisDataset/@ItemGroupOID` is required.
      i Set `dataset` on the `arm_results` row.

# a result naming no display is refused, not dropped (#p6-review-1)

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Warning:
      The `def:Standards` block was not written.
      x The spec names "ADaMIG 1.1" but carries no `standards` table.
      i Define-XML 2.1 needs a name, version, type and status for each standard.
      Error:
      ! 1 analysis result name a display the spec does not define.
      x "RD.TYPO".
      i Add them to `arm_displays`, or correct `display_id`.

# a result that describes itself two ways is refused (#p6-review-3)

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Warning:
      The `def:Standards` block was not written.
      x The spec names "ADaMIG 1.1" but carries no `standards` table.
      i Define-XML 2.1 needs a name, version, type and status for each standard.
      Error:
      ! Analysis result "AR.T1.R1" describes itself two ways.
      x Its rows disagree on "reason".
      i Those columns describe the result, so they repeat on each of its dataset rows and must agree.

# one result under two displays is refused (#p6-review-7)

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Warning:
      The `def:Standards` block was not written.
      x The spec names "ADaMIG 1.1" but carries no `standards` table.
      i Define-XML 2.1 needs a name, version, type and status for each standard.
      Error:
      ! 1 analysis result under more than one display.
      x "AR.SHARED".
      i An `arm:AnalysisResult` OID must be unique in the document; give each display its own result ids.

