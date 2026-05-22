# Reference: DuckDB SQL gotchas

DuckDB is forgiving compared to Presto/Athena, but a handful of patterns trip first-time users. Cookbook of the most common.

## Reading landed JSON

`fetch-api.sh` writes one JSON record per line (JSONL). `land-to-duckdb.sh` invokes:

```sql
CREATE OR REPLACE TABLE raw_<source>_<entity> AS
SELECT * FROM read_json_auto(
  'data/raw/<source>/<entity>/*.jsonl',
  format='newline_delimited',
  union_by_name=true
);
```

DuckDB infers types and nests: a JSON object becomes a `STRUCT`, an array becomes a `LIST`, a leaf becomes `BIGINT`/`VARCHAR`/`BOOLEAN`/`DOUBLE`. `union_by_name=true` tolerates schema drift across pages.

## Accessing nested data

| Shape | Access | Notes |
|---|---|---|
| `STRUCT(login VARCHAR, id BIGINT)` | `user.login`, `user.id` | Dot-notation works if the column is typed `STRUCT`. |
| `JSON` or `VARCHAR` containing JSON | `json_extract_string(col, '$.path')` | Path syntax: `$.a.b[0].c`. |
| `LIST(STRUCT(...))` | `unnest(col)` in `FROM`, then dot-notation | Returns one row per list element. |
| Unknown — DuckDB inferred wrong | `CAST(col AS JSON)` then `json_extract_string` | Forces JSON-typed access. |

```sql
-- LIST of STRUCTs (PR labels)
SELECT pr_id, label.name, label.color
FROM (SELECT id AS pr_id, unnest(labels) AS label FROM raw_github_pulls);

-- STRUCT field
SELECT user.login, count(*) FROM raw_github_pulls GROUP BY 1;
```

## Date / timestamp handling (rule #1)

```sql
-- Landed JSON timestamps usually arrive as VARCHAR
SELECT strptime(created_at, '%Y-%m-%dT%H:%M:%SZ') AS created_ts FROM raw_github_pulls;

-- Compare TIMESTAMPs against typed literals, not bare strings
WHERE strptime(created_at, '%Y-%m-%dT%H:%M:%SZ') >= TIMESTAMP '2025-01-01'

-- Differences between timestamps
datediff('hour', start_ts, end_ts)     -- hours
datediff('day',  start_ts, end_ts)     -- days
age(end_ts, start_ts)                  -- INTERVAL ('3 days 02:15:00')

-- DuckDB TIMESTAMP is timezone-naive. To compute against local time:
SELECT created_ts AT TIME ZONE 'UTC' AT TIME ZONE 'Africa/Johannesburg' AS local_ts
```

## Percentiles

```sql
-- Linear interpolation
quantile_cont(cycle_time_hours, 0.5)   -- median
quantile_cont(cycle_time_hours, 0.9)   -- p90

-- Discrete
quantile_disc(cycle_time_hours, 0.95)
```

## COPY (writing files)

```sql
COPY (SELECT * FROM bi_pr_cycle_time_view) TO '/tmp/cycle.parquet' (FORMAT PARQUET);
COPY (SELECT * FROM raw_github_pulls)      TO '/tmp/pulls.csv'     (FORMAT CSV, HEADER);
```

Parquet preserves types and is cheaper to re-read than CSV. See rule #18.

## EXPLAIN (planning, no execution)

```sql
EXPLAIN ANALYZE SELECT count(*) FROM raw_github_pulls WHERE merged_at IS NOT NULL;
```

Useful in `premortem` to estimate row count and time before running a wide query.

## DESCRIBE (column-name introspection)

DuckDB's `DESCRIBE (<sql>)` runs the planner without executing — returns one row per output column with name and type. The framework uses this for the authoritative PII firewall check.

```sql
DESCRIBE (SELECT user.login AS author, count(*) FROM raw_github_pulls GROUP BY 1);
```

## COMMENT ON TABLE

`land-to-duckdb.sh` stamps tables with provenance via `COMMENT`. Surfaces via `duckdb_tables()`:

```sql
SELECT table_name, comment FROM duckdb_tables() WHERE table_name = 'raw_github_pulls';
-- partial=false;loaded_from=data/raw/github/pulls/*.jsonl;mode=replace
```

The `partial=true` substring is what `regression-record.sh` checks before allowing goldens.

## Things that work in Presto/Athena but not here

| Presto | DuckDB equivalent |
|---|---|
| `JSON_EXTRACT_SCALAR(col, '$.a')` | `json_extract_string(col, '$.a')` |
| `from_iso8601_timestamp(str)` | `strptime(str, '%Y-%m-%dT%H:%M:%SZ')` |
| `date_format(ts, '%Y-%m-%d')` | `strftime(ts, '%Y-%m-%d')` |
| `approx_percentile(x, 0.5)` | `quantile_cont(x, 0.5)` |
| `UNNEST(arr) AS t(elem)` in FROM | `unnest(arr)` (no AS required) |
| `CARDINALITY(arr)` | `len(arr)` |
