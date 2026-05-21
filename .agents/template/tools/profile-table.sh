#!/usr/bin/env bash
# profile-table.sh <table> [--db <path>]
#
# Emits a profile block of a DuckDB table:
#  - row count
#  - max(updated_at) / max(created_at) for freshness (when present)
#  - column list + types
#  - partial-fetch flag (from the table comment set by land-to-duckdb.sh)
#
# Per rule #10: profile before non-trivial aggregation. See data-trust.md F2
# (stale snapshot) and F8 (partial fetch).

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

db_override=""
positional=()
while (( $# )); do
  case "$1" in
    --db) db_override="$2"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

table="${1:-}"
[[ -z "$table" ]] && { echo "usage: profile-table.sh <table> [--db <path>]" >&2; exit 64; }

command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }

db_path="${db_override:-$DUCKDB_PATH}"
[[ -f "$db_path" ]] || { echo "error: no DuckDB database at $db_path (land some data first)" >&2; exit 64; }

# Confirm the table exists
exists="$(duckdb "$db_path" -noheader -list -c "
  SELECT count(*) FROM information_schema.tables WHERE table_name = '$table';
" 2>/dev/null || echo 0)"
if [[ "$exists" != "1" ]]; then
  echo "error: table '$table' not in $db_path" >&2
  echo "Available:" >&2
  duckdb "$db_path" -box -c "SELECT table_name FROM information_schema.tables ORDER BY table_name;" >&2
  exit 64
fi

# Read the table comment (partial flag, loaded_from, mode)
comment="$(duckdb "$db_path" -noheader -list -c "
  SELECT coalesce(comment, '') FROM duckdb_tables() WHERE table_name = '$table';
" 2>/dev/null || echo "")"

# Columns
columns_table="$(duckdb "$db_path" -box -c "PRAGMA table_info('$table');")"
column_names="$(duckdb "$db_path" -noheader -list -c "
  SELECT lower(column_name) FROM information_schema.columns WHERE table_name = '$table';
")"

# Look for freshness columns
freshness_sql_parts=()
for col_lc in $column_names; do
  case "$col_lc" in
    updated_at|created_at|merged_at|closed_at|inserted_at|fetched_at|modified_at)
      freshness_sql_parts+=("MAX(\"$col_lc\") AS max_$col_lc")
      ;;
  esac
done

freshness_sql=""
if (( ${#freshness_sql_parts[@]} )); then
  freshness_sql="$(IFS=', '; echo "${freshness_sql_parts[*]}")"
fi

# Summary query
if [[ -n "$freshness_sql" ]]; then
  summary_sql="SELECT COUNT(*) AS row_count, $freshness_sql FROM \"$table\";"
else
  summary_sql="SELECT COUNT(*) AS row_count FROM \"$table\";"
fi

summary="$(duckdb "$db_path" -box -c "$summary_sql")"

start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"

echo "=== profile: $table ==="
[[ -n "$comment" ]] && echo "comment: $comment"
echo
echo "-- summary --"
echo "$summary"
echo
echo "-- columns --"
echo "$columns_table"
echo

if [[ "$comment" == *"partial=true"* ]]; then
  cat <<'EOF'
WARNING: this table was loaded from a partial fetch (data-trust.md F8).
Numbers computed against it are structurally incomplete, not just noisy.
regression-record.sh will refuse goldens; profile-table.sh surfaces the flag.
Re-run fetch-api.sh + land-to-duckdb.sh to refresh, or accept --allow-partial.
EOF
elif (( ${#freshness_sql_parts[@]} )); then
  echo "Note: freshness is the MAX(*) column(s) above. Re-fetch via the framework's"
  echo "fetch-api.sh + land-to-duckdb.sh to refresh; the DuckDB table is a snapshot."
else
  echo "Note: no recognised freshness column (no created_at/updated_at/etc.). State"
  echo "snapshot age from the manifest in data/raw/ when reporting numbers."
fi

end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

_session_log "profile-table" "true" "$ms" "0"
_mixpanel_track "Exploration Started" "tool=profile-table" "table=$table"
