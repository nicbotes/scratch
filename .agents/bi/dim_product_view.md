# dim_product_view

## Grain
One row per product module. Unique on `product_module_id`. Covers all modules regardless of status (active, archived, test/sandbox).

## Columns

| Column | Type | Notes |
|---|---|---|
| `product_module_id` | varchar | PK — join key for all fact views |
| `product_key` | varchar | Short code (e.g. `root_funeral`, `dinosure`) — use for filtering in reports |
| `product_name` | varchar | Human-readable name |
| `restricted` | boolean | Whether the module is restricted to this org |
| `owned_by_organization_id` | varchar | Owning org (may differ from querying org for shared modules) |
| `is_archived` | boolean | Derived: `archived_at IS NOT NULL` |
| `live_definition_id` | varchar | FK → `product_module_definitions` for the current live version |
| `draft_definition_id` | varchar | FK → `product_module_definitions` for the current draft |
| `created_at` | timestamp(3) | UTC |
| `archived_at` | timestamp(3) | UTC — NULL if active |

## Source
`product_modules` — **no `environment` column**, no env filter applied. All rows are org-level.

## SCD Type
SCD Type 1 (overwrite). Reflects latest state at snapshot time.

## Refresh
Daily, in line with Root Platform snapshots.

## Consumers
- `fact_payments_view` — already materialises `product_key` and `product_name` inline
- Future `fact_policies_view`, `fact_claims_view`, `fact_quote_funnel_view`
- Product performance dashboards (premium by product, claim ratio by product)

## Known caveats
- This is a **testing org** — many modules are test/sandbox/playground products (names contain `[TESTING]`, `[STAGING]`, `playground`, etc.). Filter by `product_key` or `product_name` when building production-grade reports.
- `is_archived = false` for all current rows — no modules have been archived yet in this org.

## Regression goldens

| Golden | Description |
|---|---|
| `dim_product_row_count` | Row count for modules created 2010-01-01 to 2026-01-01 |

Run with: `bash .agents/tools/regression-check.sh --all`
