# decode_column.R — create or translate one variable through a spec
# codelist. The single-column companion to apply_spec()'s decode step: the
# same mapper (.map_codelist_values), the same policies, but aimed at the
# everyday ADaM task of deriving a coded variable from its decode (RACEN
# from RACE) or vice versa — the metatools::create_var_from_codelist()
# shape, driven by the artoo_spec instead of a metacore object.

#' Derive or translate a variable through its codelist
#'
#' Map one column's values through a spec codelist — code to decode or
#' decode to code — writing the result to a new variable or in place. This
#' is the everyday companion to [apply_spec()]'s whole-dataset `decode`
#' step: deriving `RACEN` from `RACE`, recovering submission codes from
#' decoded values, or decoding a single variable for display, without
#' re-running the pipeline. When the target variable is declared in the
#' spec, the result is also coerced to its dataType and labelled, so the
#' new column lands conformed.
#'
#' @details
#' **Which codelist applies.** The codelist attached to `to` in the spec
#' wins (the natural direction for `RACEN`-style derivations, where the
#' numeric variable owns the code/decode pairs); when `to` declares none,
#' `from`'s codelist is used. If neither variable references a codelist
#' the call aborts — there is nothing to map through.
#'
#' **Mismatched surfaces chain.** A single call maps through ONE codelist,
#' so the winning codelist's terms (or decodes) must line up with the
#' `from` values — the CDISC `*N` convention guarantees this for
#' `RACEN`-style pairs, whose decodes are the character variable's
#' submission values. When the two codelists share no value surface (say
#' `SEXN`'s decodes are `"Female"`/`"Male"` but `SEX` holds `"F"`/`"M"`),
#' the unmatched values hit the `no_match` policy; translate in two hops
#' instead — decode through `from`'s codelist first, then `to_code`
#' through the destination's:
#'
#' ```r
#' dm |>
#'   decode_column(spec, "DM", from = "SEX", to = "SEXDECD") |>
#'   decode_column(spec, "DM", from = "SEXDECD", to = "SEXN",
#'                 direction = "to_code")
#' ```
#'
#' **Soft matches are reported, never silent.** Values that match only
#' after trimming whitespace (or case-folding, when `ignore_case = TRUE`)
#' still map, with a `artoo_warning_codelist` naming the variants —
#' [check_spec()] always compares exactly, so clean the source for
#' submission.
#'
#' @param x *The data frame to extend.* `<data.frame>: required`.
#' @param spec *The specification carrying the codelists.* `<artoo_spec>:
#'   required`.
#' @param dataset *The dataset whose variables apply.* `<character(1)>:
#'   required`. Must name a dataset in `spec`.
#' @param from *The source column.* `<character(1)>: required`. Must be a
#'   column of `x`.
#' @param to *The destination variable.* `<character(1)>: default `from``.
#'   Defaults to translating in place. A `to` declared in the spec gets its
#'   dataType coercion and label; an undeclared `to` is plain character.
#' @param direction *Which way to map.* `<character(1)>`. One of:
#'   * `"to_decode"` (default) map codes to their decoded values
#'     (`"M"` becomes `"Male"`).
#'   * `"to_code"` map decoded values to their submission codes — the
#'     `RACEN`-from-`RACE` derivation.
#' @param no_match *Policy for values absent from the codelist.*
#'   `<character(1)>`. One of `"error"` (default), `"keep"` (carry the
#'   source value through), or `"na"`.
#' @param trim *Match after trimming whitespace.* `<logical(1)>: default
#'   TRUE`.
#' @param ignore_case *Match case-insensitively.* `<logical(1)>: default
#'   FALSE`. Case differences are usually genuine CT violations, so this is
#'   opt-in.
#'
#' @return *The data frame `x`* with the `to` column added (at the end) or
#'   replaced (in place), ready for the next pipeline step.
#'
#' @examples
#' spec <- artoo_spec(cdisc_sdtm_datasets, cdisc_sdtm_variables, codelists = cdisc_codelists)
#'
#' # ---- Example 1: decode a coded variable into a display column ----
#' #
#' # SEX is coded against C66731; map the codes to their decodes in a new
#' # column, leaving the submission values untouched.
#' dm <- decode_column(cdisc_dm, spec, "DM", from = "SEX", to = "SEXDECD")
#' table(dm$SEX, dm$SEXDECD)
#'
#' # ---- Example 2: the RACEN pattern, a coded numeric from its decode ----
#' #
#' # Declare SEXN as an integer variable owning a numeric codelist, then
#' # derive it from SEX's decoded values: to_code maps each decode to its
#' # submission code, and the spec dataType makes the result integer.
#' vars <- rbind(
#'   cdisc_sdtm_variables,
#'   data.frame(
#'     dataset = "DM", variable = "SEXN", label = "Sex (N)",
#'     data_type = "integer", length = 8L, order = NA_integer_,
#'     codelist_id = "SEXN"
#'   )
#' )
#' cls <- rbind(
#'   cdisc_codelists,
#'   data.frame(
#'     codelist_id = "SEXN", term = c("1", "2"),
#'     decode = c("F", "M"), order = 1:2
#'   )
#' )
#' spec_n <- artoo_spec(cdisc_sdtm_datasets, vars, codelists = cls)
#' dm_n <- decode_column(cdisc_dm, spec_n, "DM",
#'   from = "SEX", to = "SEXN", direction = "to_code"
#' )
#' str(dm_n$SEXN)
#'
#' @seealso
#' **Whole-dataset decode:** [apply_spec()] with `decode =`.
#'
#' **Inspect the terms:** [spec_codelists()]. **Check membership:**
#' [check_spec()].
#' @export
decode_column <- function(
  x,
  spec,
  dataset,
  from,
  to = from,
  direction = c("to_decode", "to_code"),
  no_match = c("error", "keep", "na"),
  trim = TRUE,
  ignore_case = FALSE
) {
  call <- rlang::caller_env()
  direction <- match.arg(direction)
  no_match <- match.arg(no_match)
  if (!is.data.frame(x)) {
    .artoo_abort(
      c(
        "{.arg x} must be a data frame.",
        "x" = "You supplied {.obj_type_friendly {x}}."
      ),
      kind = "input",
      call = call
    )
  }
  .check_spec_arg(spec, call = call)
  .check_dataset_arg(spec, dataset, call = call)
  for (arg in c("from", "to")) {
    val <- get(arg)
    if (!is.character(val) || length(val) != 1L || is.na(val) || !nzchar(val)) {
      .artoo_abort(
        c(
          "{.arg {arg}} must be a single variable name.",
          "x" = "You supplied {.obj_type_friendly {val}}."
        ),
        kind = "input",
        call = call
      )
    }
  }
  if (!(from %in% names(x))) {
    .artoo_abort(
      c(
        "{.arg from} must be a column of {.arg x}.",
        "x" = "{.val {from}} is not present.",
        "i" = "Columns: {.val {names(x)}}."
      ),
      kind = "input",
      call = call
    )
  }

  vars <- spec_variables(spec, dataset)
  cl_of <- function(v) {
    row <- vars[!is.na(vars$variable) & vars$variable == v, , drop = FALSE]
    if (!nrow(row) || is.na(row$codelist_id[1L])) NULL else row$codelist_id[1L]
  }
  clid <- cl_of(to) %||% cl_of(from)
  if (is.null(clid)) {
    .artoo_abort(
      c(
        "Neither {.val {to}} nor {.val {from}} references a codelist in dataset {.val {dataset}}.",
        "i" = "Add a {.field codelist_id} to one of them in the spec."
      ),
      kind = "codelist",
      call = call
    )
  }
  cl <- spec_codelists(spec, clid)

  out <- .map_codelist_values(
    x[[from]],
    cl,
    direction = direction,
    no_match = no_match,
    trim = trim,
    ignore_case = ignore_case,
    var = from,
    clid = clid,
    call = call
  )

  # A spec-declared destination lands conformed: its dataType coercion and
  # its label, so the new column needs no second pass.
  to_row <- vars[!is.na(vars$variable) & vars$variable == to, , drop = FALSE]
  if (nrow(to_row)) {
    dt <- to_row$data_type[1L]
    if (!is.na(dt)) {
      res <- .coerce_to_type(out, dt)
      if (res$n_na_introduced > 0L) {
        .artoo_warn(
          c(
            "Coercing {.var {to}} to dataType {.val {dt}} introduced {res$n_na_introduced} NA value{?s}.",
            "i" = "Check the codelist terms against the spec dataType."
          ),
          kind = "coercion",
          call = call
        )
      }
      out <- res$value
    }
    if ("label" %in% names(to_row) && !is.na(to_row$label[1L])) {
      attr(out, "label") <- to_row$label[1L]
    }
  }

  x[[to]] <- out
  x
}
