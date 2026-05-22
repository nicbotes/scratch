---
name: ops-dataset
description: Build a flat, denormalised, pre-filtered, action-oriented view (ops_*_view) that ops works through directly or that feeds a downstream sink (Sheets, Zapier, CSV drop, Slack alert). Use when the consumer is a human queue or a non-aggregating pipeline. Do NOT use when the consumer is a BI tool that will re-aggregate (use bi-view), or when the question is exploratory (use analyst-workflow).
---

# Skill: ops-dataset

Operational caches are intentionally not analytical. They're the opposite — one row per action, every column the reader needs already present, ranked by urgency. Don't apologise for the lack of dimensional purity; document it.

## Steps

1. **Name the action, not the data.**
   - Good: `ops_stale_prs_view`, `ops_unmerged_long_branches_view`, `ops_failed_jobs_to_retry_view`.
   - Bad: `ops_prs_view` (what's the action?), `ops_jobs_view` (which jobs?).
   `save-view.sh` enforces the `ops_*_view` prefix.
2. **Pre-filter to the actionable rows only.** This is a queue, not an archive. `WHERE` should be aggressive — exclude already-completed, already-merged, future-scheduled. If the row shouldn't be on the screen, it shouldn't be in the view.
3. **Pre-join and denormalise.** The reader opens this and acts. Everything they need (who owns it, what state it's in, how old, what to do next) is on the row. No further joins required downstream.
4. **Rank by urgency** with `ORDER BY`. The order is part of the contract — oldest first, highest score first, most-overdue first. State the ordering in the sibling doc.
5. **Skip Kimball on purpose.** No surrogate keys, no conformed dimensions. State this in `.agents/ops/<view>.md` so future readers don't mistake it for sloppiness — it's intentional, and the consumer doesn't pay for what they don't use.
6. **Premortem.** Ops views refresh whenever the underlying landed table refreshes. Cost is small in DuckDB but compounds for downstream sinks.
7. **Persist:**
   ```bash
   bash .agents/tools/save-view.sh ops_stale_prs \
     "SELECT
        number                                              AS pr_number,
        user.login                                          AS author,
        title,
        strptime(created_at, '%Y-%m-%dT%H:%M:%SZ')           AS created_ts,
        datediff('day',
                 strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
                 CURRENT_TIMESTAMP)                          AS days_open,
        html_url                                             AS pr_url
      FROM raw_github_pulls
      WHERE state = 'open' AND draft = false
        AND datediff('day',
                     strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
                     CURRENT_TIMESTAMP) > 14
      ORDER BY days_open DESC"
   ```
8. **Document the downstream action.** Write `.agents/ops/<view>.md` covering:
   - **Action** ("the on-call engineer pings each author with a one-line nudge")
   - **Reader** ("eng on-call, daily standup")
   - **Cadence** (daily after `land-data` re-fetch)
   - **Downstream sink** (Sheets export, Slack hook, dashboard) — set up out-of-band
   - **Ordering contract** (what "first" means)
9. **Optional regression golden** — pin a historical count if you want drift alerts; not required for ops queues.

**Promoting from a `scratch_<ns>_*_view`?** Create the canonical `ops_*_view` first, confirm the downstream sink is pointing at the new name, then `drop-view.sh scratch_<ns>_<body>_view`. Never rename in place — the consumer may be polling the scratch path on a schedule.

## Reference

Examples of intent:
- `ops_stale_prs_view` — PRs open > N days, ordered by age.
- `ops_unattended_issues_view` — issues with no response in 7 days.
- `ops_failing_workflows_view` — CI workflows failing >2x in a row.

→ Cross-references: `bi-view` for the opposite intent (modelled re-aggregation); `format-output` if the queue ships as a periodic file rather than a live view.
