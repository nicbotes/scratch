# dim_payment_method_view

## Grain
One row per payment method (production environment). Unique on `payment_method_id`.

## Columns

| Column | Type | Notes |
|---|---|---|
| `payment_method_id` | varchar | PK — join key for `fact_payments_view` |
| `policyholder_id` | varchar | FK → `policyholders` / future `dim_policyholder_view` |
| `payment_method_config_id` | varchar | FK → `payment_method_configs` |
| `verification_batch_id` | varchar | FK → `verification_batches` |
| `data_import_id` | varchar | Non-NULL = created via data import |
| `payment_method_type` | varchar | `debit_order`, `card`, `collection_module`, `eft` |
| `bank` | varchar | Bank code (e.g. `absa`, `fnb`, `capitec`) — NULL for card/eft/collection_module |
| `branch_code` | varchar | |
| `account_type` | varchar | e.g. `current`, `savings` |
| `card_brand` | varchar | e.g. `visa`, `mastercard` — populated for card type only |
| `banv_status` | varchar | Bank account verification status |
| `banv_auto_verified` | boolean | Whether verification was automated |
| `blocked_reason` | varchar | Non-NULL = method is blocked; describes why |
| `external_reference` | varchar | Partner reference |
| `created_at` | timestamp(3) | UTC |
| `updated_at` | timestamp(3) | UTC |
| `dismissed_at` | timestamp(3) | UTC — NULL if not dismissed |

## PII exclusions
The following columns from `payment_methods` are intentionally **excluded** to prevent PII leakage:
`account_holder`, `first_name`, `last_name`, `account_number`, `account_holder_identification`, `bin`, `holder`, `last_4_digits`, `expiry_year`, `expiry_month`

Never `SELECT *` from `payment_methods` directly in a BI context — always go through this view.

## Source
`payment_methods WHERE environment = 'production'`

## SCD Type
SCD Type 1 (overwrite). Reflects latest state at snapshot time.

## Refresh
Daily, in line with Root Platform snapshots.

## Consumers
- `fact_payments_view` — already materialises `payment_method_type` and `bank` inline; use this view for richer payment method attributes
- Payment method performance reports (collection rate by bank, by type)
- BANV verification dashboards

## Payment method type breakdown (at time of build, 2026-05-19)

| Type | Bank | Count |
|---|---|---|
| debit_order | absa | 39 |
| debit_order | fnb | 21 |
| debit_order | standard_bank | 9 |
| collection_module | — | 7 |
| debit_order | capitec | 7 |
| card | — | 5 |
| others | various | 15 |

## Known caveats
- `bank` is NULL for `card`, `eft`, and `collection_module` types — handle NULLs explicitly in bank-level aggregations.
- 1 payment method is blocked (`blocked_reason IS NOT NULL`, bank = absa).

## Regression goldens

| Golden | Description |
|---|---|
| `dim_payment_method_row_count` | Row count for methods created 2010-01-01 to 2026-01-01 |
| `dim_payment_method_type_counts` | Per-type counts, same window |

Run with: `bash .agents/tools/regression-check.sh --all`
