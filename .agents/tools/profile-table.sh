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

# Total + freshness
qid="$(run_athena "
SELECT
  COUNT(*) AS row_count,
  MAX(created_at) AS max_created_at,
  MIN(created_at) AS min_created_at
FROM \"$table\"
WHERE environment = '$ROOT_ENV'
")"
summary="$(fetch_results "$qid")"

# Columns
qid="$(run_athena "DESCRIBE \"$table\"")"
columns="$(fetch_results "$qid")"

echo "=== profile: $table (env=$ROOT_ENV, org=$ROOT_ORG_ID) ==="
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
