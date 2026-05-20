# Proposal 05 — `profile-table.sh` environment-column guard

**Source feedback notes (`feedback/2026-05-19.jsonl`):**
- `2026-05-19T13:44:00Z` (tool-gap, tail) — "profile-table.sh blindly adds `WHERE environment = ...` — should detect tables without the column first (users table broke this session)"
- `2026-05-19T09:11:38Z` — confirms `users` lacks `environment`; `references/schema.md` line 643 documents it (`### users\nNo environment column.`)

## Reason

`profile-table.sh policies` works. `profile-table.sh users` fails with a SQL error because the tool unconditionally adds `WHERE environment = '$ROOT_ENV'` to the row-count query, and `users` (along with ~15 other tables — see `references/schema.md:16-22`) has no `environment` column. Same goes for `organizations`, `product_modules`, `api_keys`, etc.

The fix is to look up the column shape first and skip the predicate when absent. `DESCRIBE` via Athena already happens in the tool (line 34), so the data is in hand — we just need to consult it before the count query.

## Current state

`tools/profile-table.sh:22-30`:

```bash
qid="$(run_athena "
SELECT
  COUNT(*) AS row_count,
  MAX(created_at) AS max_created_at,
  MIN(created_at) AS min_created_at
FROM \"$table\"
WHERE environment = '$ROOT_ENV'
")"
```

Fails for any table in `references/schema.md`'s "Tables without `environment` column" list.

## Proposed change

Reorder: `DESCRIBE` first, build a column set, then conditionally include the env predicate. The tool already runs `DESCRIBE` later for the columns block — we just move it up.

```bash
#!/usr/bin/env bash
# (header comments unchanged)

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

table="${1:-}"
if [[ -z "$table" ]]; then
  echo "usage: profile-table.sh <table>" >&2
  exit 64
fi

# Columns first — we need to know whether the table has `environment` before
# we build the row-count query. DESCRIBE is cheap (no bytes scanned).
qid="$(run_athena "DESCRIBE \"$table\"")"
columns="$(fetch_results "$qid")"

# Detect `environment` column. DESCRIBE output is CSV with col_name,data_type,comment.
has_env_column=0
if printf '%s\n' "$columns" | awk -F',' 'NR>1 {gsub(/"/,"",$1); print $1}' \
    | grep -qx 'environment'; then
  has_env_column=1
fi

# Build env predicate only when applicable.
env_predicate=""
env_note="env=$ROOT_ENV"
if (( has_env_column )); then
  env_predicate="WHERE environment = '$ROOT_ENV'"
else
  env_note="env=N/A (table has no environment column — org-level or platform table)"
fi

# Total + freshness
qid="$(run_athena "
SELECT
  COUNT(*) AS row_count,
  MAX(created_at) AS max_created_at,
  MIN(created_at) AS min_created_at
FROM \"$table\"
$env_predicate
")"
summary="$(fetch_results "$qid")"

echo "=== profile: $table ($env_note, org=$ROOT_ORG_ID) ==="
echo
echo "-- summary --"
echo "$summary"
echo
echo "-- columns --"
echo "$columns"
echo
echo "Note: snapshots refresh daily. Freshness is max(created_at) above."
echo "For per-column null rates and distinct counts, run targeted queries"
echo "via athena-query.sh against the columns you care about — generic"
echo "null-rate scans are partition-expensive."
```

## Notes / non-changes

- **Independent of Proposal 04.** We don't reach for `glue-describe.sh` here because (a) it's a follow-up tool and we don't want to couple the env-guard fix to its existence, and (b) Athena's `DESCRIBE` is the same metastore-backed call under the hood — same answer, same cost. If Proposal 04 lands first, a future cleanup can swap to `glue-describe.sh --has-column $table environment` — but that's a cosmetic refactor, not load-bearing.
- DESCRIBE output is reliably `"col_name","data_type","comment"` CSV. The `awk` strips the surrounding quotes and the `grep -qx 'environment'` matches exactly (no substring false-positives like `environment_id`).
- We do **not** try to detect `created_at`; if it's missing the query will fail and the user gets a clear Athena error — preferable to silently dropping the freshness signal.

## Test

```bash
# Org-data table (has environment column)
bash .agents/tools/profile-table.sh policies
# → "=== profile: policies (env=production, org=...) ==="
# → row_count is filtered by environment

# Org-level table (no environment column)
bash .agents/tools/profile-table.sh users
# → "=== profile: users (env=N/A (table has no environment column — ...), org=...) ==="
# → succeeds; row_count is unfiltered

# Platform table
bash .agents/tools/profile-table.sh organizations
# → also succeeds with N/A note

# Regression: still works for the canonical case
bash .agents/tools/profile-table.sh payments
# → env=production, row_count filtered
```

Acceptance: every table named in `references/schema.md` profiles without SQL errors; the env note tells the agent whether the count is environment-scoped.
