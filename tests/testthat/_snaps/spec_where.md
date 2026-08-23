# OR across different variables is refused, not silently narrowed

    Code
      artoo:::.wc_parse_text("SEX EQ (F) OR RACE EQ (WHITE)", "WC.5")
    Condition
      Error:
      ! Where clause "WC.5" combines different variables with OR.
      x Define-XML combines the checks in a where clause with AND, so a disjunction across "SEX" and "RACE" cannot be expressed.
      i Split it into separate value-level rows, one per condition.

# an unknown comparator is refused

    Code
      artoo:::.wc_parse_text("SEX LIKE (F)", "WC.6")
    Condition
      Error:
      ! Where clause "WC.6" uses an unknown comparator "LIKE".
      i Define-XML allows "LT", "LE", "GT", "GE", "EQ", "NE", "IN", and "NOTIN".

# free text with too few tokens is refused as unreadable

    Code
      artoo:::.wc_parse_text("SEX", "WC.10")
    Condition
      Error:
      ! Cannot read the where clause "WC.10".
      x "SEX" is not `VARIABLE COMPARATOR value`.
      i Supply a WhereClauses sheet instead, which needs no parsing.

