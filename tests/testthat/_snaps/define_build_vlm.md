# two rows sharing an ItemDef OID must agree

    Code
      write_spec(spec, path, created = "2020-01-01 00:00:00")
    Condition
      Error:
      ! 1 ItemDef OID is defined more than one way.
      x "IT.SHARED".
      i Define-XML allows one ItemDef per OID; give the rows distinct `itemoid` values, or make their definitions agree.

# a where clause that names no resolvable variable is refused

    Code
      write_spec(spec, path, created = "2020-01-01 00:00:00")
    Condition
      Error:
      ! Where clause "WC.1" names no variable.
      x `RangeCheck/@def:ItemOID` is required, and the clause carries neither `itemoid` nor a dataset and variable that resolve to one.
      i Set `dataset` and `variable` on the where-clause rows.

# a where clause the spec does not define is refused, never dropped

    Code
      write_spec(spec, path, created = "2020-01-01 00:00:00")
    Condition
      Error:
      ! Value-level row 1 ("VS"."VSORRES") names a where clause the spec does not define.
      x "VSTESTCD EQ (WEIGHT)".
      i Add it to the `where_clauses` table, or clear the row's where clause.

# a def:ValueListRef naming no value list is refused (#p4-review-2)

    Code
      write_spec(spec, path, created = "2020-01-01 00:00:00")
    Condition
      Error:
      ! 1 variable points at a value list the spec does not define.
      x "DM.SEX".
      i Add value-level rows, or clear `value_list_id`.

