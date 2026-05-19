# dim_date_view

## Grain
One row per calendar day. Unique on `date_key`. Spans 2010-01-01 to 2030-12-31 (7,670 days).

## Columns

| Column | Type | Notes |
|---|---|---|
| `date_key` | DATE | PK — join key for all fact views on their `*_date_key` columns |
| `year` | bigint | e.g. `2025` |
| `quarter` | bigint | 1–4 |
| `month` | bigint | 1–12 |
| `month_name` | varchar | e.g. `January` |
| `week_of_year` | bigint | ISO week number |
| `day_of_week` | bigint | 1=Monday … 7=Sunday (ISO) |
| `day_of_week_name` | varchar | e.g. `Monday` |
| `day_of_month` | bigint | 1–31 |
| `day_of_year` | bigint | 1–366 |
| `is_weekend` | boolean | `true` for Saturday (6) and Sunday (7) |
| `year_month` | varchar | `YYYY-MM` — use for monthly GROUP BY (e.g. `2025-06`) |
| `year_quarter` | varchar | `YYYY-Qn` — use for quarterly GROUP BY (e.g. `2025-Q2`) |

## Source
Generated from Athena's `sequence()` function — no source table, no env filter, no PII.

```sql
FROM UNNEST(sequence(date '2010-01-01', date '2030-12-31', INTERVAL '1' DAY)) AS t(d)
```

## SCD Type
Static / immutable. Calendar facts don't change.

## Consumers
- Monthly payment time series: `JOIN dim_date_view d ON d.date_key = p.payment_date_key GROUP BY d.year_month`
- Quarterly revenue trend: `GROUP BY d.year_quarter`
- Weekend vs weekday collection rate: `GROUP BY d.is_weekend`
- Policy inception cohorts: `JOIN dim_date_view d ON d.date_key = pol.start_date_key GROUP BY d.year_month`

## Example time-series query

```sql
SELECT
  d.year_month,
  d.year_quarter,
  COUNT(p.payment_id)                                                AS payment_attempts,
  SUM(CASE WHEN p.status = 'successful' THEN p.amount_cents ELSE 0 END) AS collected_cents
FROM dim_date_view d
LEFT JOIN fact_payments_view p ON p.payment_date_key = d.date_key
WHERE d.year BETWEEN 2024 AND 2026
  AND p.payment_id IS NOT NULL
GROUP BY d.year_month, d.year_quarter
ORDER BY d.year_month
```

## Join notes
- `fact_payments_view.payment_date_key` — joins here; NULL for pending payments (no settlement date yet)
- `fact_policies_view.start_date_key` / `created_date_key` / `cancelled_date_key` — all conform to this key
- `dim_date_view` is a right-side spine: do `dim_date_view LEFT JOIN fact_*` when you need zero-filled months

## Known caveats
- South African public holidays are **not** included — `is_weekend` is the only business-day signal available
- `day_of_week` follows ISO (1=Monday, 7=Sunday) — not the MySQL/US convention (1=Sunday)
- `date_key` is `DATE` type; compare with `date '2025-01-01'` literals, not bare strings

## Regression goldens

| Golden | Description |
|---|---|
| `dim_date_row_count` | Row count for full spine 2010-01-01 to 2030-12-31 |
| `dim_date_weekend_count` | Weekend/weekday counts for 2020-01-01 to 2025-12-31 |

Run with: `bash .agents/tools/regression-check.sh --all`
