# Derive or translate a variable through its codelist

Map one column's values through a spec codelist — code to decode or
decode to code — writing the result to a new variable or in place. This
is the everyday companion to
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)'s
whole-dataset `decode` step: deriving `RACEN` from `RACE`, recovering
submission codes from decoded values, or decoding a single variable for
display, without re-running the pipeline. When the target variable is
declared in the spec, the result is also coerced to its dataType and
labelled, so the new column lands conformed.

## Usage

``` r
decode_column(
  x,
  spec,
  dataset,
  from,
  to = from,
  direction = c("to_decode", "to_code"),
  no_match = c("error", "keep", "na"),
  trim = TRUE,
  ignore_case = FALSE
)
```

## Arguments

- x:

  *The data frame to extend.* `<data.frame>: required`.

- spec:

  *The specification carrying the codelists.* `<artoo_spec>: required`.

- dataset:

  *The dataset whose variables apply.* `<character(1)>: required`. Must
  name a dataset in `spec`.

- from:

  *The source column.* `<character(1)>: required`. Must be a column of
  `x`.

- to:

  *The destination variable.* `<character(1)>: default `from“. Defaults
  to translating in place. A `to` declared in the spec gets its dataType
  coercion and label; an undeclared \`to\` is plain character.

- direction:

  *Which way to map.* `<character(1)>`. One of:

  - `"to_decode"` (default) map codes to their decoded values (`"M"`
    becomes `"Male"`).

  - `"to_code"` map decoded values to their submission codes — the
    `RACEN`-from-`RACE` derivation.

- no_match:

  *Policy for values absent from the codelist.* `<character(1)>`. One of
  `"error"` (default), `"keep"` (carry the source value through), or
  `"na"`.

- trim:

  *Match after trimming whitespace.* `<logical(1)>: default TRUE`.

- ignore_case:

  *Match case-insensitively.* `<logical(1)>: default FALSE`. Case
  differences are usually genuine CT violations, so this is opt-in.

## Value

*The data frame `x`* with the `to` column added (at the end) or replaced
(in place), ready for the next pipeline step.

## Details

**Which codelist applies.** The codelist attached to `to` in the spec
wins (the natural direction for `RACEN`-style derivations, where the
numeric variable owns the code/decode pairs); when `to` declares none,
`from`'s codelist is used. If neither variable references a codelist the
call aborts — there is nothing to map through.

**Mismatched surfaces chain.** A single call maps through ONE codelist,
so the winning codelist's terms (or decodes) must line up with the
`from` values — the CDISC `*N` convention guarantees this for
`RACEN`-style pairs, whose decodes are the character variable's
submission values. When the two codelists share no value surface (say
`SEXN`'s decodes are `"Female"`/`"Male"` but `SEX` holds `"F"`/`"M"`),
the unmatched values hit the `no_match` policy; translate in two hops
instead — decode through `from`'s codelist first, then `to_code` through
the destination's:

    dm |>
      decode_column(spec, "DM", from = "SEX", to = "SEXDECD") |>
      decode_column(spec, "DM", from = "SEXDECD", to = "SEXN",
                    direction = "to_code")

**Soft matches are reported, never silent.** Values that match only
after trimming whitespace (or case-folding, when `ignore_case = TRUE`)
still map, with a `artoo_warning_codelist` naming the variants —
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md)
always compares exactly, so clean the source for submission.

## See also

**Whole-dataset decode:**
[`apply_spec()`](https://vthanik.github.io/artoo/reference/apply_spec.md)
with `decode =`.

**Inspect the terms:**
[`spec_codelists()`](https://vthanik.github.io/artoo/reference/spec_codelists.md).
**Check membership:**
[`check_spec()`](https://vthanik.github.io/artoo/reference/check_spec.md).

## Examples

``` r
spec <- artoo_spec(cdisc_sdtm_datasets, cdisc_sdtm_variables, codelists = cdisc_codelists)

# ---- Example 1: decode a coded variable into a display column ----
#
# SEX is coded against C66731; map the codes to their decodes in a new
# column, leaving the submission values untouched.
dm <- decode_column(cdisc_dm, spec, "DM", from = "SEX", to = "SEXDECD")
table(dm$SEX, dm$SEXDECD)
#>    
#>     Female Male
#>   F     29    0
#>   M      0   31

# ---- Example 2: the RACEN pattern, a coded numeric from its decode ----
#
# Declare SEXN as an integer variable owning a numeric codelist, then
# derive it from SEX's decoded values: to_code maps each decode to its
# submission code, and the spec dataType makes the result integer.
vars <- rbind(
  cdisc_sdtm_variables,
  data.frame(
    dataset = "DM", variable = "SEXN", label = "Sex (N)",
    data_type = "integer", length = 8L, order = NA_integer_,
    codelist_id = "SEXN"
  )
)
cls <- rbind(
  cdisc_codelists,
  data.frame(
    codelist_id = "SEXN", term = c("1", "2"),
    decode = c("F", "M"), order = 1:2
  )
)
spec_n <- artoo_spec(cdisc_sdtm_datasets, vars, codelists = cls)
dm_n <- decode_column(cdisc_dm, spec_n, "DM",
  from = "SEX", to = "SEXN", direction = "to_code"
)
str(dm_n$SEXN)
#>  int [1:60] 1 2 2 2 1 1 1 2 1 2 ...
#>  - attr(*, "label")= chr "Sex (N)"
```
