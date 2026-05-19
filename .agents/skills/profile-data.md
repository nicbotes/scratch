---
name: profile-data
description: Gating skill — profile a table (row count, freshness, sampled columns) before any non-trivial aggregation, so subsequent agent decisions rest on real ground truth rather than assumptions about data shape. Use when a new table enters scope, before any published aggregate, or when the user asks "is the data good enough to answer X?". Do NOT use when the table was already profiled this session and the question scope hasn't changed.
---

# Skill: profile-data

The profile output is context for the **next agent decision**, not a deliverable in its own right. Run it, paste it into context, and refer back to it when choosing columns, filters, and bucket sizes.

## Steps

1. Run:
   ```bash
   bash .agents/tools/profile-table.sh <table>
   ```
2. Inspect the output:
   - **Row count.** Sanity-check against expectation. Off by an order of magnitude? Suspect a missing env filter or a wrong table.
   - **`max(created_at)`.** If older than 36h, the snapshot is stale — say so in every downstream report.
   - **Columns.** Compare to `references/schema.md`. New columns? Add to the next retro proposal.
3. For columns you plan to aggregate on, run a targeted null/distinct check (the script avoids partition-expensive generic scans):
   ```bash
   bash .agents/tools/athena-query.sh "
     SELECT
       COUNT(*) AS total,
       COUNT(<col>) AS non_null,
       APPROX_DISTINCT(<col>) AS distinct_est
     FROM <table>
     WHERE environment = '$ROOT_ENV'"
   ```
4. **Flag any column with >5% nulls** before using it in `GROUP BY` or `SUM`. Decide explicitly: drop nulls, coalesce, or reject the column.
5. Commit the profile block to context. Subsequent skills (`analyst-workflow`, `bi-view`, `ops-dataset`) read it instead of re-querying.

## Reference

Useful follow-up profiles, depending on the question shape:
- Cohort retention questions → also profile `policy_events` for `event_type` distribution.
- Money questions → spot-check `monthly_premium` distribution with `APPROX_PERCENTILE(monthly_premium, ARRAY[0.5, 0.9, 0.99])` to catch outliers before they distort means.
- Optional: pin a profile snapshot as a golden via `regression-test` (e.g. `policies_row_count_2025-04-30`) so future sessions can detect upstream data shifts.

→ Next: `analyst-workflow` for open-ended analysis, `bi-view` for modelled aggregations, `ops-dataset` for action lists.
