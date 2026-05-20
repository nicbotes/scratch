# Reference: Common Query Recipes

Canonical patterns. Each is shown as a single `athena-query.sh` invocation. All assume `ROOT_ENV=production`.

## Active policies summary

Counts and total premium by status — a sanity-check query for the start of any analytical session.

```bash
bash .agents/tools/athena-query.sh "
SELECT
  status,
  COUNT(*) AS count,
  SUM(monthly_premium) / 100.0 AS total_premium
FROM policies
WHERE environment = 'production'
GROUP BY status
ORDER BY count DESC"
```

## Premium report with module JSON

```bash
bash .agents/tools/athena-query.sh "
SELECT
  p.policy_number,
  p.monthly_premium / 100.0 AS premium,
  p.sum_assured / 100.0 AS cover,
  JSON_EXTRACT_SCALAR(p.module, '\$.plan_type') AS plan,
  ph.first_name || ' ' || ph.last_name AS policyholder
FROM policies p
JOIN policyholders ph USING (policyholder_id)
WHERE p.environment = 'production'
  AND p.status = 'active'
LIMIT 100"
```

## Payment failure analysis

Per-policy failure count over 90 days. Useful as the basis for an `ops_failed_payments_to_retry_view`.

```bash
bash .agents/tools/athena-query.sh "
SELECT
  policy_id,
  COUNT(*) AS failed_count,
  SUM(amount) / 100.0 AS total_failed
FROM payments
WHERE environment = 'production'
  AND status = 'failed'
  AND from_iso8601_timestamp(created_at) >= NOW() - INTERVAL '90' DAY
GROUP BY policy_id
ORDER BY failed_count DESC
LIMIT 100"
```

## Retention by month-cohort

Start narrow (one cohort) before generalising. The narrow version below is the unit; widen by adding cohort and month dimensions once the relationship looks right.

```bash
bash .agents/tools/athena-query.sh "
WITH cohort AS (
  SELECT policy_id, from_iso8601_timestamp(start_date) AS start_ts
  FROM policies
  WHERE environment = 'production'
    AND from_iso8601_timestamp(start_date) >= TIMESTAMP '2025-01-01 00:00:00 UTC'
    AND from_iso8601_timestamp(start_date) <  TIMESTAMP '2025-02-01 00:00:00 UTC'
)
SELECT
  date_diff('month', c.start_ts, from_iso8601_timestamp(p.end_date)) AS months_to_lapse,
  COUNT(*) AS lapses
FROM cohort c
JOIN policies p USING (policy_id)
WHERE p.environment = 'production'
  AND p.status IN ('lapsed', 'cancelled')
GROUP BY 1
ORDER BY 1"
```

## Compliance: every record on a subject

For DSARs. Route through `export-results.sh` so the manifest captures the evidence.

```bash
SUBJECT_ID='ph_123'

bash .agents/tools/export-results.sh dsar-$SUBJECT_ID-policies \
  "SELECT * FROM policies WHERE environment='production' AND policyholder_id='$SUBJECT_ID'"

bash .agents/tools/export-results.sh dsar-$SUBJECT_ID-policyholders \
  "SELECT * FROM policyholders WHERE environment='production' AND policyholder_id='$SUBJECT_ID'"

bash .agents/tools/export-results.sh dsar-$SUBJECT_ID-payments \
  "SELECT p.* FROM payments p JOIN policies pol USING (policy_id)
   WHERE p.environment='production' AND pol.policyholder_id='$SUBJECT_ID'"
```

## Dimensional view (Kimball): payments fact

```bash
bash .agents/tools/save-view.sh fact_payments \
  "SELECT
     from_iso8601_timestamp(payment_date) AS payment_ts,
     date(from_iso8601_timestamp(payment_date)) AS payment_date_key,
     policy_id,
     payment_method_id,
     payment_type,
     status,
     CAST(amount AS BIGINT) AS amount_cents
   FROM payments
   WHERE environment = 'production'"
```

## Operational view: failed payments to retry

```bash
bash .agents/tools/save-view.sh ops_failed_payments_to_retry \
  "SELECT
     p.payment_id,
     p.policy_id,
     ph.first_name || ' ' || ph.last_name AS policyholder_name,
     ph.email AS policyholder_email,
     p.amount / 100.0 AS amount,
     p.payment_date,
     p.status
   FROM payments p
   JOIN policies pol USING (policy_id)
   JOIN policyholders ph USING (policyholder_id)
   WHERE p.environment = 'production'
     AND p.status = 'failed'
   ORDER BY p.payment_date ASC"
```

## Feature adoption (template)

Parameterise `<base population>`, `<feature signal>`, and the optional `<cohort window>`. Full workflow is `feature-adoption` skill; this is the bare SQL for one-off use.

```sql
WITH base AS (
  SELECT policy_id, module
  FROM policies
  WHERE environment = 'production'
    AND status = 'active'                                          -- <base filter>
),
adopters AS (
  SELECT policy_id
  FROM base
  WHERE JSON_EXTRACT_SCALAR(module, '$.<feature_path>')
        = '<feature_value>'                                        -- <feature signal>
)
SELECT
  (SELECT COUNT(*) FROM adopters)                                  AS adopters,
  (SELECT COUNT(*) FROM base)                                      AS base,
  1.0 * (SELECT COUNT(*) FROM adopters)
      / NULLIF((SELECT COUNT(*) FROM base), 0)                     AS adoption_rate;
```

Monthly trend version:

