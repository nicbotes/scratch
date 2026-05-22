#!/usr/bin/env bash
# duckdb-query.sh "<sql>" [--db <path>] [--input <path>] [--format csv|json|jsonl|tsv]
#                         [--head N] [--to-file <path>] [--no-row-cap]
#                         [--pii-required --reason "<text>"]
#
# Local SQL against the framework's DuckDB database (default
# .agents/data/db/main.duckdb). Pair with land-to-duckdb.sh to land API
# fetches first; see skills/land-data.md.
#
# Honors the row cap (rule #23) — default ROOT_AGENTS_MAX_ROWS=1000 to
# stdout, with --to-file / --head / --no-row-cap escape valves.
#
# Two-layer PII firewall: pre-flight regex against pii-columns.json, then
# (when --to-file is not used) an authoritative DuckDB DESCRIBE check before
# any row reaches stdout. See rules.md and skills/pii-safe-analysis.md.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

input=""
db_override=""
format="csv"
head_n=""
to_file=""
no_row_cap=0
pii_required=0
reason=""
positional=()

while (( $# )); do
  case "$1" in
    --input)         input="$2";        shift 2 ;;
    --db)            db_override="$2";  shift 2 ;;
    --format)
      format="${2:-}"
      case "$format" in
        csv|json|jsonl|tsv) : ;;
        *)
          echo "error: --format must be one of: csv json jsonl tsv (got: $format)" >&2
          exit 64
          ;;
      esac
      shift 2
      ;;
    --head)
      head_n="${2:-}"
      if ! [[ "$head_n" =~ ^[0-9]+$ ]] || (( head_n < 1 )); then
        echo "error: --head expects a positive integer (got: $head_n)" >&2
        exit 64
      fi
      shift 2
      ;;
    --to-file)
      to_file="${2:-}"
      [[ -z "$to_file" ]] && { echo "error: --to-file expects a path" >&2; exit 64; }
      shift 2
      ;;
    --no-row-cap)   no_row_cap=1; shift ;;
    --pii-required) pii_required=1; shift ;;
    --reason)       reason="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)  positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

sql="${1:-}"
if [[ -z "$sql" ]]; then
  cat >&2 <<'EOF'
usage: duckdb-query.sh "<sql>" [--db <path>] [--input <path>] [--format csv|json|jsonl|tsv]
                               [--head N] [--to-file <path>] [--no-row-cap]
                               [--pii-required --reason "<text>"]
EOF
  exit 64
fi

if ! command -v duckdb >/dev/null; then
  cat >&2 <<'EOF'
error: duckdb not on PATH.

Install one of:
  brew install duckdb                      (macOS)
  curl https://install.duckdb.org | sh     (Linux/macOS)
  pip install duckdb                       (Python binding; CLI bundled)
EOF
  exit 64
fi

# Resolve target DB. --db wins; else $DUCKDB_PATH (from _lib.sh).
db_path="${db_override:-$DUCKDB_PATH}"
mkdir -p "$(dirname "$db_path")"

# If --input was passed and the SQL doesn't already reference it, wrap as CTE
# aliased as `input`. (Handy for one-off file inspection without landing.)
if [[ -n "$input" ]] && ! grep -qF "$input" <<<"$sql"; then
  sql="WITH input AS (SELECT * FROM '$input') $sql"
fi

# Pre-flight PII firewall (regex against pii-columns.json).
override_ok=0
[[ -n "$to_file" ]] && override_ok=1
pii_required_or_fail "$sql" "$pii_required" "$reason" "duckdb-query" "$override_ok"

# Inline / authoritative firewall (DuckDB DESCRIBE) — skipped when --to-file
# alone is the override (result never reaches stdout) and when --pii-required
# was passed (gate already applied at pre-flight).
if [[ -z "$to_file" && $pii_required -eq 0 ]]; then
  DUCKDB_PATH="$db_path" pii_required_or_fail_inline "$sql" "$pii_required" "$reason" "duckdb-query" "$override_ok"
fi

_debug "duckdb db: $db_path"
_debug "duckdb sql: $sql"

start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"

csv="$(duckdb -csv "$db_path" -c "$sql" 2>&1)" || {
  echo "duckdb error:" >&2
  echo "$csv" >&2
  exit 1
}

end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

if [[ -z "$csv" ]]; then
  total_rows=0
else
  total_rows=$(( $(printf '%s\n' "$csv" | wc -l) - 1 ))
  (( total_rows < 0 )) && total_rows=0
fi

format_csv() {
  local fmt="$1" data="$2"
  case "$fmt" in
    csv) printf '%s\n' "$data" ;;
    tsv)
      printf '%s\n' "$data" | python3 -c '
import csv, sys
r = csv.reader(sys.stdin)
w = csv.writer(sys.stdout, delimiter="\t")
for row in r: w.writerow(row)
'
      ;;
    json|jsonl)
      printf '%s\n' "$data" | python3 -c "
import csv, json, sys
rows = list(csv.reader(sys.stdin))
if not rows:
    sys.exit(0)
header, *body = rows
records = [dict(zip(header, r)) for r in body]
if '$fmt' == 'json':
    json.dump(records, sys.stdout)
    sys.stdout.write('\n')
else:
    for rec in records:
        sys.stdout.write(json.dumps(rec) + '\n')
"
      ;;
  esac
}

# Session log + telemetry
_session_log "duckdb-query" "true" "$ms" "0"

# SQL hash so telemetry can spot repeated queries without leaking the text.
sql_hash="$(printf '%s' "$sql" | { command -v shasum >/dev/null && shasum -a 256 || sha256sum; } | cut -c1-16)"

_mixpanel_track "Query Run" "tool=duckdb-query" \
  "sql_hash=$sql_hash" "rows_returned=$total_rows" "ms=$ms" \
  "to_file=$([[ -n "$to_file" ]] && echo true || echo false)" \
  "format=$format"

# --to-file: write full result, stdout = locator only.
if [[ -n "$to_file" ]]; then
  formatted="$(format_csv "$format" "$csv")"
  printf '%s\n' "$formatted" > "$to_file"
  bytes="$(wc -c < "$to_file" | tr -d ' ')"
  echo "$to_file rows=$total_rows bytes=$bytes"
  exit 0
fi

# Truncation logic
truncate_to=""
truncated=0
cap="$ROOT_AGENTS_MAX_ROWS"

if [[ -n "$head_n" ]]; then
  truncate_to="$head_n"
  (( total_rows > head_n )) && truncated=1
elif (( no_row_cap )); then
  echo "warning: --no-row-cap on ${total_rows}-row result; explain in your reply why this had to land in context" >&2
  _session_log_extra "duckdb-query" "row_cap_hit=true" "rows=$total_rows" "capped_at=0"
elif (( total_rows > cap )); then
  truncate_to="$cap"
  truncated=1
  _session_log_extra "duckdb-query" "row_cap_hit=true" "rows=$total_rows" "capped_at=$cap"
fi

if [[ -n "$truncate_to" ]]; then
  truncated_csv="$(printf '%s\n' "$csv" | awk -v n="$truncate_to" 'NR==1 {print; next} NR<=n+1 {print}')"
  format_csv "$format" "$truncated_csv"
  if (( truncated )); then
    cat >&2 <<EOF
... truncated at $truncate_to of $total_rows rows.
Re-run with --to-file <path>, --head <N>, or --no-row-cap.
For larger summaries, narrow the GROUP BY or sample with TABLESAMPLE.
EOF
  fi
else
  format_csv "$format" "$csv"
fi
