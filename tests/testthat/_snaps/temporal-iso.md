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
      i Fix the spec: dataType "float" or "decimal" keeps fractions; a wider type avoids overflow.

