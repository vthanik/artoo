# a result with no reason or purpose is refused

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Error:
      ! Analysis result "AR.T1.R1" is missing reason and purpose.
      x `AnalysisReason` and `AnalysisPurpose` are required by the ARM schema.
      i Set them on the `arm_results` row; artoo will not choose them for you.

# a display with no results is refused

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Error:
      ! Analysis display "RD.ORPHAN" has no results.
      x `arm:ResultDisplay` requires at least one `arm:AnalysisResult`.
      i Add rows to `arm_results` naming this display, or drop the display.

# documentation that references a page but says nothing is refused

    Code
      write_spec(spec, path, created = FROZEN_ARM)
    Condition
      Error:
      ! Analysis result "AR.T1.R1" documents a reference but says nothing.
      x `arm:Documentation` requires a Description.
      i Set `documentation`, or clear `documentation_document_id`.

# an unresolvable ItemGroup is kept verbatim, an absent one refused

    Code
      write_spec(none, out, created = FROZEN_ARM)
    Condition
      Error:
      ! Analysis result "AR.T1.R1" names no analysis dataset.
      x `arm:AnalysisDataset/@ItemGroupOID` is required.
      i Set `dataset` on the `arm_results` row.

