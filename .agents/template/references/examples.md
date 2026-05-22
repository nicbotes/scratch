# Reference: examples

Recipe cookbook. Fill in as you discover patterns worth sharing across sessions (`feedback-note.sh --kind success-pattern --target references/examples.md`).

The bundled examples below all target the GitHub source documented in `sources/github.md` and run against tables produced by `land-to-duckdb.sh pulls --source github`.

## Count PRs merged in a window

```sql
SELECT count(*) AS merged_prs
FROM raw_github_pulls
WHERE merged_at IS NOT NULL
  AND strptime(merged_at, '%Y-%m-%dT%H:%M:%SZ') >= TIMESTAMP '2025-01-01'
  AND strptime(merged_at, '%Y-%m-%dT%H:%M:%SZ') <  TIMESTAMP '2025-04-01';
```

## PR cycle time percentiles by author

```sql
SELECT
  user.login                                                        AS author,
  count(*)                                                          AS merged_prs,
  CAST(quantile_cont(cycle_time_hours, 0.5) AS INT)                 AS p50_hours,
  CAST(quantile_cont(cycle_time_hours, 0.9) AS INT)                 AS p90_hours
FROM bi_pr_cycle_time_view
WHERE merged_ts >= TIMESTAMP '2025-01-01'
GROUP BY 1
HAVING count(*) >= 5
ORDER BY merged_prs DESC
LIMIT 20;
```

## PRs open longer than 30 days

```sql
SELECT
  number,
  user.login                                       AS author,
  strptime(created_at, '%Y-%m-%dT%H:%M:%SZ')        AS created_ts,
  datediff('day',
           strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
           CURRENT_TIMESTAMP)                       AS days_open
FROM raw_github_pulls
WHERE state = 'open' AND draft = false
  AND datediff('day',
               strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
               CURRENT_TIMESTAMP) > 30
ORDER BY days_open DESC;
```

(Note: `CURRENT_TIMESTAMP` is fine for an ad-hoc operational query like this. It is **forbidden** in regression golden SQL — rule #13.)

## Label distribution

```sql
SELECT
  label.name                                       AS label_name,
  count(*)                                         AS pr_count
FROM (
  SELECT unnest(labels) AS label FROM raw_github_pulls
)
GROUP BY 1
ORDER BY pr_count DESC
LIMIT 20;
```
