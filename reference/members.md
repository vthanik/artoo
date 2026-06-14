# List the datasets in a file or directory

Inventory the dataset(s) a path contains, one row per dataset,
dispatched by extension through the same codec registry as
[`read_dataset()`](https://vthanik.github.io/artoo/reference/read_dataset.md).
A SAS XPORT library lists every member; a single-dataset file (`.json`,
`.ndjson`, `.parquet`, `.rds`) reports one row; a directory inventories
each dataset file it holds. The format-neutral companion to the
xpt-specific
[`xpt_members()`](https://vthanik.github.io/artoo/reference/xpt_members.md).

## Usage

``` r
members(path)
```

## Arguments

- path:

  *A dataset file or a directory.* `<character(1)>: required`. A path to
  a dataset file (`.xpt`, `.json`, `.ndjson`, `.parquet`, `.rds`) or to
  a directory holding such files. A path that does not exist, or a file
  whose extension no codec claims, aborts.

## Value

*A `<artoo_members>` data frame*, one row per dataset, with columns
`file` (source basename), `member` (dataset name), `label`, `records`
(row count), `variables` (column count), and `format` (the codec
format). Empty when a directory holds no dataset files. It is an
ordinary data frame underneath.

## Details

**One dataset per file, except XPORT.** XPORT is the only multi-dataset
container artoo handles, so only an `.xpt` path can return more than one
row. Every other format is one dataset per file.

**A directory is inventoried, not descended.** Only the files directly
in the directory are listed (no recursion); files whose extension no
codec claims are skipped, and a directory with no dataset files returns
an empty inventory rather than aborting. A dataset file that fails to
read aborts with its codec's error, naming the file.

**Note:** counting `records` reads the file through its codec (the one
lossless reader), so members() is an honest count, not a header guess;
for a large directory it reads every dataset.

## See also

**Members of one XPORT file:**
[`xpt_members()`](https://vthanik.github.io/artoo/reference/xpt_members.md).

**Per-variable attributes:**
[`columns()`](https://vthanik.github.io/artoo/reference/columns.md) for
one dataset's variable pane.

## Examples

``` r
dm <- apply_spec(cdisc_dm, sdtm_spec, "DM", conformance = "off")
#> 1 variable the spec declares is absent from the data (not added):
#> `BRTHDTC`.

# ---- Example 1: one dataset in a file ----
#
# A single-dataset format reports exactly one member.
p <- tempfile(fileext = ".json")
write_json(dm, p)
members(p)
#> <artoo_members> 1 dataset
#> file                   member  label         records  variables  format
#> file19df7b89437e.json  DM      Demographics  60       25         json

# ---- Example 2: every dataset in a directory ----
#
# Point members() at a folder to inventory each dataset file it holds, one
# row per dataset, dispatched by extension.
dir <- tempfile("datasets")
dir.create(dir)
write_json(dm, file.path(dir, "dm.json"))
write_rds(dm, file.path(dir, "dm.rds"))
members(dir)
#> <artoo_members> 2 datasets
#> file     member  label         records  variables  format
#> dm.json  DM      Demographics  60       25         json
#> dm.rds   DM      Demographics  60       25         rds
```
