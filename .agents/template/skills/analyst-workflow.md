---
name: analyst-workflow
description: Open-ended exploratory analysis — funnels, cohorts, retention, lifetime value, churn drivers, distributions, time-to-X metrics. Use when the user's question doesn't have a single right SQL and the path forward is to explore-narrow-widen. Do NOT use for a single specific row-level question (use run-query), a recurring KPI dashboard (use bi-view), or an action list (use ops-dataset).
---

# Skill: analyst-workflow

The "thinking" workflow. Start narrow, widen once the narrow version makes sense, ship a view once the shape is stable.

## Steps

1. **Clarify the question.** Restate it in one sentence with concrete entities and a date range. If you can't, ask the user before querying.
2. **Profile the relevant tables.** Call `profile-data` for each table that will contribute. Use freshness (`max(*)`), null rates, partial flag, and row counts to constrain the analysis.
3. **Start narrow.** Pick a single cohort and a single time window. Get one number you trust before generalising. Example: "PRs merged in 2025-03, cycle time p50" before "cycle time by month across all of 2025".
4. **Sanity-check.** Run a complementary query that should yield a related number (e.g. total cohort size next to the slice you computed) and confirm the relationship holds.
5. **Widen.** Add dimensions or extend the time range only after the narrow version is stable. Re-`premortem` if widening crosses the join/scan thresholds in rules.md #7. If the intermediate query is something you'll join against or come back to next session, save it as a scratch view: `bash .agents/tools/save-view.sh --scratch [<ns>] <body> '<sql>'`. The namespace keeps it out of the canonical layer and labels the originator.
6. **Crystallise.** If the question will be asked again, hand off to `bi-view` (analytical layer) or `ops-dataset` (action queue), then drop the scratch view (`drop-view.sh scratch_<ns>_<body>_view`) once the canonical one lands. If it's a one-off, capture a regression golden for the headline number (`regression-test`) so the answer is reproducible later.
7. **Publish-time check.** Before sharing numbers with a human, run `regression-check.sh --all`, confirm any documented reconciliation queries agree (BI sidecars carry these under "Reconciliation queries"), and prefix every number reported in chat with the confidence-label format from `references/data-trust.md` — `[verified|single-source|stale|sandbox|partial]` + as-of + evidence pointer. When a number can only land as `single-source` (no independent path agreed), say so explicitly — consumer calibration depends on it.

## Reference

Canonical recipes (`references/examples.md`):
- PR cycle time percentiles by author.
- PRs open longer than N days (operational queue candidate).
- Label distribution (cohort by tag).

→ Next: `bi-view` (dimensional) for recurring; `ops-dataset` for ops queues; `regression-test` to pin the headline.
