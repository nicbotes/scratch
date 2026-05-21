#!/usr/bin/env bash
# drop-view.sh [--force-canonical] [--db <path>] <name>
#
# Drops a DuckDB view. By default refuses to drop canonical bi_/ops_ views
# (they're shared analytical artefacts; an accidental drop breaks downstream
# work). Pass --force-canonical to override. scratch_*_view drops are always
# allowed.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

force_canonical=0
db_override=""
positional=()
while (( $# )); do
  case "$1" in
    --force-canonical) force_canonical=1; shift ;;
    --db) db_override="$2"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

name="${1:-}"
if [[ -z "$name" ]]; then
  echo 'usage: drop-view.sh [--force-canonical] [--db <path>] <name>' >&2
  exit 64
fi

case "$name" in
  scratch_*_view)
    : # always allowed
    ;;
  bi_*_view|ops_*_view)
    if (( ! force_canonical )); then
      cat >&2 <<EOF
error: $name is a canonical view (bi_/ops_).
Dropping a canonical view can break downstream work. If you're sure:
  drop-view.sh --force-canonical $name
EOF
      exit 64
    fi
    ;;
  *_view)
    echo "warn: $name does not match a known tier prefix; proceeding anyway" >&2
    ;;
  *)
    echo "error: $name does not look like a view (must end in _view)" >&2
    exit 64
    ;;
esac

command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }
db_path="${db_override:-$DUCKDB_PATH}"

duckdb "$db_path" -c "DROP VIEW IF EXISTS \"$name\";"
_session_log "drop-view" "true" "0" "0"
echo "view dropped: $name (db=$db_path)"
