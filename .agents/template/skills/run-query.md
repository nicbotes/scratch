---
name: run-query
description: Execute one specific SQL question against the local DuckDB and report results. Use when the user has a single concrete question, the relevant table is already landed, and the answer fits under the row cap. Do NOT use for open-ended analysis (use analyst-workflow), aggregations on large landed tables (use pre-aggregate), or queries that touch sensitive columns (use pii-safe-analysis).
---

# Skill: run-query

The simplest path: one question, one query, one answer.

## Steps

1. **Confirm the table exists and is profiled this session.** If not, `bash .agents/tools/profile-table.sh <table>` first (rule #8).
2. **Compose SQL.** Use `references/duckdb-sql.md` for DuckDB-specific syntax (JSON access, date handling, percentiles).
3. **Run:**
   ```bash
   bash .agents/tools/duckdb-query.sh "<your sql>"
   ```
4. **Read the result.** If truncation fired, the tool tells you the escape valves (`--to-file`, `--head`, `--no-row-cap`). For >1000 rows, route through `pre-aggregate` or `export-results.sh` — don't `--no-row-cap` silently.
5. **Report.** State the source table and as-of (from earlier `profile-table.sh`). If this is a number a human will act on, walk the publish-time gate (`references/data-trust.md`) and add a confidence label.

## When `run-query` is the wrong skill

| Symptom | Right skill |
|---|---|
| The user wants the patterns / churn / cohorts / retention | `analyst-workflow` |
| The result is a summary but the underlying table is huge | `pre-aggregate` |
| The SQL touches PII / restricted / json_sensitive columns | `pii-safe-analysis` |
| The output is for a downstream consumer (not a chat reply) | `format-output` / `export-results.sh` |
| The user wants a regular KPI definition, not a one-shot | `bi-view` |

→ Next: nothing if the answer is one number for a human. `regression-test` if the answer becomes a recurring published metric.
