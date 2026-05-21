# fact_scheduled_function_runs_view

Athena view name: `rp_fact_scheduled_function_runs_view` (the `rp_` framework prefix is auto-prepended by `save-view.sh` and marks it as Root-Platform-built, distinct from client/analyst-built `fact_*` views that share the workgroup). Per-org. Sibling DDL in `fact_scheduled_function_runs_view.sql`. Cross-org refresh driven by `/ops-scheduled-function-volumes`.

## Grain

One row per `product_module_code_runs` row where `triggered_by.type = 'system'` — i.e. one row per (policy, function, platform-scheduler-touched execution). Unique on `product_module_code_run_id`.

## Filter

```sql
environment = 'production'
AND JSON_EXTRACT_SCALAR(triggered_by, '$.type') = 'system'
```

That's it — **no name allowlist**. `triggered_by` is a JSON object (`{"type": "...", "id": "...", "ownerId": "..."}`). Observed `.type` values:

| `type` | Meaning | Included? |
|---|---|---|
| `system` | Platform scheduler fired this (scheduled function OR auto-triggered lifecycle hook) | **yes** |
| `embed_jwt` | Customer embed flow (quote-to-issue) | no |
| `user` | Dashboard user clicked something | no |
| `api_key` | Partner/integration via API | no |
| `product_module` | Cross-module trigger (rare) | no |

## Columns

| Column | Type | Notes |
|---|---|---|
| `product_module_code_run_id` | varchar | PK |
| `product_module_id` | varchar | Join: `dim_product_view` (product_key / product_name) |
| `product_module_definition_id` | varchar | Version of the module that ran (drift indicator) |
| `policy_id` | varchar | **Drill-down key** to `fact_policies_view` |
| `function_name` | varchar | Raw passthrough. Carve at query time — see below. |
| `triggered_by_type` | varchar | Always `'system'` given the filter; kept as a sanity column |
| `status` | varchar | Observed: `complete`, `failed`. Surface anything else via the surprise audit query in the skill. |
| `started_at` | TIMESTAMP | `created_at` |
| `completed_at` | TIMESTAMP | NULL if incomplete |
| `duration_ms` | BIGINT | `date_diff('millisecond', ...)`. NULL if incomplete. Proxy for "did work" vs. "no-op". |
| `started_hour_key` | TIMESTAMP | `date_trunc('hour', started_at)` — drives hourly charts |
| `started_date_key` | DATE | `date_trunc('day', started_at)` |

`organization_id` / `organization_name` are NOT in the view — they're prepended by `cross-org-pull.sh` when unifying per-org CSVs into the local DuckDB file.

## Carve at query time

Naming convention is the carve. Platform lifecycle hooks always start with `after` or `before` (`afterPolicyIssued`, `beforePolicyCancelled`, …). User-defined scheduled functions don't (`expirePolicyAfterMainMemberClaim`, `removeOverAgeChildren`, …).

```sql
-- Scheduled functions only (user-named, the high-volume targeting offenders)
WHERE function_name NOT LIKE 'after%' AND function_name NOT LIKE 'before%'

-- Platform lifecycle hooks only (platform-named, fired by system events)
WHERE function_name LIKE 'after%' OR function_name LIKE 'before%'
```

**Surprise audit** — any high-volume row where the carve looks wrong (a name starting with `after`/`before` that you don't recognise as a lifecycle hook, or a non-`after`/`before` name that's clearly a hook) is worth a manual look. The skill includes the audit query.

## Source

`product_module_code_runs` (see `.agents/references/schema.md` lines 594–607).

## SCD Type

SCD Type 1. Code-run rows are append-only at source — a row never changes after it's written, so type 1 and type 2 are equivalent at this grain.

## Refresh

Daily, in line with Root Platform snapshots. Cross-org pull recipe: `/ops-scheduled-function-volumes`.

**Year-long retention note.** The view re-reads the full Athena snapshot each pull. If Athena retention is shorter than the dashboard lifetime, switch to append-only roll-ups into a separate `unified_history` DuckDB table. Flag if it bites.

## Pre-check before first save (new org)

Confirm `triggered_by.type` distribution looks like the baseline distribution:

```sql
SELECT JSON_EXTRACT_SCALAR(triggered_by, '$.type') AS t, COUNT(*) AS n
FROM product_module_code_runs
WHERE environment = 'production'
  AND created_at >= current_date - INTERVAL '30' DAY
GROUP BY 1 ORDER BY 2 DESC;
```

You'd expect `system` to be the largest bucket for any org with active scheduled functions; `embed_jwt` and `api_key` dominate orgs whose books are growing.

## Consumers

- Cross-org dashboard tracking scheduled-function waste reduction (~12 months); BI surface itself TBD
- Drill-down: "show me every system-triggered code-run for `policy_id = X`"
- Hourly volume by org × product × function_name (with the scheduled-only carve applied)
- Week-over-week delta after targeting changes ship

## Known caveats

- **`environment = 'production'` baked in.** Re-save with the string substituted for sandbox/staging.
- **`duration_ms` is a proxy, not ground truth, for "waste".** Fast run ≈ no-op; slow run ≈ did work. True no-op counts need product-module-side instrumentation.
- **`completed_at` may be NULL.** For crashed or still-running rows. Handle in the dashboard.
- **Naming-convention drift.** If a product author names a scheduled function `afterCleanup` (starting with `after`), the carve will misclassify it as lifecycle. Surface via the audit query in the skill.
- **`triggered_by` JSON shape may have additional `.type` values** in orgs we haven't sampled. The pre-check catches new values.

## Persistence

The view exists in each org's Athena workgroup as `rp_fact_scheduled_function_runs_view`. Re-save with `save-view.sh fact_scheduled_function_runs_view "$(cat .agents/bi/fact_scheduled_function_runs_view.sql)"` — `save-view.sh` auto-prepends `rp_` and uses CREATE OR REPLACE. When adding a new org, save the view into that org's workgroup — `cross-org-pull.sh` will otherwise log `skip org=<id> reason="query failed: ..."` and exclude it.

## Empirical baseline (customer org sample, 30 days)

Confirmed at plan time (2026-05-20):

| function_name | runs | category |
|---|---:|---|
| expirePolicyAfterMainMemberClaim | 2,505,871 | scheduled |
| checkIfChildRemovedInThirtyOrSixtyDays | 2,504,325 | scheduled |
| removeOverAgeChildren | 2,503,557 | scheduled |
| firstDebitOrderReminder | 2,496,447 | scheduled |
| processInstructions | 74,165 | scheduled |
| afterPaymentSuccess | 25,063 | lifecycle |
| afterPolicyLapsed | 14,048 | lifecycle |
| afterPolicyNotTakenUp | 10,180 | lifecycle |

Top 4 scheduled functions account for ~10M runs in 30 days — the targeting-waste signal the project is chasing.

## Regression goldens

Pin once a closed week is in the data. Suggested first golden: the sampled customer org `expirePolicyAfterMainMemberClaim` weekly run count for a fixed week window.

## Out of scope

- BI tool (Metabase / Hex / Streamlit) — plug onto unified DuckDB file once stable.
- Pre-aggregated hourly view. Defer until latency demands it.
- Customer-driven hooks (everything excluded by the `type = 'system'` filter). Different problem.
- Authoritative scheduled-function inventory from `.root-config.json` — not exposed via Data Adapter (confirmed: `product_module_definitions.settings` does not contain `scheduledFunctions`). Would need `rp` CLI fan-out if/when needed.
