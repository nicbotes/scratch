---
name: bi-view
description: Build the analytical layer (bi_*_view; bi_fact_*, bi_dim_* when a star schema emerges) that downstream consumers will read repeatedly and re-aggregate. Use when the deliverable is a reusable layer for KPIs across cohorts/time/segments. Do NOT use for a flat list ops works through (use ops-dataset), a one-off question (run-query), or a compliance dump (compliance-query).
---

# Skill: bi-view

You are building the analytical layer. Discipline matters here — these views get joined, sliced, and trusted for downstream BI. Get them wrong and every chart downstream inherits the bug.

## Steps

1. **Declare the grain in one sentence.** "One row per merged PR", "one row per issue per day", "one row per user per session". If the grain is fuzzy, stop and clarify with the user — fuzzy grain is the root cause of most fact-table bugs.
2. **Separate facts from dimensions.** Once you have ≥3 BI views and a clear pattern, split:
   - **Facts** = additive measures: cycle time hours, count, sum of amounts.
   - **Dimensions** = descriptive context: author, repo, time, label, segment.
   One fact view, many dimension views joined on keys. Naming: `bi_fact_<event>_view`, `bi_dim_<entity>_view`.
3. **Conformed dimensions.** One `bi_dim_date_view`, one `bi_dim_author_view`, one `bi_dim_repo_view` reused across fact views. Don't duplicate dimensional logic — when author resolution diverges across fact views, downstream charts will disagree.
4. **Naming is strict** — `save-view.sh` enforces it:
   - `bi_<entity>_view` (e.g. `bi_pr_cycle_time_view`)
   - `bi_fact_<event>_view`, `bi_dim_<entity>_view` once a star schema is forming.
5. **No `SELECT *` in facts.** Each measure is named and typed (`CAST(datediff('hour', a, b) AS INT) AS cycle_time_hours`). Re-stating types prevents downstream confusion.
6. **Premortem the view.** A BI view is re-queried by every consumer — cost compounds even in DuckDB (and especially if you ever migrate it to a remote warehouse).
7. **Persist:**
   ```bash
   bash .agents/tools/save-view.sh bi_pr_cycle_time \
     "SELECT
        id                                                AS pr_id,
        number                                            AS pr_number,
        user.login                                        AS author,
        base.repo.full_name                               AS repo,
        strptime(created_at, '%Y-%m-%dT%H:%M:%SZ')        AS created_ts,
        strptime(merged_at,  '%Y-%m-%dT%H:%M:%SZ')        AS merged_ts,
        CAST(datediff('hour',
                       strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
                       strptime(merged_at,  '%Y-%m-%dT%H:%M:%SZ')) AS INT) AS cycle_time_hours
      FROM raw_github_pulls
      WHERE merged_at IS NOT NULL AND draft = false"
   ```
8. **Document the view.** Write `.agents/bi/<view>.md` covering:
   - **Grain** (one sentence)
   - **Facts** (column → meaning, units)
   - **Dimensions** (column → join key)
   - **Refresh cadence** (manual via `land-data`; recommended cadence for the source)
   - **Consumers** (which dashboards / tools read it)
   - **Reconciliation** (an independent SQL path that should produce a matching number)
9. **Pin a regression golden.** When the view is stable, record at least one deterministic golden against a fixed historical window (see `regression-test`) — typically a row count or a key aggregate for a single closed quarter.
10. **Document the reconciliation query.** Re-derive a key measure from an independent path (different table, different join logic, different aggregation) and confirm the numbers match (within stated tolerance). A regression golden guards drift *over time*; a reconciliation guards drift *across paths*. Both are defaults. Write the SQL in the sidecar under "Reconciliation queries", one block per measure. Reconciliation SQL must be aggregate-shaped and PII-clean (rules #13, #23). See `references/data-trust.md` (F6) for the why.

**Promoting from a `scratch_<ns>_*_view`?** Create the canonical `bi_*_view` first (running both for one snapshot is fine), confirm any consumers have switched, then `drop-view.sh scratch_<ns>_<body>_view`. Never rename in place — shared consumers may already be referencing the scratch path.

## Reference

Common conformed dimensions to build first when a star schema emerges:
- `bi_dim_date_view` — one row per calendar day, with day/week/month/quarter/year columns, ISO week. Cheap and used by every cohort/trend chart.
- `bi_dim_author_view` — latest known attributes per author (SCD1 — overwrite).
- `bi_dim_repo_view` — repo key → name, default-branch, public/private.

→ Cross-references: `ops-dataset` for the opposite intent (action queues, not analytics); `regression-test` for goldens; `references/data-trust.md` for reconciliation discipline.
