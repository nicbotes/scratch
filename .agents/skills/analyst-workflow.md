---
name: analyst-workflow
description: Open-ended exploratory analysis — funnels, cohorts, retention, lifetime value, churn drivers, distributions. Use when the user's question doesn't have a single right SQL and the path forward is to explore-narrow-widen. Do NOT use for a single specific row-level question (use run-query), a recurring KPI dashboard (use bi-view), or an action list (use ops-dataset).
---

# Skill: analyst-workflow

The "thinking" workflow. Start narrow, widen once the narrow version makes sense, ship a view once the shape is stable.

## Steps

1. **Clarify the question.** Restate it in one sentence with concrete entities and a date range. If you can't, ask the user before querying.
2. **Profile the relevant tables.** Call `profile-data` for each table that will contribute to the answer. Use the freshness, null rates, and row counts to constrain the analysis.
3. **Start narrow.** Pick a single cohort and a single time window. Get one number you trust before generalising. Example: "policies created in 2025-03, churned within 90 days" before "churn by month across all of 2025".
4. **Sanity-check.** Run a complementary query that should yield a related number (e.g. total cohort size next to churned cohort size) and confirm the relationship holds.
5. **Widen.** Add dimensions or extend the time range only after the narrow version is stable. Re-`premortem` if widening crosses the join/scan thresholds in rules.md #9. If the intermediate query is something you want to share, join against, or come back to next session, save it as a scratch view: `bash .agents/tools/save-view.sh --scratch [<ns>] <body> '<sql>'`. The namespace keeps it out of the canonical layer and labels the originator.
6. **Crystallise.** If the question will be asked again, hand off to `bi-view` (analytical layer) or `ops-dataset` (action queue), then drop the scratch view (`drop-view.sh scratch_<ns>_<body>_view`) once the canonical one lands. If it's a one-off, capture a regression golden for the headline number (`regression-test`) so the answer is reproducible later.
7. **Publish-time check.** Before sharing numbers with a human, run `regression-check.sh --all` and call out the data freshness (max(created_at) from the profile).

## Reference

Canonical recipes (`references/examples.md`):
- `active_policies_summary` — counts and total premium by status.
- `payment_failure_analysis` — failures per policy over 90 days.
- `retention_by_cohort` — start with month-cohort × month-since-start; widen later.

→ Next: `bi-view` (dimensional) for recurring; `ops-dataset` for ops queues; `regression-test` to pin the headline.
