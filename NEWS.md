# vport 0.0.0.9000

* `apply_spec()` gained a `na_position` argument controlling where missing
  key values sort: `"first"` (the default, matching SAS `PROC SORT` and the
  FDA submission convention) or `"last"` (matching R, pandas, and Polars).
* `read_xpt()` and `write_xpt()` read and write SAS XPORT (xpt) v5 and v8
  files losslessly through the `vport_meta` spine, with byte-stable output, a
  full IBM-370 float and SAS-epoch temporal round-trip, special-missing
  (`.A`-`.Z`, `._`) fidelity, and encoding round-trip for any single-byte
  charset.
