#!/usr/bin/env bash
# export-results.sh <name> "<sql>"
# Runs the SQL and persists the CSV + a manifest under
# .agents/evidence/<utc-ts>-<name>/ for compliance / audit.
#
# The manifest captures org id, env, sql, query execution id, row count and
# sha256 of the CSV so the export is verifiable independent of the agent
# session that produced it.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

name="${1:-}"
sql="${2:-}"
if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: export-results.sh <name> "<sql>"' >&2
  exit 64
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
dir="$AGENTS_ROOT/evidence/$ts-$name"
mkdir -p "$dir"

qid="$(run_athena "$sql")"

csv_path="$dir/results.csv"
fetch_results "$qid" > "$csv_path"

rows="$(($(wc -l < "$csv_path") - 1))"
sha="$(sha256sum "$csv_path" | awk '{print $1}')"

cat > "$dir/manifest.json" <<EOF
{
  "name": "$name",
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "org_id": "$ROOT_ORG_ID",
  "env": "$ROOT_ENV",
  "region": "$AWS_REGION",
  "query_execution_id": "$qid",
  "row_count": $rows,
  "sha256": "$sha",
  "sql": $(printf '%s' "$sql" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$(echo "$sql" | sed 's/"/\\"/g')")
}
EOF

echo "$dir"
