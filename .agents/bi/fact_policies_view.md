# fact_policies_view

## Grain
One row per policy (production environment). Unique on `policy_id`. Includes all statuses: active, cancelled, lapsed, expired, not_taken_up, pending_initial_payment.

## Facts

| Column | Type | Units | Notes |
|---|---|---|---|
| `monthly_premium_cents` | BIGINT | cents | Recurring billed premium |
| `sum_assured_cents` | BIGINT | cents | Cover amount |
| `billing_amount_cents` | BIGINT | cents | Actual billing amount (may differ from monthly_premium for pro-rata) |
| `base_premium_cents` | BIGINT | cents | Base premium before loadings |
| `start_date` | TIMESTAMP | UTC | Policy inception date |
| `end_date` | TIMESTAMP | UTC | Policy expiry date — NULL for open-ended policies |
| `cancelled_at` | TIMESTAMP | UTC | NULL unless cancelled |
| `status_updated_at` | TIMESTAMP | UTC | Last status change |
| `created_at` | TIMESTAMP | UTC | Row creation; used for golden windows |
| `updated_at` | TIMESTAMP | UTC | |
| `start_date_key` | DATE | — | Conformed date key for `dim_date_view` |
| `end_date_key` | DATE | — | Conformed date key |
| `cancelled_date_key` | DATE | — | Conformed date key |
| `created_date_key` | DATE | — | Conformed date key |

## Dimensions

| Column | Type | Join target |
|---|---|---|
| `policy_id` | varchar | PK of grain |
| `policyholder_id` | varchar | `dim_policyholder_view` |
| `payment_method_id` | varchar | `dim_payment_method_view` |
| `application_id` | varchar | `applications` |
| `product_module_id` | varchar | `dim_product_view` |
| `product_module_definition_id` | varchar | `product_module_definitions` |
| `debicheck_mandate_id` | varchar | `debicheck_mandates` |
| `data_import_id` | varchar | `data_imports` |
| `product_key` | varchar | Materialised inline from `product_modules.key` |
| `product_name` | varchar | Materialised inline from `product_modules.name` |
| `policy_number` | varchar | Human-readable reference |
| `status` | varchar | `active`, `cancelled`, `lapsed`, `expired`, `not_taken_up`, `pending_initial_payment` |
| `scheme_type` | varchar | |
| `package_name` | varchar | |
| `billing_frequency` | varchar | |
| `billing_day` | integer | |
| `billing_month` | integer | |
| `currency` | varchar | |
| `flushed` | boolean | Soft-delete flag — filter `WHERE flushed = false` for clean reports |
| `reason_cancelled` | varchar | NULL unless cancelled |
| `cancellation_type` | varchar | NULL unless cancelled |
| `external_reference` | varchar | Partner/system reference |

## Status breakdown (at time of build, 2026-05-19)

| Status | Count | Total premium (cents) |
|---|---|---|
| cancelled | 100 | 4,918,544 |
| pending_initial_payment | 95 | 1,786,222 |
| not_taken_up | 22 | 203,139 |
| lapsed | 16 | 177,193 |
| expired | 9 | 40,919 |
| active | 8 | 181,024 |

> This is a testing org — the high proportion of cancelled/pending reflects test data, not a production book.

## Source
`policies WHERE environment = 'production'` LEFT JOIN `product_modules`

## SCD Type
SCD Type 1 (overwrite). Reflects latest policy state at snapshot time.

## Refresh
Daily, in line with Root Platform snapshots.

## Consumers
- Portfolio dashboard: `COUNT(*) / SUM(monthly_premium_cents) WHERE status = 'active'`
- Lapse analysis: policies transitioning to `lapsed` over time
- Product mix: `GROUP BY product_key, status`
- Cancellation analysis: `reason_cancelled`, `cancellation_type`

## Excluded columns (JSON — require derive-jsonb-schema before use)
`module`, `app_data`, `charges`, `covered_items`, `covered_people`, `beneficiaries`, `claim_ids`, `complaint_ids`

## Known caveats
- `flushed = true` rows exist — always add `WHERE flushed = false` for clean business reports
- `end_date` is NULL for open-ended (ongoing) policies — handle NULLs in tenure calculations
- `pending_initial_payment` policies have not yet paid their first premium — exclude from "in-force" calculations

## Regression goldens

| Golden | Description |
|---|---|
| `fact_policies_active_count` | Active policy count, created 2020-01-01 to 2026-01-01 |
| `fact_policies_premium_sum` | SUM(monthly_premium_cents) for active policies, same window |

Run with: `bash .agents/tools/regression-check.sh --all`

## Reconciliation queries

A regression golden guards drift over time; a reconciliation guards drift across paths. Each block below re-derives a measure from an **independent source / join logic** and must agree with the corresponding golden within the stated tolerance. See `references/data-trust.md` (F6) for the why.

### Reconciles `fact_policies_active_count` — from `policy_events` (event-log derivation)

Counts policies with an issuance event in the window and no subsequent terminal event. Independent of `policies.status` (which is the field the view filters on); a disagreement points to a stale-status bug or an event-log gap.

```sql
SELECT COUNT(DISTINCT pe.policy_id) AS active_count
FROM policy_events pe
WHERE pe.environment = 'production'
  AND pe.event_type IN ('policy_issued', 'policy_reinstated')
  AND date_format(pe.created_at, '%Y-%m-%d') >= '2020-01-01'
  AND date_format(pe.created_at, '%Y-%m-%d') < '2026-01-01'
  AND pe.policy_id NOT IN (
    SELECT policy_id
    FROM policy_events
    WHERE environment = 'production'
      AND event_type IN ('policy_cancelled', 'policy_lapsed', 'policy_expired', 'policy_not_taken_up')
  );
```

**Expected agreement:** exact, unless the event log lags the status field by a snapshot. Tolerance ≤ 1 day's worth of state transitions; greater drift = investigate.

### Reconciles `fact_policies_premium_sum` — from `policies` via in-force date logic (structural derivation)

Sums `monthly_premium` for policies in force as-of `2026-01-01` (the window's upper bound) using date predicates instead of the `status = 'active'` filter. Independent of how `status` is maintained; surfaces cases where `status` and the date columns disagree.

```sql
SELECT SUM(monthly_premium) AS premium_sum_cents
FROM policies
WHERE environment = 'production'
  AND flushed = false
  AND from_iso8601_timestamp(start_date) < TIMESTAMP '2026-01-01 00:00:00'
  AND (end_date IS NULL OR from_iso8601_timestamp(end_date) >= TIMESTAMP '2026-01-01 00:00:00')
  AND (cancelled_at IS NULL OR cancelled_at >= TIMESTAMP '2026-01-01 00:00:00')
  AND date_format(created_at, '%Y-%m-%d') >= '2020-01-01'
  AND date_format(created_at, '%Y-%m-%d') < '2026-01-01';
```

**Expected agreement:** within ~2% — "in-force on date" and "status = active" diverge for policies in transitional states (`pending_initial_payment`, `not_taken_up`). State the divergence; sustained drift > 5% is a calibration bug, not noise.
