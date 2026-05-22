#!/usr/bin/env bash
# list-views.sh [--tier bi|ops|scratch] [--ns <ns>] [--db <path>]
#
# Lists DuckDB views in main.duckdb, grouped by tier. scratch_<ns>_*_view
# entries are sub-grouped by namespace.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

filter_tier=""
filter_ns=""
db_override=""
while (( $# )); do
  case "$1" in
    --tier) filter_tier="${2:-}"; shift 2 ;;
    --ns)   filter_ns="${2:-}";   shift 2 ;;
    --db)   db_override="$2";     shift 2 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown flag: $1" >&2; exit 64 ;;
  esac
done

case "${filter_tier:-any}" in
  any|bi|ops|scratch) : ;;
  *) echo "error: --tier must be one of: bi, ops, scratch (got: $filter_tier)" >&2; exit 64 ;;
esac

command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }

db_path="${db_override:-$DUCKDB_PATH}"
[[ -f "$db_path" ]] || { echo "(no DuckDB database at $db_path)"; exit 0; }

names="$(duckdb "$db_path" -noheader -list -c "
  SELECT table_name FROM information_schema.tables
  WHERE table_type = 'VIEW' AND table_schema = 'main'
  ORDER BY table_name;
" 2>/dev/null || true)"

if [[ -z "$names" ]]; then
  echo "(no views in $db_path)"
  exit 0
fi

# Classify
classified="$(printf '%s\n' "$names" | awk '
{
  name = $0
  if (name ~ /^bi_.*_view$/)  { print "bi\t\t" name; next }
  if (name ~ /^ops_.*_view$/) { print "ops\t\t" name; next }
  if (name ~ /^scratch_[a-z0-9][a-z0-9-]*_.*_view$/) {
    rest = substr(name, 9)
    p = index(rest, "_")
    ns = substr(rest, 1, p-1)
    print "scratch\t" ns "\t" name
    next
  }
  print "other\t\t" name
}')"

if [[ -n "$filter_tier" ]]; then
  classified="$(printf '%s\n' "$classified" | awk -F'\t' -v t="$filter_tier" '$1==t')"
fi
if [[ -n "$filter_ns" ]]; then
  classified="$(printf '%s\n' "$classified" | awk -F'\t' -v n="$filter_ns" '$2==n')"
fi

if [[ -z "$classified" ]]; then
  echo "(no views match the filter)"
  exit 0
fi

for tier in bi ops scratch other; do
  rows="$(printf '%s\n' "$classified" | awk -F'\t' -v t="$tier" '$1==t')"
  [[ -z "$rows" ]] && continue
  case "$tier" in
    bi)      echo "# bi_*_view (analytical layer)" ;;
    ops)     echo "# ops_*_view (operational caches)" ;;
    scratch) echo "# scratch_*_view (exploratory, by namespace)" ;;
    other)   echo "# (unclassified — pre-convention views?)" ;;
  esac
  if [[ "$tier" == "scratch" ]]; then
    namespaces="$(printf '%s\n' "$rows" | awk -F'\t' '{print $2}' | sort -u)"
    while IFS= read -r ns; do
      [[ -z "$ns" ]] && continue
      echo "  [$ns]"
      printf '%s\n' "$rows" | awk -F'\t' -v n="$ns" '$2==n {print "    " $3}' | sort
    done <<< "$namespaces"
  else
    printf '%s\n' "$rows" | awk -F'\t' '{print "  " $3}' | sort
  fi
  echo
done

_session_log "list-views" "true" "0" "0"
