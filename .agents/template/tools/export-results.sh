#!/usr/bin/env bash
# export-results.sh <name> "<sql>" [--db <path>] [--pii-required --reason "<why>"]
#
# Runs the SQL against DuckDB and persists CSV + manifest. Non-sensitive
# exports land under .agents/evidence/<utc-ts>-<name>/; sensitive exports
# land under .agents/sensitive/<utc-ts>-<name>/ (separately gitignored).
#
# The manifest captures api_base_hash, sql, row count, sha256 of the CSV,
# duration, and sensitivity tags so the export is verifiable independent of
# the session.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

pii_required=0
reason=""
db_override=""
positional=()

while (( $# )); do
  case "$1" in
    --pii-required) pii_required=1; shift ;;
    --reason)       reason="$2";    shift 2 ;;
    --db)           db_override="$2"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

name="${1:-}"
sql="${2:-}"
if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: export-results.sh <name> "<sql>" [--db <path>] [--pii-required --reason "<why>"]' >&2
  exit 64
fi

command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }
db_path="${db_override:-$DUCKDB_PATH}"
[[ -f "$db_path" ]] || { echo "error: no DuckDB database at $db_path" >&2; exit 64; }

# Pre-flight sensitivity scan
scan="$(scan_sql_for_sensitivity "$sql")"
contains_pii=false; contains_restricted=false; contains_json_sensitive=false
echo "$scan" | grep -q 'pii=[^ ]'            && contains_pii=true
echo "$scan" | grep -q 'restricted=[^ ]'     && contains_restricted=true
echo "$scan" | grep -q 'json_sensitive=[^ ]' && contains_json_sensitive=true

# PII firewall — writing to disk is the legitimate path for sensitive output,
# but --pii-required + reason is still required for auditability.
pii_required_or_fail "$sql" "$pii_required" "$reason" "export-results" 0

# Inline DESCRIBE check — augment the pre-flight with actual result columns.
DUCKDB_PATH="$db_path" inline_scan="$(check_executed_query_sensitivity_duckdb "$sql")"
echo "$inline_scan" | grep -q 'pii=[^ ]'            && contains_pii=true
echo "$inline_scan" | grep -q 'restricted=[^ ]'     && contains_restricted=true
echo "$inline_scan" | grep -q 'json_sensitive=[^ ]' && contains_json_sensitive=true

ts="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ "$contains_pii" == "true" || "$contains_restricted" == "true" || "$contains_json_sensitive" == "true" ]]; then
  dir="$AGENTS_ROOT/sensitive/$ts-$name"
else
  dir="$AGENTS_ROOT/evidence/$ts-$name"
fi
mkdir -p "$dir"

csv_path="$dir/results.csv"

start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
duckdb "$db_path" -csv -c "$sql" > "$csv_path"
end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

rows="$(($(wc -l < "$csv_path") - 1))"
(( rows < 0 )) && rows=0
sha="$( { command -v shasum >/dev/null && shasum -a 256 "$csv_path" || sha256sum "$csv_path"; } | awk '{print $1}')"
hash="$(api_base_hash)"

escape_json() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'
}
j_sql="$(printf '%s' "$sql"    | escape_json)"
j_reason="$(printf '%s' "$reason" | escape_json)"

cat > "$dir/manifest.json" <<EOF
{
  "name": "$name",
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "api_base_hash": "$hash",
  "row_count": $rows,
  "sha256": "$sha",
  "duration_ms": $ms,
  "contains_pii": $contains_pii,
  "contains_restricted": $contains_restricted,
  "contains_json_sensitive": $contains_json_sensitive,
  "pii_required_reason": $j_reason,
  "sql": $j_sql
}
EOF

_session_log "export-results" "true" "$ms" "0"

sensitive_flag=false
if [[ "$contains_pii" == "true" || "$contains_restricted" == "true" || "$contains_json_sensitive" == "true" ]]; then
  sensitive_flag=true
fi
_mixpanel_track "Results Exported" "tool=export-results" \
  "name=$name" "rows=$rows" "sensitive=$sensitive_flag" "duration_ms=$ms"

echo "$dir"
