#!/usr/bin/env bash
# athena-query.sh "<sql>"        run query, print CSV
# athena-query.sh --dry-run "<sql>"  EXPLAIN only, print scanned-bytes estimate
# echo "<sql>" | athena-query.sh   accepts SQL on stdin

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
  shift
fi

sql="${1:-}"
if [[ -z "$sql" ]]; then
  if [[ ! -t 0 ]]; then
    sql="$(cat)"
  else
    echo "usage: athena-query.sh [--dry-run] \"<sql>\"" >&2
    exit 64
  fi
fi

if (( dry_run )); then
  qid="$(run_athena "EXPLAIN $sql")"
  fetch_results "$qid"
  exit 0
fi

qid="$(run_athena "$sql")"
fetch_results "$qid"
