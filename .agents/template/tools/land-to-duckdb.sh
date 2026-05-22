#!/usr/bin/env bash
# land-to-duckdb.sh <entity>
#   [--source <name>]                  # default: derived from --input parent dir
#   [--input <glob>]                   # default: data/raw/<source>/<entity>/*.jsonl
#   [--mode replace|append|upsert]     # default: replace
#   [--pk <id>]                        # required for upsert
#   [--db <path>]                      # default: $DUCKDB_PATH
#   [--allow-partial]                  # bypass refusal when manifest.complete=false
#   [--table <name>]                   # override default raw_<source>_<entity>
#
# Loads landed JSONL into a DuckDB table. Reads sibling .manifest.json and
# refuses to load partial fetches unless --allow-partial. See data-trust.md F8.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

entity=""
source_name=""
input_glob=""
mode="replace"
pk=""
db_override=""
allow_partial=0
table_override=""
positional=()

while (( $# )); do
  case "$1" in
    --source)         source_name="$2";      shift 2 ;;
    --input)          input_glob="$2";       shift 2 ;;
    --mode)           mode="$2";             shift 2 ;;
    --pk)             pk="$2";               shift 2 ;;
    --db)             db_override="$2";      shift 2 ;;
    --allow-partial)  allow_partial=1;       shift ;;
    --table)          table_override="$2";   shift 2 ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)  positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

entity="${1:-}"
[[ -z "$entity" ]] && { echo "usage: land-to-duckdb.sh <entity> [--source <name>] [--input <glob>] [--mode replace|append|upsert] [--pk <id>] [--db <path>] [--allow-partial] [--table <name>]" >&2; exit 64; }

command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }

# Resolve source
if [[ -z "$source_name" && -z "$input_glob" ]]; then
  echo "error: --source <name> required (or --input <glob>)" >&2; exit 64
fi

# Resolve input glob
if [[ -z "$input_glob" ]]; then
  input_glob="$AGENTS_ROOT/data/raw/$source_name/$entity/*.jsonl"
fi

# Pick the most-recent file (for --mode replace default) — and discover its manifest
shopt -s nullglob
files=( $input_glob )
shopt -u nullglob
if (( ${#files[@]} == 0 )); then
  echo "error: no files match: $input_glob" >&2
  exit 64
fi

# Sort and take the newest (bash-3-compatible negative-index)
IFS=$'\n' files=($(printf '%s\n' "${files[@]}" | sort))
unset IFS
latest_file="${files[$(( ${#files[@]} - 1 ))]}"
latest_manifest="${latest_file%.jsonl}.manifest.json"

# Partial-fetch guard
if [[ -f "$latest_manifest" ]]; then
  complete="$(python3 -c "import json,sys; print(json.load(open('$latest_manifest')).get('complete', True))")"
  if [[ "$complete" != "True" && "$complete" != "true" ]]; then
    if (( allow_partial == 0 )); then
      cat >&2 <<EOF
error: latest manifest reports complete=false (partial fetch — data-trust.md F8).
  manifest: $latest_manifest
  file:     $latest_file

Options:
  1. Re-fetch:                bash .agents/tools/fetch-api.sh <endpoint> ...
  2. Force-load anyway:       bash .agents/tools/land-to-duckdb.sh ... --allow-partial
     (the loaded table will be stamped with a partial=true comment;
     regression-record.sh will refuse to record goldens against it.)
EOF
      exit 64
    fi
    partial_loaded=true
  else
    partial_loaded=false
  fi
else
  partial_loaded=unknown
  echo "[land-to-duckdb] no manifest found alongside $latest_file (partial state unknown)" >&2
fi

# Resolve target db + table
db_path="${db_override:-$DUCKDB_PATH}"
mkdir -p "$(dirname "$db_path")"

if [[ -n "$table_override" ]]; then
  table="$table_override"
elif [[ -n "$source_name" ]]; then
  table="raw_${source_name}_${entity}"
else
  table="raw_${entity}"
fi

case "$mode" in
  replace|append|upsert) : ;;
  *) echo "error: --mode must be replace|append|upsert (got: $mode)" >&2; exit 64 ;;
esac
if [[ "$mode" == "upsert" && -z "$pk" ]]; then
  echo "error: --mode upsert requires --pk <column>" >&2; exit 64
fi

# Build SQL
# read_json_auto with format='newline_delimited' covers JSONL files.
# union_by_name=true tolerates evolving keys across pages.
read_expr="read_json_auto('$input_glob', format='newline_delimited', union_by_name=true)"

case "$mode" in
  replace)
    sql="CREATE OR REPLACE TABLE $table AS SELECT * FROM $read_expr;"
    ;;
  append)
    sql="CREATE TABLE IF NOT EXISTS $table AS SELECT * FROM $read_expr WHERE 1=0;
         INSERT INTO $table BY NAME SELECT * FROM $read_expr;"
    ;;
  upsert)
    sql="CREATE TABLE IF NOT EXISTS $table AS SELECT * FROM $read_expr WHERE 1=0;
         CREATE OR REPLACE TEMP TABLE _staging AS SELECT * FROM $read_expr;
         DELETE FROM $table WHERE $pk IN (SELECT $pk FROM _staging);
         INSERT INTO $table BY NAME SELECT * FROM _staging;
         DROP TABLE _staging;"
    ;;
esac

_debug "land sql: $sql"

start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
duckdb "$db_path" -c "$sql"
end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

# Stamp the partial flag as a table comment (so profile-table can surface it)
partial_lit="false"
[[ "$partial_loaded" == "true" ]] && partial_lit="true"
duckdb "$db_path" -c "COMMENT ON TABLE $table IS 'partial=$partial_lit;loaded_from=$input_glob;mode=$mode';"

# Row count summary
rows="$(duckdb "$db_path" -noheader -list -c "SELECT COUNT(*) FROM $table;")"
cols="$(duckdb "$db_path" -noheader -list -c "SELECT string_agg(column_name, ',') FROM information_schema.columns WHERE table_name = '$table';")"

_session_log "land-to-duckdb" "true" "$ms" "0"
_mixpanel_track "Data Landed" "tool=land-to-duckdb" \
  "source=${source_name:-unknown}" "entity=$entity" \
  "table=$table" "rows=$rows" "mode=$mode" "partial=$partial_lit"

cat <<EOF
table=$table rows=$rows partial=$partial_lit
columns: $cols
EOF
