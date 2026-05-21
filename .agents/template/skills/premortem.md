---
name: premortem
description: Gating skill — before any expensive or wide query, state intent and likely failure modes, then estimate row count. Use when the query has no date filter, joins three or more tables, writes a view, exports evidence, or when the user described an analysis but didn't write SQL. Do NOT use for LIMIT 10 exploration or whoami-style lookups.
---

# Skill: premortem

A two-minute gate that prevents 80% of the silent failures (wrong scope, partial fetch, cents/units, PII leak, return-size blowup). Output the block below into the working context before running.

## Steps

1. **State the intent in one sentence.** "I am about to count merged PRs for Q1 2025 broken down by author." If you can't, stop and clarify with the user.
2. **List the 3 most likely failure modes** for this specific query, picking from:
   - **F1 wrong scope/filter** — forgot `WHERE merged_at IS NOT NULL`, or wrong state, or `draft = true` rows included
   - **F2 stale snapshot** — last `max(updated_at)` older than the source's cadence
   - **F3 unit mix-up** — durations in seconds vs hours, counts vs rates, currency in cents vs unit
   - **F4 timezone** — `strptime` returns UTC; cohort window missing `AT TIME ZONE`
   - **F6 logic / wrong-thing-counted** — many-to-many join, null-handling bug, off-by-one cohort
   - **F8 partial fetch** — contributing table stamped `partial=true` (profile-table.sh will surface)
   - **PII leak** — selecting `*` on a table with `pii_columns.json` entries
   - **Return-size blowup** — `SELECT *` that returns millions of rows; will hit the stdout cap (rules.md #20) and should be routed via `--to-file` or pre-aggregated
3. **Estimate return size.** "How many rows will this query return?" If you don't know, that's a signal to add `LIMIT 50` and rerun, or check `profile-data` for the base population's row count. Anything beyond a few thousand rows belongs in a file, not in chat.
4. **Dry-plan for shape.** DuckDB's `EXPLAIN` (or `EXPLAIN ANALYZE` for an executed-plan estimate) is free and instant:
   ```bash
   bash .agents/tools/duckdb-query.sh "EXPLAIN <your sql>"
   ```
5. **Decide.** If scope and return size are acceptable, proceed. If the return size is large but the **answer is a summary**, the decision is `route via pre-aggregate`. If the answer is the raw rows themselves and the consumer is external, route via `format-output`. If neither and the query is just too big, narrow first.
6. Paste the premortem block into context. Subsequent reasoning refers back to it instead of repeating the analysis.

## Reference

Premortem block template:
```
Intent: <one sentence>
Likely failure modes:
  1. <mode> -> mitigation: <how this query avoids it>
  2. <mode> -> mitigation: <…>
  3. <mode> -> mitigation: <…>
Estimated rows returned: <answer or "unknown — narrowing first">
Decision: <proceed | narrow first | route via pre-aggregate | abort>
```

→ Next: `run-query`, `bi-view`, `ops-dataset`, or `compliance-query` — whichever the intent maps to.
