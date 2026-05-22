---
name: explore-schema
description: Discover what tables and columns are landed in main.duckdb — SHOW TABLES / DESCRIBE workflow. Use when starting analysis on an unfamiliar dataset, after a re-fetch may have changed shape, or when an unexpected column name surfaces. Do NOT use for orientation about the framework itself (read AGENTS.md) or for API schema (read references/sources/<name>.md).
---

# Skill: explore-schema

The framework's local schema is whatever's been landed. DuckDB infers types from JSONL; `duckdb-describe.sh` tells you what it ended up with.

## Steps

1. **List tables, grouped by tier:**
   ```bash
   bash .agents/tools/duckdb-describe.sh
   ```
   Output is grouped: `raw_*` (landed), `bi_*` (analytical), `ops_*` (action), `scratch_*` (exploratory), `other`.
2. **Inspect columns of a specific table:**
   ```bash
   bash .agents/tools/duckdb-describe.sh raw_github_pulls
   ```
   Shows column name, type, nullable. Pay attention to `STRUCT(...)` and `LIST(...)` types — those need `dot-notation` and `unnest()` respectively (see `references/duckdb-sql.md`).
3. **For STRUCT/LIST columns, peek at one row** to see actual key names:
   ```bash
   bash .agents/tools/duckdb-query.sh "SELECT user FROM raw_github_pulls LIMIT 1" --format json
   ```
   The PII firewall fires here if any tagged column is in the result — that's the signal that this column needs `pii-safe-analysis`.
4. **Note discoveries.** If you find a column you'll re-use across queries, jot a quick note in `references/sources/<name>.md` under "Known columns". Surprises (new fields, renames) deserve a `feedback-note.sh --kind success-pattern` so retro promotes the finding.

→ Next: `run-query` for a specific question, `analyst-workflow` for open-ended, `bi-view` for a recurring KPI.
