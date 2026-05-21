# bi_pr_cycle_time_view

Analytical layer over merged GitHub PRs. One row per merged PR.

## Grain

One row per merged, non-draft pull request.

## Facts

| Column | Type | Meaning |
|---|---|---|
| `cycle_time_hours` | `INT` | Hours from PR creation to merge. Integer; floor of the hour difference. |

## Dimensions

| Column | Type | Meaning |
|---|---|---|
| `pr_id` | `BIGINT` | GitHub's internal PR id. Unique. Join key. |
| `pr_number` | `INT` | The repo-local PR number. Use for human-readable references. |
| `author` | `VARCHAR` | `user.login`. PII (some users use real names — see pii-columns.json). |
| `repo` | `VARCHAR` | `base.repo.full_name`. `<owner>/<repo>`. |
| `created_ts` | `TIMESTAMP` | When the PR opened. Timezone-naive UTC. |
| `merged_ts` | `TIMESTAMP` | When the PR merged. Timezone-naive UTC. |
| `state` | `VARCHAR` | Always `closed` (view filters on `merged_at IS NOT NULL`). |
| `draft` | `BOOLEAN` | Always `false` (view filters). |

## Refresh cadence

Manual via `bash .agents/tools/fetch-api.sh ... && bash .agents/tools/land-to-duckdb.sh pulls --source github`. Recommended weekly for active repos; daily for high-velocity work.

## Consumers

- Ad-hoc dev productivity report (PR cycle time percentiles by author / month / label).
- `pr_cycle_time_2025_q1` regression golden — pinned p50/p90 + count over Q1 2025.

## Reconciliation queries

Reconciliation 1: row count of the view matches the count of merged, non-draft PRs in the raw table.

```sql
-- Independent path: count from raw directly with the same filters
SELECT count(*) AS via_raw FROM raw_github_pulls
  WHERE merged_at IS NOT NULL AND draft = false;

-- Headline: count from the view
SELECT count(*) AS via_view FROM bi_pr_cycle_time_view;
```

Expected: `via_raw == via_view` (difference 0).

Reconciliation 2: total cycle-time hours computed via the view matches the same total computed via a different formulation in the raw table.

```sql
-- Independent path
SELECT sum(
  datediff('hour',
           strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
           strptime(merged_at,  '%Y-%m-%dT%H:%M:%SZ'))
) AS sum_hours_via_raw
FROM raw_github_pulls
WHERE merged_at IS NOT NULL AND draft = false;

-- Headline
SELECT sum(cycle_time_hours) AS sum_hours_via_view FROM bi_pr_cycle_time_view;
```

Expected: `sum_hours_via_raw == sum_hours_via_view`.

## Caveats

- **Timezone-naive timestamps.** `strptime` produces a timezone-naive TIMESTAMP. Comparing across timezones requires explicit `AT TIME ZONE 'UTC'`.
- **Bots.** Filter `WHERE user.type != 'Bot'` if you only care about human cycle time.
- **Squash/merge timing.** GitHub records `merged_at` at the moment of merge — squash commits don't change this. Safe.
- **Backfill risk.** If a re-fetch grows the historical window (the repo had old closed PRs the original fetch missed), the regression goldens may need `--re-record` with a `--note`.

## Source

Defined in `references/sources/github.md`. Created via `save-view.sh bi_pr_cycle_time "<sql>"`.
