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
