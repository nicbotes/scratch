# Source: GitHub REST API

The GitHub REST v3 API. Worked example shipped with the template — exercises the framework's full fetch → land → view → regression loop.

## Auth

- **Header:** `Authorization: Bearer $API_TOKEN`
- **Token type:** Personal Access Token (classic), fine-grained PAT, or GitHub App installation token.
- **Required scopes for read-only analysis:** `repo` for private repos, no scope needed for public.
- **Generate at:** https://github.com/settings/tokens (classic) or https://github.com/settings/personal-access-tokens (fine-grained).
- **`API_BASE_URL`:** `https://api.github.com`

## Pagination

- **Style:** Link header
- **Flag:** `--paginate link`
- **Per-page:** 100 (max). Use `--query "per_page=100"`.
- **Example header:** `Link: <https://api.github.com/...?page=2>; rel="next", <...?page=5>; rel="last"`

`fetch-api.sh` parses the `rel="next"` URL automatically.

## Rate limits

- **Authenticated:** 5000 requests / hour.
- **Unauthenticated:** 60 requests / hour. (Don't.)
- **Headers:**
  - `X-RateLimit-Limit` — your quota.
  - `X-RateLimit-Remaining` — requests left in the window.
  - `X-RateLimit-Reset` — epoch seconds when the window resets.
- **On 429:** read `X-RateLimit-Reset`, sleep until then. `fetch-api.sh` does this automatically.

## Reference endpoints

| Entity | Endpoint | Notes |
|---|---|---|
| PRs | `GET /repos/{owner}/{repo}/pulls?state=all` | Includes open, closed, merged, drafts. Filter `merged_at IS NOT NULL` for merged-only. |
| Issues | `GET /repos/{owner}/{repo}/issues?state=all` | **Quirk: includes PRs.** Filter `pull_request IS NULL` for issues-only. |
| Events | `GET /repos/{owner}/{repo}/events` | Last 90 days only, reverse chronological. |
| Commits | `GET /repos/{owner}/{repo}/commits` | Often expensive — narrow with `?since=`/`?until=` (ISO 8601). |
| Users | `GET /users/{login}` | Use for resolving `user.login` → real identity. PII. |
| Workflow runs | `GET /repos/{owner}/{repo}/actions/runs` | Useful for CI flow / DORA metrics. |

## Worked example: land merged PRs

```bash
# Set API_BASE_URL=https://api.github.com and API_TOKEN=<your PAT> first.

bash .agents/tools/whoami.sh --endpoint /user
# Expected: identity line.

bash .agents/tools/fetch-api.sh /repos/duckdb/duckdb/pulls \
  --query "state=closed&per_page=100" --paginate link \
  --source github --entity pulls --max-pages 5
# → data/raw/github/pulls/<utc-ts>.jsonl
# → data/raw/github/pulls/<utc-ts>.manifest.json

bash .agents/tools/land-to-duckdb.sh pulls --source github
# → table=raw_github_pulls rows=<n> partial=false

bash .agents/tools/profile-table.sh raw_github_pulls
# → row count, max(updated_at), columns.
```

## Build the BI view

```bash
bash .agents/tools/save-view.sh bi_pr_cycle_time \
  "SELECT
     id                                                AS pr_id,
     number                                            AS pr_number,
     user.login                                        AS author,
     base.repo.full_name                               AS repo,
     strptime(created_at, '%Y-%m-%dT%H:%M:%SZ')        AS created_ts,
     strptime(merged_at,  '%Y-%m-%dT%H:%M:%SZ')        AS merged_ts,
     CAST(datediff('hour',
                    strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
                    strptime(merged_at,  '%Y-%m-%dT%H:%M:%SZ')) AS INT) AS cycle_time_hours,
     state, draft
   FROM raw_github_pulls
   WHERE merged_at IS NOT NULL AND draft = false"
```

See `bi/bi_pr_cycle_time_view.md` for the sidecar (grain, facts, dims, reconciliation).

## Build an ops view

```bash
bash .agents/tools/save-view.sh ops_stale_prs \
  "SELECT
     number, user.login AS author, title, html_url,
     strptime(created_at, '%Y-%m-%dT%H:%M:%SZ') AS created_ts,
     datediff('day',
              strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
              CURRENT_TIMESTAMP) AS days_open
   FROM raw_github_pulls
   WHERE state = 'open' AND draft = false
     AND datediff('day',
                  strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
                  CURRENT_TIMESTAMP) > 14
   ORDER BY days_open DESC"
```

See `ops/ops_stale_prs_view.md` for the sidecar.

## Known PII columns

See `references/pii-columns.json`. For the GitHub source:

| Column | Sensitivity | Notes |
|---|---|---|
| `raw_github_pulls.user.login` | `pii` | Many users put their real name in their handle. |
| `raw_github_pulls.user.email` | `pii` | Rare on public REST. When present, strictly PII. |
| `raw_github_pulls.body` | `json_sensitive` | Free text. May contain anything. |
| `raw_github_pulls.title` | `json_sensitive` | Free text but lower risk; tag based on context. |
| `raw_github_issues.body` | `json_sensitive` | Same. |

(After landing, run `pii-scan.sh "SELECT user FROM raw_github_pulls LIMIT 1"` and add tags to `pii-columns.json` that reflect what you actually fetched.)

## Quirks worth knowing

- **Issues endpoint includes PRs.** Always filter `WHERE pull_request IS NULL` for issues-only views.
- **`merged_at` is the truth.** `state='closed'` doesn't mean merged — a PR can be `closed` without merging. Use `merged_at IS NOT NULL`.
- **Bot users.** `user.type = 'Bot'` (dependabot, renovate). Filter when measuring human cycle time.
- **Drafts.** `draft = true` PRs aren't "open" for cycle-time purposes. Exclude in `bi_pr_cycle_time_view`.
- **Squash/merge changes the commit count.** If a downstream measure depends on commits per PR, use the `/pulls/{number}/commits` endpoint, not the field on the PR object.
