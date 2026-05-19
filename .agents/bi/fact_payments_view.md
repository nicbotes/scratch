# fact_payments_view

## Grain
One row per payment attempt. Unique on `payment_id`. Includes successful, failed, pending, and reversed payments. A reversal creates a new row (`status = 'reversed'`) linked to the original via `reversal_of_payment_id` — not a type-2 update to the original row.

## Facts

| Column | Type | Units | Notes |
|---|---|---|---|
| `amount_cents` | BIGINT | cents | Core additive measure. Never divide inside SUM/AVG/GROUP BY. |
| `tracking_days` | INTEGER | days | Lifecycle duration from submission to finalization |
| `payment_ts` | TIMESTAMP | UTC | Settlement timestamp. Apply AT TIME ZONE at the BI layer. |
| `billing_ts` | TIMESTAMP | UTC | Billing cycle timestamp |
| `action_ts` | TIMESTAMP | UTC | Batch action date |
| `submitted_at` | TIMESTAMP | UTC | |
| `finalized_at` | TIMESTAMP | UTC | |
| `reviewed_at` | TIMESTAMP | UTC | |
| `reversed_at` | TIMESTAMP | UTC | NULL unless `status = 'reversed'` |
| `created_at` | TIMESTAMP | UTC | Row creation; used for regression golden windows |
| `payment_date_key` | DATE | — | Conformed date key for joining `dim_date_view` |

## Dimensions

| Column | Type | Join target |
|---|---|---|
| `payment_id` | varchar | PK of grain |
| `policy_id` | varchar | `policies`, future `dim_policy_view` |
| `payment_method_id` | varchar | `dim_payment_method_view` (not yet built) |
| `payment_batch_id` | varchar | `payment_batches` |
| `policyholder_id` | varchar | `dim_policyholder_view` (not yet built) |
| `product_module_id` | varchar | `dim_product_view` (not yet built) |
| `product_key` | varchar | Materialised inline from `product_modules.key` |
| `product_name` | varchar | Materialised inline from `product_modules.name` |
| `payment_method_type` | varchar | Materialised inline from `payment_methods.type` |
| `payment_method_bank` | varchar | Materialised inline from `payment_methods.bank` |
| `payment_type` | varchar | Degenerate dimension |
| `premium_type` | varchar | Degenerate dimension |
| `collection_type` | varchar | Degenerate dimension |
| `source` | varchar | Degenerate dimension |
| `status` | varchar | `successful`, `failed`, `pending`, `cancelled`, `reversed` |
| `currency` | varchar | Degenerate dimension |
| `is_external_payment` | boolean | Flag |
| `retry_of_payment_id` | varchar | NULL = original attempt; non-NULL = retry |
| `reversal_of_payment_id` | varchar | Links reversal rows to originals |
| `failure_reason` | varchar | Populated on failed/cancelled rows |
| `failure_code` | varchar | Populated on failed/cancelled rows |
| `data_import_id` | varchar | Non-NULL = payment came from a data import |

## Refresh
Daily. Reflects Root Platform snapshot taken shortly after midnight UTC. Not real-time.

## Consumers
- Collection rate dashboard: `COUNT(*) / COUNT(*) FILTER (WHERE retry_of_payment_id IS NULL)` by product / month
- Premium received report: `SUM(amount_cents) WHERE status = 'successful'`
- Failure analysis: `GROUP BY failure_code, failure_reason ORDER BY COUNT(*) DESC`
- Retry effectiveness: filter `retry_of_payment_id IS NOT NULL`

## SCD Type
SCD Type 1 (overwrite). The daily snapshot reflects latest state. No historical dimension tracking — reversals create new rows rather than updating prior ones.

## Known caveats
- **Pending payments** have NULL `payment_date_key` because `payment_date` is NULL before settlement. Filter `WHERE status != 'pending'` or handle NULLs explicitly in date-bounded aggregates.
- **Retried payments**: the failed original and each retry both appear as separate rows. Use `retry_of_payment_id IS NULL` in denominators when computing attempt rates.
- **Multi-currency**: `amount_cents` is denominated in `currency`. Add `WHERE currency = 'ZAR'` for single-currency reports.
- **22 payments** have NULL `payment_method_id` (external payments with `is_external_payment = true`). These will have NULL `payment_method_type` and `payment_method_bank`.
- `product_key` and `product_name` are NULL if the policy has no `product_module_id` or the product module row is missing.

## Data scanned (first dry-run)
Dry-run completed successfully. Athena reports cost as `?` bytes for EXPLAIN (no actual scan). Row count at time of first query: 441 payments (production, as of 2026-05-19 snapshot).

## Regression goldens

| Golden | Description |
|---|---|
| `fact_payments_2025q1_row_count` | Row count for 2025-01-01 to 2025-04-01 |
| `fact_payments_successful_2025q1_sum` | `SUM(amount_cents)` for successful payments, same window |
| `fact_payments_2025q1_status_counts` | Per-status counts, same window |

Run with: `bash .agents/tools/regression-check.sh --all`

## Next: conformed dimensions to build
- `dim_product_view` — product module key/name/status; small table, no env filter; reused by all future fact views
- `dim_payment_method_view` — PII-safe; expose only `type`, `bank`, `account_type`, `card_brand`, `banv_status`, `blocked_reason`
- `dim_policyholder_view` — SCD1 latest attributes; PII-safe columns only for BI use
