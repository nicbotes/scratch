---
name: run-query
description: Execute one specific SQL question against the active org's Athena workgroup. Use when the schema is known, the question is well-defined, and the answer is a single result set. Do NOT use when the query is wide / multi-join (run premortem first), when you haven't seen the table shape (run explore-schema first), or when the question is open-ended exploratory analysis (use analyst-workflow).
---

# Skill: run-query

Workhorse. Most other skills compose this one.

## Steps

1. Confirm the rules apply to your SQL:
   - `WHERE environment = '$ROOT_ENV'` present.
   - Money columns left as cents (divide only when displaying).
   - Dates wrapped in `from_iso8601_timestamp(...)`.
   - `LIMIT 1000` for exploratory queries; remove only for aggregates or compliance.
2. Run:
   ```bash
   bash .agents/tools/athena-query.sh "<sql>"
   ```
   Or pipe SQL on stdin:
   ```bash
   cat my-query.sql | bash .agents/tools/athena-query.sh
   ```
3. On `FAILED`:
   - `COLUMN_NOT_FOUND` → `explore-schema` to confirm column name.
   - `SYNTAX_ERROR` → re-read the SQL with `references/athena-sql.md` (Presto, not standard SQL).
   - `ACCESS_DENIED` → wrong workgroup — re-check `ROOT_ORG_ID` matches the org the keys grant.
   - Timeouts on wide scans → call `premortem` and narrow.
4. If the result is a number a human will act on, run `regression-check.sh --all` before publishing it (rules.md #14).

## Reference

`athena-query.sh` flags:
- `--dry-run` — call `EXPLAIN` and get `DataScannedInBytes` without executing. Used by `premortem`.
- `--format csv|json|jsonl|tsv` — emit a programmatic format.
- **`--to-file <path>`** — write the full result to a file; stdout only echoes the path and row count. Use for anything beyond a few thousand rows.
- **`--head N`** — header + first N data rows.
- **`--no-row-cap`** — explicit override of the stdout cap. Pair with a sentence in your reply explaining why the full output had to land in context. The default cap is `ROOT_AGENTS_MAX_ROWS` (1000); above it, output truncates with a loud footer naming these escape valves.

If you find yourself reaching for `--no-row-cap`, that's the framework telling you the output should be **formatted-and-delivered**, not pasted in chat. Route via `format-output` instead. See rules.md #23 and `references/output-formats.md`.

→ Next (if recurring): `bi-view` (analytical layer) or `ops-dataset` (action queue). Next (if leaving chat): `format-output`.
