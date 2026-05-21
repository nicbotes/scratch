---
name: ops-scheduled-function-volumes
description: Pull `rp_fact_scheduled_function_runs_view` across all orgs in `ROOT_ORG_IDS` into one local DuckDB file, then slice by org × product × function_name × hour to track scheduled-function and system-lifecycle execution volume. Use when tracking the "tighten targeting / reduce wasted runs" project, or when asked about how often scheduled functions fire per product / per org / per policy. Do NOT use for customer-driven hook latency (those are excluded by the view's `type = 'system'` filter) or for action-level "waste" measurement (the view has no action payload — only bookend timestamps).
---

# Skill: ops-scheduled-function-volumes

The data layer behind the cross-org scheduled-function-volume dashboard. One row per platform-scheduler-touched code-run; full hour of granularity; drill-down to a single policy; year-long horizon; daily refresh.

## What the view returns

`rp_fact_scheduled_function_runs_view` — one row per `product_module_code_runs` row where `triggered_by.type = 'system'`. That single filter cleanly captures scheduled functions **and** system-fired lifecycle hooks; customer-driven runs (`embed_jwt`, `api_key`, `user`, `product_module`) are excluded.

Definitions and the full DDL:

- `.agents/bi/fact_scheduled_function_runs_view.md`
- `.agents/bi/fact_scheduled_function_runs_view.sql`

There is no `dim_function_view`. Classification is naming-convention-based and happens at query time — see "Carve patterns" below.

## Carve patterns (the core idiom)

Platform lifecycle hooks always start with `after`/`before`; user-defined scheduled functions don't. Carve at query time:

```sql
-- Scheduled functions only (user-named, the high-volume targeting offenders)
WHERE function_name NOT LIKE 'after%' AND function_name NOT LIKE 'before%'

-- Platform lifecycle hooks only (platform-named, system-fired events)
WHERE function_name LIKE 'after%' OR function_name LIKE 'before%'
```

The project's primary signal is the scheduled-only carve. Lifecycle hooks are kept in the same view (rather than filtered out) because they're also platform-triggered and useful context — but they're not the targeting-waste signal.

## Daily refresh

```bash
bash .agents/tools/cross-org-pull.sh \
  --view rp_fact_scheduled_function_runs_view \
  --out .agents/cross-org/scheduled_function_runs.duckdb
```

Writes a fresh `unified` table with `org_id` / `org_name` prepended. Re-running is idempotent — every day overwrites. The file is the dashboard's source of truth.

For a daily cron, a thin wrapper that calls this and exits non-zero on any skipped org is enough.

## Slicing in DuckDB

### Headline — hourly scheduled-function volume by org × product × function

```bash
duckdb .agents/cross-org/scheduled_function_runs.duckdb -box -c "
  SELECT
    org_name,
    product_module_id,
    function_name,
    started_hour_key,
    COUNT(*)                                  AS run_count,
    APPROX_QUANTILE(duration_ms, 0.50)        AS p50_ms,
    APPROX_QUANTILE(duration_ms, 0.95)        AS p95_ms
  FROM unified
  WHERE started_at >= now() - INTERVAL 7 DAY
    AND function_name NOT LIKE 'after%'
    AND function_name NOT LIKE 'before%'
  GROUP BY 1, 2, 3, 4
  ORDER BY started_hour_key DESC, run_count DESC
  LIMIT 200;
"
```

### Join product names

`dim_product_view` already exists per-org. Pull it cross-org and ATTACH:

```bash
bash .agents/tools/cross-org-pull.sh \
  --view dim_product \
  --out .agents/cross-org/dim_product.duckdb

duckdb .agents/cross-org/scheduled_function_runs.duckdb -box -c "
  ATTACH '.agents/cross-org/dim_product.duckdb' AS p (READ_ONLY);
  SELECT
    f.org_name,
    p.unified.product_key,
    f.function_name,
    f.started_date_key,
    COUNT(*) AS run_count
  FROM unified f
  LEFT JOIN p.unified
    ON f.org_id = p.unified.org_id
   AND f.product_module_id = p.unified.product_module_id
  WHERE f.function_name NOT LIKE 'after%' AND f.function_name NOT LIKE 'before%'
  GROUP BY 1, 2, 3, 4
  ORDER BY started_date_key DESC, run_count DESC;
"
```

### Drill-down to a single policy

```bash
POLICY_ID=<uuid>
duckdb .agents/cross-org/scheduled_function_runs.duckdb -box -c "
  SELECT org_name, started_at, function_name, status, duration_ms
  FROM unified
  WHERE policy_id = '$POLICY_ID'
  ORDER BY started_at DESC
  LIMIT 200;
"
```

### Week-over-week delta after a targeting change

```bash
duckdb .agents/cross-org/scheduled_function_runs.duckdb -box -c "
  WITH weekly AS (
    SELECT
      org_name,
      function_name,
      date_trunc('week', started_at) AS wk,
      COUNT(*) AS runs
    FROM unified
    WHERE started_at >= now() - INTERVAL 8 WEEK
      AND function_name NOT LIKE 'after%'
      AND function_name NOT LIKE 'before%'
    GROUP BY 1, 2, 3
  )
  SELECT
    org_name, function_name, wk, runs,
    runs - LAG(runs) OVER (PARTITION BY org_name, function_name ORDER BY wk) AS delta_vs_prev_wk
  FROM weekly
  ORDER BY org_name, function_name, wk;
"
```

### Surprise audit — convention drift

Any name that bucks the convention is worth a manual look:

```bash
duckdb .agents/cross-org/scheduled_function_runs.duckdb -box -c "
  SELECT org_name, function_name, COUNT(*) AS runs,
    CASE WHEN function_name LIKE 'after%' OR function_name LIKE 'before%'
         THEN 'lifecycle (by name)'
         ELSE 'scheduled (by name)' END AS carve
  FROM unified
  GROUP BY 1, 2, 4
  ORDER BY runs DESC
  LIMIT 50;
"
```

If a `lifecycle (by name)` entry isn't one of the documented platform hooks (`afterPolicyIssued`, `afterPaymentSuccess`, etc.), it's a user-named function that breaks the convention — note it and either rename in the product code or special-case in dashboard queries.

## First-time setup — saving the view in a new org

Each org's Athena workgroup needs its own copy:

```bash
export ROOT_ORG_ID="<new-org-uuid>"
export ROOT_ATHENA_S3_BUCKET="<that-org's-bucket>"   # or use ROOT_ATHENA_S3_BUCKET_BY_ORG

# 1. Pre-check (see fact view doc): triggered_by.type distribution
bash .agents/tools/athena-query.sh "
  SELECT JSON_EXTRACT_SCALAR(triggered_by, '\$.type') AS t, COUNT(*) AS n
  FROM product_module_code_runs
  WHERE environment = 'production'
    AND created_at >= current_date - INTERVAL '30' DAY
  GROUP BY 1 ORDER BY 2 DESC
"

# 2. Save the view (rp_ prefix auto-prepended → rp_fact_scheduled_function_runs_view)
bash .agents/tools/save-view.sh fact_scheduled_function_runs_view \
  "$(cat .agents/bi/fact_scheduled_function_runs_view.sql)"
```

`save-view.sh` uses `CREATE OR REPLACE VIEW` — re-saving is safe and is how you ship updates.

## When to *not* use this skill

- **Customer-driven hook latency / volume.** Excluded from the view by the `type = 'system'` filter. Query `product_module_code_runs` directly with the appropriate `triggered_by.type` filter, or build a separate fact.
- **Action-level "waste" measurement.** The view has bookend timestamps, no action payload. `duration_ms` is the proxy. True no-op counts need product-module-side instrumentation.
- **Real-time monitoring.** Daily snapshot only — yesterday's data, not live.

## Reference

- View DDL + full column docs: `.agents/bi/fact_scheduled_function_runs_view.md`
- Fan-out + DuckDB pattern: `skills/cross-org-explore.md`
- Why this is `rp_fact_` not plain `fact_`: marks Root-Platform-built views, distinct from client/analyst-built `fact_*_view`s sharing the workgroup.

→ Cross-references: `skills/cross-org-explore.md`; `skills/bi-view.md`; `tools/save-view.sh`; `tools/cross-org-pull.sh`.
