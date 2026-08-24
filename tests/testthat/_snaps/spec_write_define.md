# a dataset with neither structure nor keys is refused

    Code
      write_spec(spec, path, created = FROZEN)
    Condition
      Error:
      ! Dataset "DM" has no structure.
      x Define-XML requires `def:Structure` on every ItemGroupDef.
      i Set `structure` on the datasets table, or give the dataset keys.

# a value-level row qualifying an absent variable is refused

    Code
      write_spec(spec, path, created = FROZEN)
    Condition
      Error:
      ! 1 value-level row qualifies a variable the spec does not carry.
      x "VS.VSORRES".
      i A def:ValueListDef hangs off its parent ItemDef, so the variable must be in the spec.

# Define-XML 2.0 output is refused, for now, by name

    Code
      write_spec(small_spec(), path, version = "2.0", created = FROZEN)
    Condition
      Error:
      ! artoo cannot write Define-XML 2.0 yet.
      x This release writes Define-XML 2.1.
      i Pass `version = "2.1"` to write the spec as 2.1.

# an invalid document never replaces the target file

    Code
      write_spec(small_spec(), path, created = FROZEN)
    Condition
      Error:
      ! The Define-XML artoo built is not schema-valid, so '<tmp>/define.xml' was not written.
      x 1 schema error, first: "Element 'ItemDef': something is wrong.".
      i This is an artoo defect; the spec that produced it is worth attaching to a report.