```sql
SELECT
  date_trunc('month', from_iso8601_timestamp(created_at))      AS month,
  COUNT(*)                                                     AS base,
  COUNT_IF(JSON_EXTRACT_SCALAR(module, '$.<path>')
           = '<value>')                                        AS adopters,
  1.0 * COUNT_IF(JSON_EXTRACT_SCALAR(module, '$.<path>')
                 = '<value>') / NULLIF(COUNT(*), 0)            AS rate
FROM policies
WHERE environment = 'production'
  AND status = 'active'
  AND from_iso8601_timestamp(created_at) >= NOW() - INTERVAL '6' MONTH
GROUP BY 1
ORDER BY 1;
```

## DuckDB on Athena CSV: dates auto-infer to TIMESTAMP

DuckDB's CSV reader inspects the first N rows and types ISO-shaped date columns as `TIMESTAMP`, not `VARCHAR`. Functions written assuming string input then fail:

```sql
-- ✗ Fails: SUBSTRING / STRPTIME expect VARCHAR
SELECT STRPTIME(SUBSTRING(created_at, 1, 10), '%Y-%m-%d') AS d
FROM read_csv_auto('/tmp/policies.csv');
-- Binder Error: No function matches the given name and argument types 'substring(TIMESTAMP, ...)'

-- ✓ Works: cast the inferred TIMESTAMP to DATE
SELECT CAST(created_at AS DATE) AS d
FROM read_csv_auto('/tmp/policies.csv');

-- ✓ Also works: bypass type inference, read as string, then parse
SELECT STRPTIME(SUBSTRING(created_at, 1, 10), '%Y-%m-%d') AS d
FROM read_csv_auto('/tmp/policies.csv', types={'created_at': 'VARCHAR'});
```

The first form is the right move 95% of the time — DuckDB inferred the type correctly; lean on it. The `types={...}` override exists for the edge case where the CSV column is intentionally non-ISO and you need to control parsing yourself. Affects `skills/pre-aggregate.md` worked examples and `examples/policyholders-duckdb.sh`.

## Pre-aggregate on Parquet (the pull-once-slice-many pattern)

Pay Athena once to produce a typed Parquet file. Slice it locally with DuckDB as many times as the question needs — no extra scan cost.

```bash
# 1. Pull once
bash .agents/tools/athena-unload.sh policies_2025q1 \
  "SELECT
     policy_id,
     status,
     module,
     from_iso8601_timestamp(created_at) AS created_ts
   FROM policies
   WHERE environment = 'production'
     AND created_at >= '2025-01-01'
     AND created_at <  '2025-04-01'" \
  --format parquet
# → unload complete: s3://<bucket>/<org>/unloads/policies_2025q1/

# 2. Aggregate locally — adoption by month
bash .agents/tools/duckdb-query.sh \
  "SELECT
     date_trunc('month', created_ts) AS month,
     COUNT(*) AS base,
     COUNT_IF(JSON_EXTRACT_STRING(module, '\$.plan_type') = 'premium') AS adopters,
     1.0 * COUNT_IF(JSON_EXTRACT_STRING(module, '\$.plan_type') = 'premium')
         / NULLIF(COUNT(*), 0) AS rate
   FROM 's3://<bucket>/<org>/unloads/policies_2025q1/*.parquet'
   GROUP BY 1 ORDER BY 1"

# 3. Same dataset, different slice — by status (still free, still local)
bash .agents/tools/duckdb-query.sh \
  "SELECT status, COUNT(*) AS n
   FROM 's3://<bucket>/<org>/unloads/policies_2025q1/*.parquet'
   GROUP BY status ORDER BY n DESC"
```

For smaller scopes, swap step 1 for `athena-query.sh --to-file /tmp/data.csv` and reference `'/tmp/data.csv'` in the DuckDB query. See `skills/pre-aggregate.md` for the full workflow.

## Parquet unload for a data pipeline

Typed, columnar, snappy-compressed. Written straight to S3 — no CSV roundtrip, no type loss. The downstream pipeline reads the prefix.

```bash
bash .agents/tools/athena-unload.sh policies_2025q1 \
  "SELECT
     policy_id,
     status,
     CAST(monthly_premium AS BIGINT) AS premium_cents,
     from_iso8601_timestamp(created_at) AS created_ts
   FROM policies
   WHERE environment = 'production'
     AND created_at >= '2025-01-01'
     AND created_at <  '2025-04-01'" \
  --format parquet --compression snappy
# → unload complete: s3://<bucket>/<org_id>/unloads/policies_2025q1/
```

Consumer side (Python + pyarrow):

```python
import pyarrow.dataset as ds
table = ds.dataset(
    "s3://<bucket>/<org_id>/unloads/policies_2025q1/",
    format="parquet",
).to_table()
```

## JSONL feed for a Node / Python app

One JSON object per line — streamable on both sides.

```bash
bash .agents/tools/athena-query.sh --format jsonl \
  "SELECT policy_id, status FROM policies
   WHERE environment = 'production' LIMIT 10000" \
  > policies.jsonl

aws s3 cp policies.jsonl "s3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/feeds/policies.jsonl"
```

Consumer side (Node):

```js
const readline = require('readline');
const fs = require('fs');
const rl = readline.createInterface({ input: fs.createReadStream('policies.jsonl') });
rl.on('line', (line) => {
  const row = JSON.parse(line);
  // ...
});
```

## Regression golden

Closed window, deterministic.

```bash
bash .agents/tools/regression-record.sh total_premium_2025q1 \
  "SELECT SUM(monthly_premium) AS premium_cents
   FROM policies
   WHERE environment = 'production'
     AND created_at >= '2025-01-01'
     AND created_at <  '2025-04-01'"
```
