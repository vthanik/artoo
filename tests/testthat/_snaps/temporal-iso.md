# targetDataType = integer still demands numeric storage and aborts on partials

    Code
      write_xpt(dm, p)
    Condition
      Error in `write_xpt()`:
      ! Cannot write column `BRTHDTC` as a SAS date numeric.
      x It is a character vector; with targetDataType "integer" a date column must be a Date or already a SAS-epoch numeric.
      i Partial ISO 8601 values cannot be SAS numerics. Drop the spec's targetDataType to write them as ISO text, or complete the values.

# apply_spec always aborts on truncating coercion (lossless or abort)

    Code
      apply_spec(frac_frame(), frac_spec(), "ADVS", conformance = "off")
    Condition
      Error:
      ! Coercion to the spec dataTypes would lose data.
      x Integer coercion would truncate fractional values in: HEIGHTBL (2).
      i This gate is separate from `conformance`; `conformance = "off"` does not bypass it.
      i To keep these values in R, set `apply_spec(on_coercion_loss = "keep")`, or retype the spec with `set_type()` (dataType "float" or "decimal").
      i To see every finding at once, run `check_spec(x, spec, dataset)`.

