#!/usr/bin/env bash
# regression-record.sh <name> "<sql>" [--re-record --note "<reason>"]
# Captures a deterministic golden under .agents/regressions/<org_id_hash>/<name>.json.
#
# Hard requirements:
#   - SQL must contain a closed historical time bound — either BETWEEN, or
#     both '>=' and '<' (or both '>' and '<='). NOW()/CURRENT_DATE rejected.
#   - <name>.json must not already exist unless --re-record is passed with
#     --note explaining why (data backfill, source correction, etc.).
#
# Goldens are committed to git. To avoid leaking org identifiers, the raw
# org_id is hashed into the path and the JSON, and query_execution_id is
# omitted entirely. See rules.md #25.

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

# 0. Reject sensitive SQL outright. Goldens commit to git; sensitive values
# never belong in a golden. Rule #15 + #26. The committed result field is
# innocuous only when the SQL is aggregate-shaped against non-sensitive
# columns. No --pii-required override here — the constraint is structural.
if is_sensitive_query "$sql"; then
  scan="$(scan_sql_for_sensitivity "$sql")"
  summary="$(_sensitive_summary "$scan")"
  cat >&2 <<EOF
error: regression goldens must be sensitive-free.
  $summary
Goldens are committed to git; sensitive values can't go there. Rules #15, #26.

Options:
  1. Restructure the golden to be aggregate-shaped on non-sensitive columns
     (e.g. SUM(monthly_premium), COUNT(*) GROUP BY status).
  2. If you need a per-subject deterministic check, use compliance-query
     + export-results.sh — those write to .agents/sensitive/ (gitignored).
EOF
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

# Compute the org-hash subfolder before validation — we still need require_env
# for that since ROOT_ORG_ID is required. Order: validate SQL shape first
# (cheap, no env needed); then require_env; then compute org_hash + path.
require_env
org_hash="$(hash_id "$ROOT_ORG_ID")"
out_dir="$AGENTS_ROOT/regressions/$org_hash"
out="$out_dir/$name.json"

if [[ -e "$out" && $re_record -eq 0 ]]; then
  echo "error: $out already exists. To overwrite, pass --re-record --note \"<reason>\"." >&2
  exit 64
fi
if [[ $re_record -eq 1 && -z "$note" ]]; then
  echo "error: --re-record requires --note explaining the legitimate data change." >&2
  exit 64
fi

# 3. Run and capture
qid="$(run_athena "$sql")"

# Inline result-schema check — authoritative. The pre-flight regex at step
# 0 should have caught most sensitive SQL, but the inline check catches
# aliased PII columns and computed-PII patterns. Rules #15, #26.
exec_scan="$(check_executed_query_sensitivity "$qid")"
if echo "$exec_scan" | grep -Eq '(pii|restricted|json_sensitive)=[^ ]+'; then
  summary="$(_sensitive_summary "$exec_scan")"
  cat >&2 <<EOF
error: regression goldens must be sensitive-free (inline schema check).
  $summary
The result schema Athena returned contains tagged columns. Goldens commit to
git; this can't go there even with an override.

Re-shape the SQL to drop the sensitive columns. Aggregate-only queries
(SUM/COUNT/AVG) never trip this check.
EOF
  exit 64
fi

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

mkdir -p "$out_dir"
cat > "$out" <<EOF
{
  "name": "$name",
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "captured_by": "agent",
  "org_id_hash": "$org_hash",
  "env": "$ROOT_ENV",
  "sql": $j_sql,
  "result": $j_res,
  "data_scanned_bytes": $bytes,
  "re_recorded": $([[ $re_record -eq 1 ]] && echo true || echo false),
  "note": $j_note
}
EOF

_mixpanel_track "Evidence Captured" "tool=regression-record" \
  "golden_name=$name" "org_id_hash=$org_hash" \
  "re_recorded=$([[ $re_record -eq 1 ]] && echo true || echo false)" \
  "data_scanned_bytes=$bytes"

echo "recorded: $out"
