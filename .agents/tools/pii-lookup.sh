#!/usr/bin/env bash
# pii-lookup.sh <table> <id-col>=<value> [--columns col1,col2,...] --reason "<why>"
#
# Fetches a specific record from a PII-bearing table. Writes the result to
# .agents/sensitive/<utc-ts>-lookup/lookup.csv and returns only the file path
# on stdout — the values never enter the agent's context unless the user
# explicitly opens the file.
#
# --reason is mandatory and logged in the session trace. Use cases:
#   - Drafting a personalised customer communication.
#   - Fulfilling a DSAR for a specific subject.
#   - Resolving a support ticket for an identified policyholder.
#
# For analytical work that aggregates over many PII rows, do NOT use this
# tool — use pseudonymize.sh + duckdb-query.sh instead so values never reach
# disk-readable form.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

table=""
id_expr=""
columns=""
reason=""
positional=()

while (( $# )); do
  case "$1" in
    --columns) columns="$2"; shift 2 ;;
    --reason)  reason="$2";  shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done

table="${positional[0]:-}"
id_expr="${positional[1]:-}"

if [[ -z "$table" || -z "$id_expr" || -z "$reason" ]]; then
  cat >&2 <<'EOF'
usage: pii-lookup.sh <table> <id-col>=<value> [--columns col1,col2,...] --reason "<why>"

Example:
  pii-lookup.sh policyholders policyholder_id=abc-123 --reason "DSAR-2026-Q2-014"
  pii-lookup.sh policyholders policyholder_id=abc-123 --columns first_name,email --reason "drafting outreach"

--reason is mandatory — it ends up in the compliance audit trail.
EOF
  exit 64
fi

# Validate the id expression: must be col=value, col only [a-z0-9_] and
# value not containing single quotes (avoid SQL injection in the SELECT).
if [[ ! "$id_expr" =~ ^[a-z][a-z0-9_]*=[^\'\"]+ ]]; then
  echo "error: id expression must be col=value, e.g. policyholder_id=abc-123" >&2
  exit 64
fi
id_col="${id_expr%%=*}"
id_value="${id_expr#*=}"

# Build the SELECT clause
if [[ -n "$columns" ]]; then
  # Validate column names
  IFS=',' read -ra col_arr <<<"$columns"
  for c in "${col_arr[@]}"; do
    c="${c// /}"
    if [[ ! "$c" =~ ^[a-z][a-z0-9_]*$ ]]; then
      echo "error: invalid column name: $c" >&2
      exit 64
    fi
  done
  select_clause="$columns"
else
  select_clause="*"
fi

# Validate table name
if [[ ! "$table" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "error: invalid table name: $table" >&2
  exit 64
fi

# Most org tables have environment; some don't. Default to including the filter.
# (Caller can pass a more specific id-value pair that already disambiguates.)
sql="SELECT $select_clause FROM $table WHERE $id_col = '$id_value' AND environment = '$ROOT_ENV' LIMIT 1"

require_env

ts="$(date -u +%Y%m%dT%H%M%SZ)"
dir="$AGENTS_ROOT/sensitive/$ts-lookup"
mkdir -p "$dir"

qid="$(run_athena "$sql")"
csv_path="$dir/lookup.csv"
fetch_results "$qid" > "$csv_path"
rows="$(($(wc -l < "$csv_path") - 1))"
(( rows < 0 )) && rows=0

# Manifest — no values, only metadata, sensitive flags, the reason
org_hash="$(hash_id "$ROOT_ORG_ID")"
escape_json() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))' 2>/dev/null \
    || printf '"%s"' "$(sed 's/\\/\\\\/g; s/"/\\"/g' <<<"$1")"
}
j_reason="$(printf '%s' "$reason" | escape_json)"

cat > "$dir/manifest.json" <<EOF
{
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tool": "pii-lookup",
  "table": "$table",
  "id_column": "$id_col",
  "columns": "${columns:-*}",
  "reason": $j_reason,
  "org_id_hash": "$org_hash",
  "env": "$ROOT_ENV",
  "query_execution_id": "$qid",
  "row_count": $rows
}
EOF

# Session log — include the requested columns so the audit trail records
# exactly which fields were fetched, not just "we did a lookup on table X".
_session_log_extra "pii-lookup" \
  "table=\"$table\"" \
  "id_col=\"$id_col\"" \
  "rows=$rows" \
  "reason=$j_reason" \
  "touched_columns=\"${columns:-*}\""

echo "$csv_path"
