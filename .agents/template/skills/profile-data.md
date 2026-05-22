---
name: profile-data
description: Gating skill — profile a DuckDB table (row count, freshness, partial flag, columns) before any non-trivial aggregation, so subsequent agent decisions rest on real ground truth rather than assumptions about data shape. Use when a new table enters scope, before any published aggregate, or when the user asks "is the data good enough to answer X?". Do NOT use when the table was already profiled this session and the question scope hasn't changed.
---

# Skill: profile-data

The profile output is context for the **next agent decision**, not a deliverable in its own right. Run it, paste it into context, and refer back to it when choosing columns, filters, and bucket sizes.

## Steps

1. Run:
   ```bash
   bash .agents/tools/profile-table.sh <table>
   ```
2. Inspect the output:
   - **Row count.** Sanity-check against expectation. Off by an order of magnitude? Suspect the wrong table or a partial fetch.
   - **`max(updated_at)` / `max(created_at)`.** If older than the source's agreed cadence, the snapshot is stale — say so in every downstream report (`stale` confidence label).
   - **`partial` flag in the table comment.** If `partial=true`, the contributing fetch didn't complete (F8). Numbers against this table are structurally incomplete, not just noisy. Re-fetch or accept the `partial` label.
   - **Columns.** Note STRUCT/LIST columns that need DuckDB-native access (`references/duckdb-sql.md`).
3. For columns you plan to aggregate on, run a targeted null/distinct check:
   ```bash
   bash .agents/tools/duckdb-query.sh "
     SELECT
       COUNT(*)                       AS total,
       COUNT(\"<col>\")                AS non_null,
       approx_count_distinct(\"<col>\") AS distinct_est
     FROM <table>"
   ```
4. **Flag any column with >5% nulls** before using it in `GROUP BY` or `SUM`. Decide explicitly: drop nulls, coalesce, or reject the column.
5. Commit the profile block to context. Subsequent skills (`analyst-workflow`, `bi-view`, `ops-dataset`) read it instead of re-querying.

## Reference

Useful follow-up profiles, depending on the question shape:
- **Cohort retention** → also profile event/log tables for `event_type` distribution.
- **Money / duration** → spot-check distribution with `quantile_cont(<col>, [0.5, 0.9, 0.99])` to catch outliers before they distort means.
- **Optional:** pin a profile snapshot as a golden via `regression-test` (e.g. `raw_github_pulls_row_count_2025-04-30`) so future sessions can detect upstream data shifts.

→ Next: `analyst-workflow` for open-ended analysis, `bi-view` for modelled aggregations, `ops-dataset` for action lists.
