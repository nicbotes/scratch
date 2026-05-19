---
name: regression-test
description: Pin deterministic golden answers against fixed historical windows, and verify subsequent agent / human work matches. Use when stabilising a fact_*/dim_*/ops_*_view, after shipping a headline number, or before publishing analytical results. Do NOT use on non-deterministic SQL (NOW, CURRENT_DATE, unbounded MAX), sandbox data, or open-ended exploration that's not yet stable.
---

# Skill: regression-test

Goldens are the cheapest possible second opinion. A `fact_payments_view` that returns 1,432,907 rows for `2025-Q1` today should return 1,432,907 rows for `2025-Q1` next week, next month, and next year. If it doesn't, something changed — and you want to know.

## Steps

1. **Pick a fixed historical window.** Closed on both sides:
   ```sql
   WHERE created_at >= '2025-01-01' AND created_at < '2025-04-01'
   ```
   Never `NOW()`, `CURRENT_DATE`, or open-ended `>=`. `regression-record.sh` rejects these.
2. **Compute the expected value yourself first** (via `analyst-workflow` or while building the `bi-view`). Don't record a golden you haven't reasoned about — that freezes a bug.
3. **Record:**
   ```bash
   bash .agents/tools/regression-record.sh total_active_premium_2025q1 \
     "SELECT SUM(monthly_premium) AS total_cents
      FROM policies
      WHERE environment = '$ROOT_ENV'
        AND status = 'active'
        AND created_at >= '2025-01-01' AND created_at < '2025-04-01'"
   ```
   Name the golden so it tells the truth — `<measure>_<period>` or `<view>_<period>`.
4. **Round-trip check immediately:**
   ```bash
   bash .agents/tools/regression-check.sh total_active_premium_2025q1
   ```
   Should print `OK`. If not, the SQL isn't actually deterministic — investigate before relying on it.
5. **Run the full suite before publishing:**
   ```bash
   bash .agents/tools/regression-check.sh --all
   ```
   Rules.md #14: a red golden is stop-the-line, not retry-the-query.
6. **Legitimate drift handling.** When data actually changes (backfill, corrected source record, schema change), don't silently re-record:
   ```bash
   bash .agents/tools/regression-record.sh total_active_premium_2025q1 "<sql>" \
     --re-record --note "Backfill on 2026-05-12 corrected 2025-Q1 premiums for 3 policies; SUM increased by 78,400 cents."
   ```
   Git history preserves the prior value.

## Integration points

- **`bi-view` / `ops-dataset`:** record at least one golden when the view stabilises. Default name `<view>_<historical-period>`.
- **`analyst-workflow`:** when shipping a headline number, record it so the next session can reproduce it.
- **`profile-data`:** optionally pin row counts and null rates for a historical window — drift on next run = upstream data changed.
- **`retro`:** `regression-check --all` failures become high-priority feedback (`rule-missing` or `tool-gap`) so the cause is investigated, not papered over.

## Reference

Good golden shapes:
- Aggregates over closed quarters / months / half-years.
- Row counts of dimension views as of a specific snapshot date.
- Per-status counts for a closed period.
- The output of a `fact_*_view` filtered to a closed period (CSV result as the golden).

Bad golden shapes:
- `SELECT COUNT(*) FROM policies WHERE status = 'active'` — drifts daily, every passing day breaks the test.
- `WHERE created_at >= '2025-01-01'` (no upper bound) — same problem, slower drift.
- Anything querying `_view` definitions you're actively iterating on — pin only stable views.
- **Row-level captures** (e.g. `SELECT * FROM policies WHERE policy_id = '…'`) — these belong in `compliance-query` → `export-results.sh` (gitignored evidence), **not** in a committed golden. Rule #15.

## On-disk layout

Goldens live under `.agents/regressions/<org_id_hash>/<name>.json` — one subfolder per org, hash computed from `$ROOT_ORG_ID` via `hash_id` (rules.md #25). Multiple orgs' goldens coexist in the same repo without colliding; raw `org_id` never lands in git. `regression-check --all` only iterates the current org's subfolder. `bash .agents/tools/whoami.sh` prints `Org hash:` so you can map subfolders to orgs.

→ Cross-references: `rules.md` #14, #15, #25.
