---
name: regression-test
description: Pin deterministic golden answers against fixed historical windows, and verify subsequent work matches. Use when stabilising a bi_*/ops_*_view, after shipping a headline number, or before publishing analytical results. Do NOT use on non-deterministic SQL (NOW, CURRENT_DATE, unbounded MAX), partial-flagged tables, or open-ended exploration that's not yet stable.
---

# Skill: regression-test

Goldens are the cheapest possible second opinion. A `bi_pr_cycle_time_view` that returns p50=24 hours for 2025-Q1 today should return p50=24 hours for 2025-Q1 next week, next month, and next year. If it doesn't, something changed — and you want to know.

## Steps

1. **Pick a fixed historical window.** Closed on both sides:
   ```sql
   WHERE merged_ts >= TIMESTAMP '2025-01-01' AND merged_ts < TIMESTAMP '2025-04-01'
   ```
   Never `NOW()`, `CURRENT_DATE`, or open-ended `>=`. `regression-record.sh` rejects these.
2. **Compute the expected value yourself first** (via `analyst-workflow` or while building the `bi-view`). Don't record a golden you haven't reasoned about — that freezes a bug.
3. **Confirm the underlying table isn't partial.** `bash .agents/tools/profile-table.sh raw_<source>_<entity>` — look for `partial=true`. Goldens against partial tables are refused (F8).
4. **Record:**
   ```bash
   bash .agents/tools/regression-record.sh pr_cycle_time_2025q1 \
     "SELECT
        COUNT(*)                                          AS merged_prs,
        CAST(quantile_cont(cycle_time_hours, 0.5) AS INT) AS p50_hours,
        CAST(quantile_cont(cycle_time_hours, 0.9) AS INT) AS p90_hours
      FROM bi_pr_cycle_time_view
      WHERE merged_ts >= TIMESTAMP '2025-01-01'
        AND merged_ts <  TIMESTAMP '2025-04-01'"
   ```
   Name the golden so it tells the truth — `<measure>_<period>` or `<view>_<period>`.
5. **Round-trip check immediately:**
   ```bash
   bash .agents/tools/regression-check.sh pr_cycle_time_2025q1
   ```
   Should print `OK`. If not, the SQL isn't actually deterministic — investigate before relying on it.
6. **Run the full suite before publishing:**
   ```bash
   bash .agents/tools/regression-check.sh --all
   ```
   Rules.md #12: a red golden is stop-the-line, not retry-the-query.
7. **Legitimate drift handling.** When data actually changes (re-fetch grew the historical window, upstream backfill, schema change), don't silently re-record:
   ```bash
   bash .agents/tools/regression-record.sh pr_cycle_time_2025q1 "<sql>" \
     --re-record --note "GitHub returned 3 additional Q1 2025 PRs in the latest fetch; p50 unchanged, count +3."
   ```
   Git history preserves the prior value.

## Integration points

- **`bi-view` / `ops-dataset`:** record at least one golden when the view stabilises. Default name `<view>_<historical-period>`.
- **`analyst-workflow`:** when shipping a headline number, record it so the next session can reproduce it.
- **`profile-data`:** optionally pin row counts for a historical window — drift on next run signals upstream data changed.
- **`retro`:** `regression-check --all` failures become high-priority feedback (`rule-missing` or `tool-gap`) so the cause is investigated, not papered over.

## Good vs bad golden shapes

| Good | Bad |
|---|---|
| Aggregates over closed quarters / months. | `SELECT COUNT(*) FROM raw_github_pulls WHERE state = 'open'` — drifts daily. |
| Row counts as of a closed snapshot date. | `WHERE created_at >= '2025-01-01'` (no upper bound). |
| Per-status counts for a closed period. | Anything querying a `_view` you're actively iterating on. |
| Bi view percentiles over a closed window. | **Row-level captures** — these belong in `export-results.sh` (gitignored evidence), not a committed golden. |

## On-disk layout

Goldens live under `.agents/regressions/<api_base_hash>/<name>.json` — one subfolder per API base, hash computed from `$API_BASE_URL` via `hash_id` (rules.md #22). At single-API scale that's one folder; preserved for portability when an adopter extends to a second source. `regression-check --all` iterates only the current API's subfolder.

→ Cross-references: `rules.md` #12, #13, #22; `references/data-trust.md` (F5 drift over time, F8 partial fetch).
