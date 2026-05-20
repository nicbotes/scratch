#!/usr/bin/env bash
# profile-table.sh <table>
# Emits a profile block intended to be appended to the agent's context.
#  - total row count (filtered by $ROOT_ENV)
#  - max(created_at) for freshness
#  - per-column null rates
#  - per-column distinct counts for low-cardinality columns
#
# Output is plain text, designed to be readable inline and stable across runs
# so subsequent agent decisions can rely on it as ground truth.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

table="${1:-}"
if [[ -z "$table" ]]; then
  echo "usage: profile-table.sh <table>" >&2
  exit 64
fi

# Columns + env-column probe via the Glue metastore — no Athena query, no
# bytes scanned, no DESCRIBE quoting quirks. Some tables (users, organizations,
# api_keys, ...) have no `environment` column; adding the predicate
# unconditionally would COLUMN_NOT_FOUND.
columns="$(bash "$(dirname "$0")/glue-describe.sh" --columns "$table")"

has_env_column=0
if bash "$(dirname "$0")/glue-describe.sh" --has-column "$table" environment; then
  has_env_column=1
fi

env_predicate=""
env_note="env=$ROOT_ENV"
if (( has_env_column )); then
  env_predicate="WHERE environment = '$ROOT_ENV'"
else
  env_note="env=N/A (no environment column — org-level or platform table)"
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
if (( has_env_column )); then
  echo "Note: snapshots refresh daily. Freshness is max(created_at) above."
else
  echo "Note: this table has no environment column — row count is unfiltered (both"
  echo "production and sandbox if present). Snapshots refresh daily."
fi
echo "For per-column null rates and distinct counts, run targeted queries"
echo "via athena-query.sh against the columns you care about — generic"
echo "null-rate scans are partition-expensive."
