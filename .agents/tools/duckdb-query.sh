#!/usr/bin/env bash
# duckdb-query.sh "<sql>" [--input <path-or-s3-uri>] [--format csv|json|jsonl|tsv]
#                         [--head N] [--to-file <path>] [--no-row-cap]
#
# Local SQL on CSV / Parquet / JSON files or S3 URIs. Pair with
# athena-query.sh --to-file or athena-unload.sh to pre-aggregate large
# result sets BEFORE they enter context. See rules.md #24 and
# skills/pre-aggregate.md.
#
# Honors the same row cap (rule #23) as athena-query.sh: default
# ROOT_AGENTS_MAX_ROWS=1000 to stdout, with --to-file / --head /
# --no-row-cap escape valves.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

input=""
format="csv"
head_n=""
to_file=""
no_row_cap=0
positional=()

while (( $# )); do
  case "$1" in
    --input)      input="$2";      shift 2 ;;
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
      if [[ -z "$to_file" ]]; then
        echo "error: --to-file expects a path" >&2
        exit 64
      fi
      shift 2
      ;;
    --no-row-cap) no_row_cap=1; shift ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

sql="${1:-}"
if [[ -z "$sql" ]]; then
  echo 'usage: duckdb-query.sh "<sql>" [--input <path-or-s3-uri>] [--format csv|json|jsonl|tsv] [--head N] [--to-file <path>] [--no-row-cap]' >&2
  exit 64
fi

# Dependency check before doing anything else.
if ! command -v duckdb >/dev/null; then
  cat >&2 <<'EOF'
error: duckdb not on PATH.

Install one of:
  brew install duckdb                      (macOS)
  curl https://install.duckdb.org | sh     (Linux/macOS)
  pip install duckdb                       (Python binding; CLI bundled)

duckdb-query.sh runs local SQL on files (CSV / Parquet / JSON) and S3 URIs.
See .agents/skills/pre-aggregate.md for the pull-aggregate-interpret flow.
EOF
  exit 64
fi

# S3 access: needs AWS creds + httpfs preamble. Trigger on either --input
# being an s3:// URI or the SQL containing an s3:// reference.
s3_preamble=""
needs_s3=0
[[ -n "$input" && "$input" == s3://* ]] && needs_s3=1
grep -qiE "'s3://" <<<"$sql" && needs_s3=1

if (( needs_s3 )); then
  require_env
  s3_preamble="INSTALL httpfs; LOAD httpfs; SET s3_region='$AWS_REGION'; SET s3_access_key_id='$AWS_ACCESS_KEY_ID'; SET s3_secret_access_key='$AWS_SECRET_ACCESS_KEY';"
fi

# If --input was passed and the SQL doesn't already reference it, wrap
# the user SQL as a CTE with the file aliased as `input`.
if [[ -n "$input" ]] && ! grep -qF "$input" <<<"$sql"; then
  sql="WITH input AS (SELECT * FROM '$input') $sql"
fi

full_sql="$s3_preamble $sql"
_debug "duckdb sql: $full_sql"

start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"

# Always emit CSV from DuckDB; format conversion is a post-step (same
# pattern as athena-query.sh).
csv="$(duckdb -csv -c "$full_sql" 2>&1)" || {
  echo "duckdb error:" >&2
  echo "$csv" >&2
  exit 1
}

end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

# Count rows (header excluded). Empty stdout means 0 rows.
if [[ -z "$csv" ]]; then
  total_rows=0
else
  total_rows=$(( $(printf '%s\n' "$csv" | wc -l) - 1 ))
  (( total_rows < 0 )) && total_rows=0
fi

format_csv() {
  local fmt="$1" data="$2"
  case "$fmt" in
    csv)
      printf '%s\n' "$data"
      ;;
    tsv)
      command -v python3 >/dev/null || { echo "error: --format tsv needs python3 on PATH" >&2; return 64; }
      printf '%s\n' "$data" | python3 -c '
import csv, sys
r = csv.reader(sys.stdin)
w = csv.writer(sys.stdout, delimiter="\t")
for row in r: w.writerow(row)
'
      ;;
    json|jsonl)
      command -v python3 >/dev/null || { echo "error: --format $fmt needs python3 on PATH" >&2; return 64; }
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

# Session log (one line per call)
dir="$AGENTS_ROOT/sessions"
mkdir -p "$dir"
sid="$(_session_id)"
printf '{"ts":"%s","session":"%s","tool":"duckdb-query","ok":true,"ms":%s,"rows":%s}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$ms" "$total_rows" \
  >> "$dir/$sid.jsonl"

_mixpanel_track "Local Processing Started" "tool=duckdb-query" \
  "rows=$total_rows" "ms=$ms" \
  "to_file=$([[ -n "$to_file" ]] && echo true || echo false)" \
  "format=$format"

# --to-file: write the formatted full result, stdout = locator only.
if [[ -n "$to_file" ]]; then
  formatted="$(format_csv "$format" "$csv")"
  printf '%s\n' "$formatted" > "$to_file"
  bytes="$(wc -c < "$to_file" | tr -d ' ')"
  echo "$to_file rows=$total_rows bytes=$bytes"
  exit 0
fi

# Truncation logic — mirrors athena-query.sh
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
