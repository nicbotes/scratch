-- Athena view name: rp_ops_monthly_invoice_lines_view (rp_ auto-prepended by save-view.sh)
-- Canonical DDL. Save into a new org with:
--   bash .agents/tools/save-view.sh ops_monthly_invoice_lines "$(cat .agents/ops/ops_monthly_invoice_lines_view.sql)"
-- See .agents/ops/ops_monthly_invoice_lines_view.md for line-item semantics.

WITH months AS (
  SELECT m AS year_month
  FROM UNNEST(sequence(DATE '2024-01-01', current_date, INTERVAL '1' MONTH)) AS t(m)
),
gwp AS (
  SELECT
    m.year_month,
    'gwp_inforce' AS line_item,
    COUNT(*) AS unit_count,
    SUM(p.monthly_premium) AS total_amount_cents
  FROM months m
  JOIN policies p
    ON p.environment = 'production'
   AND p.start_date < m.year_month + INTERVAL '1' MONTH
   AND (p.end_date IS NULL OR p.end_date >= m.year_month)
   AND (p.cancelled_at IS NULL OR p.cancelled_at >= m.year_month)
  GROUP BY 1
),
sms AS (
  SELECT
    date_trunc('month', n.created_at) AS year_month,
    'sms_billback' AS line_item,
    COUNT(*) AS unit_count,
    CAST(NULL AS BIGINT) AS total_amount_cents
  FROM notifications n
  WHERE n.environment = 'production' AND n.channel = 'sms'
  GROUP BY 1
),
banv AS (
  SELECT
    date_trunc('month', v.created_at) AS year_month,
    'banv_billback' AS line_item,
    COUNT(*) AS unit_count,
    SUM(v.provider_fee) AS total_amount_cents
  FROM verification_batches v
  WHERE v.environment = 'production'
  GROUP BY 1
),
embed AS (
  SELECT
    date_trunc('month', e.created_at) AS year_month,
    'embed_session_billback' AS line_item,
    COUNT(*) AS unit_count,
    CAST(NULL AS BIGINT) AS total_amount_cents
  FROM embed_sessions e
  WHERE e.environment = 'production'
  GROUP BY 1
)
SELECT
  CAST(year_month AS DATE) AS year_month,
  line_item,
  unit_count,
  total_amount_cents,
  'ZAR' AS currency
FROM (
  SELECT * FROM gwp
  UNION ALL SELECT * FROM sms
  UNION ALL SELECT * FROM banv
  UNION ALL SELECT * FROM embed
)
