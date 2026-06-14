# Validation & qualification

The first question a pharma organization asks of any package in a
submission pipeline is “can we qualify this?”. This article lays out the
properties artoo is built around, where each is enforced in code, and
the evidence a qualification file can point to. None of it is a
regulatory claim — qualification is your process — but every claim below
is machine-checkable in your own environment.

## 1. The core guarantee: lossless or loud

artoo’s design rule is that no operation silently damages data. It shows
up in three enforced behaviors:

- **Lossless round-trips.** Every format carries the complete
  CDISC-shaped metadata, so read-write-read returns the same values and
  the same metadata:

``` r

adsl <- apply_spec(cdisc_adsl, adam_spec, "ADSL", conformance = "off")
```

    6 variables the spec declares are absent from the data (not added): `TRTDURD`,
    `DISONDT`, `EOSSTT`, `DCSREAS`, `EOSDISP`, and `MMS1TSBL`.

``` r

p <- tempfile(fileext = ".json")
write_json(adsl, p)
back <- read_json(p)
identical(get_meta(back)@columns, get_meta(adsl)@columns)
```

    [1] TRUE

- **Lossy operations abort.** A coercion that would truncate or overflow
  aborts (`artoo_error_type`) before touching a value; an unencodable
  character aborts (`artoo_error_codec`) unless you opt into a named
  policy. There is no silent-truncation path in the package.
- **Destructive options announce.** Even the explicit
  `apply_spec(extra = "drop")` trim emits a message and leaves the
  `extra_variable` finding as an audit trail.

## 2. Conditions are an evidence surface

Every condition artoo raises carries a three-level class —
`artoo_<severity>_<kind>`, `artoo_<severity>`, `artoo_condition` — and
the data-protection conditions carry their evidence as data
(`cnd$variables`, `cnd$findings`), so a qualification harness can assert
on them programmatically rather than matching message text:

``` r

vars <- spec_variables(adam_spec)
vars$data_type[vars$variable == "AGE"] <- "integer"
strict <- artoo_spec(
  adam_spec@datasets,
  vars,
  codelists = adam_spec@codelists,
  study = spec_study(adam_spec)
)
raw <- cdisc_adsl
raw$AGE[1] <- raw$AGE[1] + 0.5
tryCatch(
  apply_spec(raw, strict, "ADSL", conformance = "off"),
  artoo_error_type = function(cnd) cnd$variables
)
```

      variable data_type n    reason
    1      AGE   integer 1 truncated

## 3. The development gates

The repository enforces, on every change and in CI:

- `R CMD check` at 0 errors / 0 warnings / 0 notes;
- a test suite in the thousands of assertions, including byte-level
  golden files for the codecs, a cross-format round-trip matrix, and
  fuzzed-input tests that assert every failure is a classed artoo
  condition (never a crash);
- line coverage of at least 95% on every file in `R/`;
- reproducible demo data: every bundled object is rebuilt by script from
  public, checksum-pinned sources (the official CDISC Define-XML 2.1
  examples and the PHUSE Test Data Factory), so your qualification can
  re-derive what the tests run against.

## 4. Standards the behavior is pinned to

Where a behavior implements a standard, the source is cited in the docs
rather than re-invented: CDISC Dataset-JSON v1.1 (type vocabulary,
UTF-8), the FDA Study Data Technical Conformance Guide (XPORT
expectations, ASCII gate), SAS XPORT v5/v8 (TS-140/TS-340), RFC 8259,
IANA character set names, and Unicode NFC (UAX \#15).

## Where to next

- [Get started](https://vthanik.github.io/artoo/articles/artoo.md) — the
  round-trip from the top.
- [Any-to-any
  conversion](https://vthanik.github.io/artoo/articles/convert.md) — the
  round trips themselves.
