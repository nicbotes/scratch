#!/usr/bin/env bash
# pii-scan.sh "<sql>"
# pii-scan.sh < file.sql
#
# Inspects a SQL statement for sensitive column references against
# references/pii-columns.json. Prints a single line:
#   pii=col1,col2 restricted=col3 json_sensitive=col4 json_paths=mod:path1
# Empty buckets are still printed (so grep/awk consumers can rely on the shape).
#
# Returns exit 0 in all cases (this tool reports; it doesn't refuse).
# The firewall in athena-query.sh / athena-unload.sh / regression-record.sh
# uses the same scanner internally and refuses based on policy.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

sql="${1:-}"
if [[ -z "$sql" ]]; then
  if [[ ! -t 0 ]]; then
    sql="$(cat)"
  else
    echo 'usage: pii-scan.sh "<sql>"  (or pipe SQL on stdin)' >&2
    exit 64
  fi
fi

scan_sql_for_sensitivity "$sql"
