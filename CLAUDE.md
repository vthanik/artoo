# CLAUDE.md — vport

**vport** ("versatile port") — a lightweight, lossless, CDISC-native
clinical-dataset reader/writer (SAS XPORT, CDISC Dataset-JSON v1.1,
Apache Parquet, RDS). One canonical metadata model; any-to-any lossless
conversion. Replaces `haven` for clinical work. (Repo dir is still
`herald/`; package is `vport`.)

Global directives load from `~/.claude/CLAUDE.md`. This file holds
project-specific shared conventions. Deeper working detail and the
decisions log are in `CLAUDE.local.md` (gitignored). The approved
design is the plan referenced there.

## Engineering principle (non-negotiable)

**Strictly don't be lazy.** Find the **root cause over a patch**, the
**best long-term solution over the lazy shortcut**. If a fix feels like
a workaround, stop and solve the real problem — even when it is more
work. Reproducibility, correctness, and the right abstraction beat
speed. No copying from non-shippable sources, no silent truncation, no
"good enough for now" that a future session has to unwind.

## Project state

Phase 1 (spec core) in progress: `vport_spec` / `vport_meta` S7 classes,
CDISC type vocabulary, spec validation, accessors. See `CLAUDE.local.md`
for the phase checklist.

## Conventions

- snake_case; package prefix on exports; dot-prefix internals.
- Lightweight, base R + targeted deps; no tidyverse in `Imports`.
  `nanoparquet` (Parquet) allowed; `arrow` and `haven` banned.
- Errors via `cli::cli_abort(class = "vport_error_<kind>")`; ASCII-only
  in message strings.
- Test-first for new exports; ≥ 95% coverage per file; roxygen2
  examples must run on bundled CDISC demo data (no toy frames).
- Roxygen follows the tabular bar (see `CLAUDE.local.md` roxygen
  standard).
- `air` formats after edits. Inner loop: document → test → check → air.
- **Demo data is built reproducibly from public sources**
  (`pharmaverseadam` / `pharmaversesdtm`) in `data-raw/`, never copied
  from a private archive — end users and CI must be able to rebuild it.

See `build.md` for the dev loop. See `debugging.md` for troubleshooting.
