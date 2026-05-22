#!/usr/bin/env bash
# duckdb-describe.sh [<table>] [--db <path>]
#
# No <table>:  lists tables and views in the database (grouped: raw_/bi_/ops_/scratch_/other).
# With <table>: shows column names + types via PRAGMA table_info.
#
# Equivalent to athena-describe.sh / glue-describe.sh but for the local
# DuckDB database. Quick orientation skill — see skills/explore-schema.md.

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

db_path="${db_override:-$DUCKDB_PATH}"

if ! command -v duckdb >/dev/null; then
  echo "error: duckdb not on PATH" >&2
  exit 64
fi

if [[ ! -f "$db_path" ]]; then
  cat >&2 <<EOF
no DuckDB database at: $db_path

Land some data first:
  bash .agents/tools/fetch-api.sh <endpoint> --source <name> --entity <name>
  bash .agents/tools/land-to-duckdb.sh <entity> --source <name>
EOF
  exit 0
fi

table="${1:-}"

start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"

if [[ -z "$table" ]]; then
  # Group by name prefix
  duckdb -box "$db_path" -c "
    SELECT
      CASE
        WHEN table_name LIKE 'raw_%'     THEN 'raw'
        WHEN table_name LIKE 'bi_%'      THEN 'bi'
        WHEN table_name LIKE 'ops_%'     THEN 'ops'
        WHEN table_name LIKE 'scratch_%' THEN 'scratch'
        ELSE 'other'
      END AS tier,
      table_type AS type,
      table_name AS name
    FROM information_schema.tables
    WHERE table_schema = 'main'
    ORDER BY tier, name;
  "
else
  duckdb -box "$db_path" -c "PRAGMA table_info('$table');"
fi

end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

_session_log "duckdb-describe" "true" "$ms" "0"
_mixpanel_track "Exploration Started" "tool=duckdb-describe" "target=${table:-tables}"
