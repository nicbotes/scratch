#!/usr/bin/env bash
# whoami.sh
# Resolve the active org by querying the organisations table
# for name where id = $ROOT_ORG_ID. Prints a four-line summary.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

sql="SELECT id, name FROM organisations WHERE id = '$ROOT_ORG_ID' LIMIT 1"
qid="$(run_athena "$sql")"
csv="$(fetch_results "$qid")"

# Drop header, take first row, split by comma
row="$(echo "$csv" | tail -n +2 | head -n 1 | tr -d '"')"
if [[ -z "$row" ]]; then
  echo "error: no row in organisations for id=$ROOT_ORG_ID" >&2
  echo "your AWS credentials may not grant access to this org's workgroup." >&2
  exit 1
fi

name="$(echo "$row" | awk -F',' '{print $2}')"

cat <<EOF
Org:    $name
Org ID: $ROOT_ORG_ID
Region: $AWS_REGION
Env:    $ROOT_ENV
EOF
