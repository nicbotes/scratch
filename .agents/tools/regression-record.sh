#!/usr/bin/env bash
# regression-record.sh <name> "<sql>" [--re-record --note "<reason>"]
# Captures a deterministic golden under .agents/regressions/<name>.json.
#
# Hard requirements:
#   - SQL must contain a closed historical time bound — either BETWEEN, or
#     both '>=' and '<' (or both '>' and '<='). NOW()/CURRENT_DATE rejected.
#   - <name>.json must not already exist unless --re-record is passed with
#     --note explaining why (data backfill, source correction, etc.).

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

re_record=0
note=""
positional=()
while (( $# )); do
  case "$1" in
    --re-record) re_record=1; shift ;;
    --note) note="$2"; shift 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

name="${1:-}"
sql="${2:-}"

if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: regression-record.sh <name> "<sql>" [--re-record --note "<reason>"]' >&2
  exit 64
fi

# 1. Reject non-deterministic SQL
if grep -Eqi '\b(NOW|CURRENT_DATE|CURRENT_TIMESTAMP|CURRENT_TIME|LOCALTIMESTAMP|LOCALTIME)\b' <<<"$sql"; then
  echo "error: SQL contains a non-deterministic time function (NOW/CURRENT_*)." >&2
  echo "Goldens must pin a fixed historical window. Replace with literal timestamps." >&2
  exit 64
fi

# 2. Require a closed historical window
has_between=0
has_lower=0
has_upper=0
grep -Eqi 'BETWEEN[[:space:]]+'\''[0-9]{4}-' <<<"$sql" && has_between=1
grep -Eq  '>=?[[:space:]]*'\''[0-9]{4}-'                <<<"$sql" && has_lower=1
grep -Eq  '<=?[[:space:]]*'\''[0-9]{4}-'                <<<"$sql" && has_upper=1
if (( has_between == 0 )) && { (( has_lower == 0 )) || (( has_upper == 0 )); }; then
  echo "error: SQL must pin a closed historical window." >&2
  echo "Use BETWEEN '<lo>' AND '<hi>' or both >= '<lo>' AND < '<hi>'." >&2
  exit 64
fi

out="$AGENTS_ROOT/regressions/$name.json"
if [[ -e "$out" && $re_record -eq 0 ]]; then
  echo "error: $out already exists. To overwrite, pass --re-record --note \"<reason>\"." >&2
  exit 64
fi
if [[ $re_record -eq 1 && -z "$note" ]]; then
  echo "error: --re-record requires --note explaining the legitimate data change." >&2
  exit 64
fi

# 3. Run and capture
require_env
qid="$(run_athena "$sql")"
result="$(fetch_results "$qid")"

# Compact result and SQL into JSON-safe strings
escape_json() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))' 2>/dev/null \
    || printf '"%s"' "$(sed 's/\\/\\\\/g; s/"/\\"/g' <<<"$1")"
}
j_sql="$(printf '%s' "$sql" | escape_json)"
j_res="$(printf '%s' "$result" | escape_json)"
j_note="$(printf '%s' "$note" | escape_json)"

bytes="$(aws athena get-query-execution --query-execution-id "$qid" \
  --output text --query 'QueryExecution.Statistics.DataScannedInBytes' 2>/dev/null || echo 0)"

mkdir -p "$AGENTS_ROOT/regressions"
cat > "$out" <<EOF
{
  "name": "$name",
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "captured_by": "agent",
  "org_id": "$ROOT_ORG_ID",
  "env": "$ROOT_ENV",
  "sql": $j_sql,
  "result": $j_res,
  "query_execution_id": "$qid",
  "data_scanned_bytes": $bytes,
  "re_recorded": $([[ $re_record -eq 1 ]] && echo true || echo false),
  "note": $j_note
}
EOF

echo "recorded: $out"
