#!/usr/bin/env bash
# regression-record.sh <name> "<sql>" [--db <path>] [--re-record --note "<reason>"]
#
# Captures a deterministic golden under .agents/regressions/<api_base_hash>/<name>.json.
#
# Hard requirements:
#   - SQL must contain a closed historical time bound — either BETWEEN, or
#     both '>='/'>' and '<'/'<='. NOW()/CURRENT_DATE rejected.
#   - The query must be sensitive-free (pre-flight + inline DESCRIBE both).
#   - The contributing tables must not be flagged partial (data-trust.md F8).
#   - <name>.json must not already exist unless --re-record + --note.
#
# Goldens commit to git. API base URL is hashed in the path so raw URLs and
# tenant identifiers stay out of plaintext (rule #25).

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

re_record=0
note=""
db_override=""
positional=()
while (( $# )); do
  case "$1" in
    --re-record) re_record=1; shift ;;
    --note) note="$2"; shift 2 ;;
    --db)   db_override="$2"; shift 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

name="${1:-}"
sql="${2:-}"

if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: regression-record.sh <name> "<sql>" [--db <path>] [--re-record --note "<reason>"]' >&2
  exit 64
fi

# 0. Reject sensitive SQL outright.
if is_sensitive_query "$sql"; then
  scan="$(scan_sql_for_sensitivity "$sql")"
  summary="$(_sensitive_summary "$scan")"
  cat >&2 <<EOF
error: regression goldens must be sensitive-free.
  $summary
Goldens are committed to git; sensitive values can't go there.

Options:
  1. Restructure the golden to be aggregate-shaped on non-sensitive columns
     (SUM, COUNT, AVG GROUP BY non-sensitive cols).
  2. If you need a per-subject deterministic check, use compliance-query
     + export-results.sh — those write to .agents/sensitive/ (gitignored).
EOF
  exit 64
fi

# 1. Reject non-deterministic SQL
if grep -Eqi '\b(NOW|CURRENT_DATE|CURRENT_TIMESTAMP|CURRENT_TIME|LOCALTIMESTAMP|LOCALTIME|TODAY)\b' <<<"$sql"; then
  echo "error: SQL contains a non-deterministic time function (NOW/CURRENT_*)." >&2
  echo "Goldens must pin a fixed historical window. Replace with literal timestamps." >&2
  exit 64
fi

# 2. Require a closed historical window
has_between=0; has_lower=0; has_upper=0
grep -Eqi 'BETWEEN[[:space:]]+'\''[0-9]{4}-' <<<"$sql" && has_between=1
grep -Eq  '>=?[[:space:]]*'\''[0-9]{4}-'      <<<"$sql" && has_lower=1
grep -Eq  '<=?[[:space:]]*'\''[0-9]{4}-'      <<<"$sql" && has_upper=1
# DuckDB-typed literal style: TIMESTAMP '2025-01-01' or DATE '2025-01-01'
grep -Eq 'TIMESTAMP[[:space:]]+'\''[0-9]{4}-' <<<"$sql" && { has_lower=1; has_upper=1; }
grep -Eq 'DATE[[:space:]]+'\''[0-9]{4}-'      <<<"$sql" && { has_lower=1; has_upper=1; }
if (( has_between == 0 )) && { (( has_lower == 0 )) || (( has_upper == 0 )); }; then
  echo "error: SQL must pin a closed historical window." >&2
  echo "Use BETWEEN '<lo>' AND '<hi>' or both >= '<lo>' AND < '<hi>'." >&2
  exit 64
fi

command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }
db_path="${db_override:-$DUCKDB_PATH}"
[[ -f "$db_path" ]] || { echo "error: no DuckDB database at $db_path" >&2; exit 64; }

# 3. Refuse goldens against tables stamped partial (data-trust.md F8).
partial_tables="$(duckdb "$db_path" -noheader -list -c "
  SELECT table_name FROM duckdb_tables() WHERE comment LIKE '%partial=true%';
" 2>/dev/null || true)"
if [[ -n "$partial_tables" ]]; then
  for t in $partial_tables; do
    if grep -qE "\\b$t\\b" <<<"$sql"; then
      cat >&2 <<EOF
error: SQL references table '$t' which was loaded from a partial fetch (F8).
Goldens against partial tables are structurally meaningless — a slice was
missing at land time. Re-fetch the source completely before recording.
EOF
      exit 64
    fi
  done
fi

# 4. Compute target path. <api_base_hash> may be a single folder for single-API
# projects; preserved for portability to multi-source.
hash="$(api_base_hash)"
out_dir="$AGENTS_ROOT/regressions/$hash"
out="$out_dir/$name.json"

if [[ -e "$out" && $re_record -eq 0 ]]; then
  echo "error: $out already exists. To overwrite, pass --re-record --note \"<reason>\"." >&2
  exit 64
fi
if [[ $re_record -eq 1 && -z "$note" ]]; then
  echo "error: --re-record requires --note explaining the legitimate data change." >&2
  exit 64
fi

# 5. Inline DESCRIBE check before fetching rows.
DUCKDB_PATH="$db_path" pii_required_or_fail_inline "$sql" 0 "" "regression-record" 0

# 6. Run and capture
start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
result="$(duckdb "$db_path" -csv -c "$sql")"
end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

# JSON-safe encoding
escape_json() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'
}
j_sql="$(printf '%s' "$sql"    | escape_json)"
j_res="$(printf '%s' "$result" | escape_json)"
j_note="$(printf '%s' "$note"  | escape_json)"

mkdir -p "$out_dir"
cat > "$out" <<EOF
{
  "name": "$name",
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "captured_by": "agent",
  "api_base_hash": "$hash",
  "sql": $j_sql,
  "result": $j_res,
  "duration_ms": $ms,
  "re_recorded": $([[ $re_record -eq 1 ]] && echo true || echo false),
  "note": $j_note
}
EOF

_session_log "regression-record" "true" "$ms" "0"
_mixpanel_track "Regression Recorded" "tool=regression-record" \
  "golden_name=$name" "api_base_hash=$hash" \
  "re_recorded=$([[ $re_record -eq 1 ]] && echo true || echo false)" \
  "duration_ms=$ms"

echo "recorded: $out"
