# Dev Skill: Data Adapter (SQL Access)

Generate SQL queries for the Root Data Adapter — SQL access to all production data via AWS Athena. Connect BI tools (Power BI, Tableau, Looker, DBeaver) to build dashboards, reports, and automated data pipelines.

## Steps

1. Get credentials from Root Dashboard: Data Management → Data Adapter → Generate Access Key
2. Note the connection details: AWS Region, Athena Schema, Athena Workgroup, S3 Output Location
3. Connect your BI tool via JDBC or ODBC using server `athena.<region>.amazonaws.com` on port 443
4. Always filter by `environment = 'production'` for live data (or `'sandbox'` for testing)
5. Use `JSON_EXTRACT_SCALAR()` to query `module` data and other JSON fields
6. Use `from_iso8601_timestamp()` for date conversions — all dates are ISO 8601 UTC
7. Remember: amounts are in **cents** — divide by 100 for currency display
8. Data snapshots are created daily (shortly after midnight in your region) — not real-time
9. Custom views must end with `_view` suffix (e.g. `active_policies_view`)

→ For flat-file CSV exports instead of SQL, see `/dev-data-export`

---

## Reference: available tables

| Table | Key columns |
|---|---|
| `policies` | policy_id, policy_number, status, monthly_premium, sum_assured, module, charges, start_date, end_date |
| `payments` | payment_id, policy_id, amount, status, payment_type, payment_date, payment_method_id |
| `claims` | claim_id, policy_id, status, approval_status, module, created_at |
| `policyholders` | policyholder_id, first_name, last_name, email, id_number, date_of_birth |
| `policy_ledger` | policy_id, amount, description, currency, created_at |
| `policy_events` | policy_id, event_type, created_at, data |
| `payment_methods` | payment_method_id, policy_id, type, status |
| `notifications` | notification_id, policy_id, type, status, created_at |
| `users` | user_id, email, role |
| `product_module_definitions` | product_module_id, settings, billing |

## Reference: JSON field extraction

Root stores `module`, `charges`, and other nested data as JSON VARCHAR strings.

```sql
-- Extract a scalar value from module JSON
SELECT
  policy_id,
  JSON_EXTRACT_SCALAR(module, '$.cover_amount') AS cover_amount,
  JSON_EXTRACT_SCALAR(module, '$.plan_type') AS plan_type
FROM policies
WHERE environment = 'production'

-- Extract from charges array
SELECT
  policy_id,
  JSON_EXTRACT_SCALAR(charges, '$[0].name') AS first_charge_name,
  JSON_ARRAY_LENGTH(charges) AS num_charges
FROM policies

-- Extract nested JSON object
SELECT JSON_EXTRACT(module, '$.beneficiaries') AS beneficiaries
FROM policies
```

| Function | Purpose |
|---|---|
| `JSON_EXTRACT_SCALAR(col, '$.key')` | Get scalar value from JSON |
| `JSON_EXTRACT(col, '$.key')` | Get object/array from JSON |
| `JSON_ARRAY_GET(col, index)` | Get array element by index |
| `JSON_ARRAY_LENGTH(col)` | Count array items |

## Reference: date and time functions

```sql
-- Convert ISO 8601 string to timestamp
SELECT from_iso8601_timestamp(created_at) AS created_ts
FROM policies

-- Convert to local timezone
SELECT from_iso8601_timestamp(created_at) AT TIME ZONE 'Africa/Johannesburg' AS local_time
FROM policies

-- Date range filter
WHERE from_iso8601_timestamp(created_at) >= NOW() - INTERVAL '30' DAY

-- Date difference
SELECT date_diff('day', from_iso8601_timestamp(start_date), NOW()) AS days_active
FROM policies
```

## Reference: common query patterns

**Active policies summary:**
```sql
SELECT
  status,
  COUNT(*) AS count,
  SUM(monthly_premium) / 100.0 AS total_premium
FROM policies
WHERE environment = 'production'
GROUP BY status
```

**Monthly premium report with module data:**
```sql
SELECT
  p.policy_number,
  p.monthly_premium / 100.0 AS premium,
  p.sum_assured / 100.0 AS cover,
  JSON_EXTRACT_SCALAR(p.module, '$.plan_type') AS plan,
  ph.first_name, ph.last_name
FROM policies p
JOIN policyholders ph ON p.policyholder_id = ph.policyholder_id
WHERE p.environment = 'production'
  AND p.status = 'active'
```

**Payment failure analysis:**
```sql
SELECT
  p.policy_id,
  COUNT(*) AS failed_count,
  SUM(p.amount) / 100.0 AS total_failed
FROM payments p
WHERE p.environment = 'production'
  AND p.status = 'failed'
  AND from_iso8601_timestamp(p.created_at) >= NOW() - INTERVAL '90' DAY
GROUP BY p.policy_id
ORDER BY failed_count DESC
```

**Create a reusable view** (must end in `_view`):
```sql
CREATE VIEW active_policies_view AS
SELECT policy_id, policy_number, monthly_premium, sum_assured, module
FROM policies
WHERE environment = 'production' AND status = 'active'
```

## Reference: connection details

| Setting | Value |
|---|---|
| Server | `athena.<aws-region>.amazonaws.com` |
| Port | 443 (requests), 444 (responses) — whitelist both |
| Driver | JDBC (download from AWS) or ODBC |
| Auth | AWS Access Key ID + Secret Access Key (from Root Dashboard) |
| Snapshots | Daily, shortly after midnight in your region |

Compatible tools: Power BI, Tableau, Google Looker, Qlik, DBeaver.
