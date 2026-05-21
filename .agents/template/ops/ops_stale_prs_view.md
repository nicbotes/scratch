# ops_stale_prs_view

Operational queue: open PRs that have been sitting longer than 14 days. Pre-filtered, denormalised, ranked by stale-ness. The reader opens this and pings each author.

## Action

The on-call engineer pings the author of each row with a one-line nudge ("PR #N is now 19 days old — what's blocking?"). The age-ordered list lets them work down the queue oldest-first.

## Reader

Engineering on-call, daily standup or async.

## Cadence

Daily. Re-fetch `pulls` via `land-data`, then re-query the view (the view is just a SQL view — re-evaluating gives the current state).

## Downstream sink

Optional: pipe the CSV to a Slack channel, an internal dashboard, or a Sheets export. The framework lands locally; out-of-band tooling handles delivery. See `references/output-formats.md`.

## Ordering contract

Strictly descending by `days_open`. Tied entries — open the same number of days — can appear in any order. The reader works top to bottom.

## Filter rules

| Filter | Why |
|---|---|
| `state = 'open'` | Already-merged or already-closed PRs don't need a nudge. |
| `draft = false` | Draft PRs are intentionally not ready; the nudge is noise. |
| `days_open > 14` | Two-week threshold. Lower it (7 days) for high-velocity teams; raise it (30 days) for repos with longer review cycles. |

Adjust the threshold by editing the view DDL. Don't fork the view for "different teams' thresholds" — write a `scratch_<ns>_stale_prs_view` for the experiment and promote when stable.

## Columns

| Column | Meaning |
|---|---|
| `pr_number` | Repo-local PR number. The thing the reader pastes into Slack. |
| `author` | `user.login`. PII (rule #23 / #25 still applies — pseudonymise before any external delivery). |
| `title` | PR title. Free text, `json_sensitive` — don't aggregate. |
| `created_ts` | When the PR opened. |
| `days_open` | The urgency signal. Sort key. |
| `pr_url` | `html_url`. Direct link for the reader. |

## Caveats

- Uses `CURRENT_TIMESTAMP` — that's fine for an operational view (rule #13 forbids it only in regression goldens). The view's "now" is whenever the query is re-evaluated.
- The age computation is in days; for hour-level urgency, use a sister `ops_stale_prs_hourly_view`.
- `body` is intentionally excluded — free-text PR bodies leak into context easily and the reader has the URL to read the full PR on GitHub.

## Source

Defined in `references/sources/github.md`. Created via `save-view.sh ops_stale_prs "<sql>"`.
