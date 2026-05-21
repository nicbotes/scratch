-- Athena view name: rp_fact_scheduled_function_runs_view (rp_ auto-prepended by save-view.sh)
-- Canonical DDL. Save into a new org with:
--   bash .agents/tools/save-view.sh fact_scheduled_function_runs_view \
--     "$(cat .agents/bi/fact_scheduled_function_runs_view.sql)"
-- See .agents/bi/fact_scheduled_function_runs_view.md for grain and carve patterns.
--
-- Filter rationale: triggered_by.type = 'system' captures platform-scheduler-touched
-- runs only (scheduled functions + system-triggered lifecycle hooks). Customer-driven
-- runs (embed_jwt / user / api_key / product_module) are excluded by this single filter.
-- Carve scheduled vs. lifecycle at query time using the function_name prefix:
--   NOT LIKE 'after%' AND NOT LIKE 'before%'  ⇒ scheduled (user-named)
--   LIKE 'after%' OR LIKE 'before%'           ⇒ lifecycle (platform-named)

SELECT
  product_module_code_run_id,
  product_module_id,
  product_module_definition_id,
  policy_id,
  function_name,
  JSON_EXTRACT_SCALAR(triggered_by, '$.type')             AS triggered_by_type,
  status,
  created_at                                              AS started_at,
  completed_at,
  CASE
    WHEN completed_at IS NULL THEN NULL
    ELSE date_diff('millisecond', created_at, completed_at)
  END                                                     AS duration_ms,
  date_trunc('hour', created_at)                          AS started_hour_key,
  CAST(date_trunc('day', created_at) AS DATE)             AS started_date_key
FROM product_module_code_runs
WHERE environment = 'production'
  AND JSON_EXTRACT_SCALAR(triggered_by, '$.type') = 'system'
