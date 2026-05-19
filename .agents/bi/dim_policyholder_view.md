# dim_policyholder_view

## Grain
One row per policyholder (production environment). Unique on `policyholder_id`.

## Columns

| Column | Type | Notes |
|---|---|---|
| `policyholder_id` | varchar | PK — join key for `fact_policies_view`, `fact_payments_view` |
| `policyholder_type` | varchar | `individual` or `company` — aliased from `type` (reserved word in Athena) |
| `title` | varchar | e.g. `mr`, `ms`, `dr` — may be NULL |
| `gender` | varchar | e.g. `male`, `female` — may be NULL |
| `identification_type` | varchar | e.g. `id`, `passport` |
| `identification_country` | varchar | ISO country code |
| `identification_expiration_date` | timestamp(3) | UTC — NULL for non-expiring ID types |
| `country` | varchar | ISO country code for policyholder address |
| `geo_coordinates_latitude` | varchar | NULL if not geocoded |
| `geo_coordinates_longitude` | varchar | NULL if not geocoded |
| `data_import_id` | varchar | Non-NULL = created via data import |
| `external_reference` | varchar | Partner/system reference |
| `flushed` | boolean | Soft-delete flag — filter `WHERE flushed = false` for clean reports |
| `created_at` | timestamp(3) | UTC |
| `updated_at` | timestamp(3) | UTC |
| `archived_by` | varchar | User ID of archiver — NULL if not archived |

## PII exclusions
The following columns from `policyholders` are intentionally **excluded** to prevent PII leakage:
`first_name`, `last_name`, `middle_name`, `initials`, `email`, `cellphone`, `phone_other`, `identification_number`, `date_of_birth`, `address_line_1`, `address_line_2`, `suburb`, `city`, `area_code`, `google_place_id`, `company_name`, `registration_number`, `app_data`, `notes`, `attachments`, `policy_ids`

Never `SELECT *` from `policyholders` directly in a BI context — always go through this view.

## Source
`policyholders WHERE environment = 'production'`

## SCD Type
SCD Type 1 (overwrite). Reflects latest policyholder state at snapshot time.

## Refresh
Daily, in line with Root Platform snapshots.

## Consumers
- `fact_policies_view` — join on `policyholder_id` for demographic segmentation
- `fact_payments_view` — join on `policyholder_id` for payment behaviour by segment
- Portfolio segmentation: `GROUP BY policyholder_type, gender, identification_country`
- Geographic analysis: `geo_coordinates_latitude`, `geo_coordinates_longitude` for mapping

## Type breakdown (at time of build, 2026-05-19)

| Type | Count |
|---|---|
| individual | 148 |
| company | 5 |

> This is a testing org — the mix of individuals and companies reflects test data.

## Known caveats
- `flushed = true` rows exist — always add `WHERE flushed = false` for clean business reports
- `geo_coordinates_latitude` / `geo_coordinates_longitude` are NULL for most records — geocoding is optional
- `archived_by` is NULL for active policyholders; non-NULL signals the policyholder has been archived
- `identification_expiration_date` is NULL for SA ID numbers (non-expiring) — handle NULLs in expiry checks

## Regression goldens

| Golden | Description |
|---|---|
| `dim_policyholder_row_count` | Row count for policyholders created 2015-01-01 to 2026-01-01 |
| `dim_policyholder_type_counts` | Per-type counts, same window |

Run with: `bash .agents/tools/regression-check.sh --all`
