# Reference: Athena (Presto / Trino) SQL gotchas

Athena is Presto / Trino, not standard SQL. The common gotchas:

## Dates

All Root timestamps are ISO 8601 strings (e.g. `2025-03-14T08:42:11.000Z`). Always wrap before arithmetic.

```sql
-- Convert
SELECT from_iso8601_timestamp(created_at) AS created_ts FROM policies;

-- Compare against literal
WHERE from_iso8601_timestamp(created_at) >= TIMESTAMP '2025-01-01 00:00:00 UTC'

-- Date math
SELECT date_diff('day', from_iso8601_timestamp(start_date), NOW())
       AS days_active
FROM policies;

-- Timezone (return is always UTC; convert explicitly)
SELECT from_iso8601_timestamp(created_at) AT TIME ZONE 'Africa/Johannesburg'
FROM policies;

-- 30-day window (still requires a date filter for cost — see rules.md #9)
WHERE from_iso8601_timestamp(created_at) >= NOW() - INTERVAL '30' DAY
```

Goldens **never** use `NOW()` or `CURRENT_DATE` (rules.md #15).

## JSON

`module`, `charges`, `policy_events.data` are JSON-encoded varchars.

```sql
-- Scalar
JSON_EXTRACT_SCALAR(module, '$.cover_amount')

-- Nested object / array (returns JSON, not scalar)
JSON_EXTRACT(module, '$.beneficiaries')

-- Array operations
JSON_ARRAY_GET(charges, 0)
JSON_ARRAY_LENGTH(charges)
```

`JSON_EXTRACT_SCALAR` returns `varchar`. Cast before numeric work: `CAST(JSON_EXTRACT_SCALAR(module, '$.cover_amount') AS BIGINT)`.

## Money

Cents, stored as `bigint`. Keep as cents until display:

```sql
-- inside aggregates: cents
SUM(monthly_premium) AS premium_cents

-- only at display
SUM(monthly_premium) / 100.0 AS premium
```

Mixing `/100.0` inside `GROUP BY` keys or join conditions is a common source of off-by-one rounding bugs.

## NULL handling

Presto is strict about NULL propagation. Default to `COALESCE`:

```sql
SUM(COALESCE(amount, 0)) AS total
```

For null rates:
```sql
SELECT
  1.0 - 1.0 * COUNT(<col>) / COUNT(*) AS null_rate
FROM <table>
WHERE environment = '$ROOT_ENV';
```

## Views

```sql
CREATE OR REPLACE VIEW fact_payments_view AS
SELECT
  from_iso8601_timestamp(payment_date) AS payment_ts,
  policy_id,
  CAST(amount AS BIGINT) AS amount_cents,
  status
FROM payments
WHERE environment = 'production';
```

Names must end in `_view` and start with `fact_` / `dim_` / `ops_` (rules.md #6; `save-view.sh` enforces).

## EXPLAIN

```sql
EXPLAIN SELECT … ;     -- logical plan
```

`athena-query.sh --dry-run "<sql>"` wraps this and surfaces `DataScannedInBytes` from the engine — use it via the `premortem` skill.

## JSON-keys enumeration

When you don't yet know the keys inside a JSONB column, enumerate them empirically. Two patterns:

**Presto `map_keys` + `UNNEST`** — runs entirely in Athena:

```sql
WITH sample AS (
  SELECT module
  FROM policies
  WHERE environment = 'production'
    AND module IS NOT NULL
  LIMIT 50
)
SELECT key, COUNT(*) AS occurrences
FROM sample, UNNEST(map_keys(CAST(module AS map<varchar, json>))) AS t(key)
GROUP BY key
ORDER BY occurrences DESC;
```

This works when the JSON is an object. For arrays, sample raw values and inspect with `jq`.

**Shell + `jq` fallback** — useful when you want type and example value alongside the key:

```bash
bash .agents/tools/athena-query.sh \
  "SELECT module FROM policies WHERE environment='production' AND module IS NOT NULL LIMIT 50" \
  | tail -n +2 \
  | jq -r 'keys_unsorted[]' 2>/dev/null \
  | sort | uniq -c | sort -rn
```

The full reconciliation workflow (sampled + declared) is the `derive-jsonb-schema` skill.

## DuckDB compatibility note

`duckdb-query.sh` (see `skills/pre-aggregate.md`) speaks Presto/Trino-ish SQL — most idioms above port directly. Differences worth knowing:

| Athena (Presto/Trino) | DuckDB |
|---|---|
| `JSON_EXTRACT_SCALAR(col, '$.k')` | `JSON_EXTRACT_STRING(col, '$.k')` — same semantics, different name |
| `from_iso8601_timestamp(col)` | `CAST(col AS TIMESTAMP)` (DuckDB infers ISO 8601 directly) |
| `approx_percentile(col, 0.95)` | `quantile_cont(col, 0.95)` or `approx_quantile(col, 0.95)` |
| `date_diff('day', a, b)` | `date_diff('day', a, b)` — same |
| `date_trunc('month', ts)` | `date_trunc('month', ts)` — same |
| `COUNT_IF(predicate)` | `COUNT_IF(predicate)` — same (also `SUM(CASE WHEN … THEN 1 ELSE 0 END)`) |
| `UNNEST(map_keys(CAST(col AS map<varchar, json>)))` | `UNNEST(json_keys(col))` — DuckDB has a direct helper |
| no native `PIVOT` | native `PIVOT` / `UNPIVOT` — handy for cross-tabs |

When in doubt, run the query through `duckdb-query.sh` once with `LIMIT 5` — DuckDB's error messages are unusually clear and will name the function it expected.

## Common surprises

- **No `IF (cond, a, b)`** in some Athena versions — use `CASE WHEN cond THEN a ELSE b END`.
- **String concat** is `||`, not `+`.
- **Single quotes** for strings, double quotes for identifiers (`"my_table"`).
- **`LIMIT` doesn't reduce scan** — partition pruning is the only thing that does.
- **Aggregates on JSON** require `JSON_EXTRACT_SCALAR` first; you can't `SUM` a JSON value directly.
