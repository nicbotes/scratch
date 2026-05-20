#!/usr/bin/env bash
# athena-query.sh "<sql>"                          run query, print CSV (capped)
# athena-query.sh --dry-run "<sql>"                EXPLAIN only
# athena-query.sh --format json   "<sql>"          one JSON array of row objects
# athena-query.sh --format jsonl  "<sql>"          one JSON object per line
# athena-query.sh --format tsv    "<sql>"          tab-separated values
# athena-query.sh --head N "<sql>"                 stream header + first N rows
# athena-query.sh --to-file <path> "<sql>"         write full result to file;
#                                                  stdout = "<path> rows=N bytes=B s3_uri=..."
# athena-query.sh --no-row-cap "<sql>"             print full result (use sparingly)
# echo "<sql>" | athena-query.sh                   accepts SQL on stdin
#
# Default behavior: if the query returns more than ROOT_AGENTS_MAX_ROWS rows
# (default 1000), the output is auto-truncated to the cap with a loud footer
# naming the escape valves. See rules.md #23.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

dry_run=0
format="csv"
head_n=""
to_file=""
no_row_cap=0

while (( $# )); do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
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
    *) break ;;
  esac
done

sql="${1:-}"
if [[ -z "$sql" ]]; then
  if [[ ! -t 0 ]]; then
    sql="$(cat)"
  else
    echo 'usage: athena-query.sh [--dry-run] [--format csv|json|jsonl|tsv] [--head N] [--to-file <path>] [--no-row-cap] "<sql>"' >&2
    exit 64
  fi
fi

if (( dry_run )); then
  qid="$(run_athena "EXPLAIN $sql")"
  fetch_results "$qid"
  exit 0
fi

qid="$(run_athena "$sql")"
total_rows="${LAST_QUERY_ROWS:-0}"

# Fetch the full CSV first (we always need it; Athena already wrote it to S3)
csv="$(fetch_results "$qid")"

# Format the CSV per --format (always operates on full data; truncation is a
# separate post-step keyed on rows)
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

# Athena S3 URI for the full result (always present, regardless of format choice)
s3_uri="$(aws athena get-query-execution --query-execution-id "$qid" \
  --output text --query 'QueryExecution.ResultConfiguration.OutputLocation' 2>/dev/null || echo "")"

# --to-file: write full result, stdout = locator only
if [[ -n "$to_file" ]]; then
  formatted="$(format_csv "$format" "$csv")"
  printf '%s\n' "$formatted" > "$to_file"
  bytes="$(wc -c < "$to_file" | tr -d ' ')"

  # Fallback row count: Athena's Statistics.OutputRows is null for queries whose
  # results are downloaded as CSV directly from S3 (not paginated via
  # GetQueryResults), so total_rows lies as 0 on non-empty files. Count the file
  # locally when that happens. Upstream fix tracked in
  # proposals/2026-05-20-data-adapter-feature-requests.md item #2; remove this
  # block once Statistics surfaces accurate counts.
  rows="$total_rows"
  if (( rows == 0 )) && (( bytes > 0 )) && [[ "$format" != "json" ]]; then
    file_lines="$(wc -l < "$to_file" | tr -d ' ')"
    (( file_lines > 0 )) && rows=$(( file_lines - 1 ))
  fi

  echo "$to_file rows=$rows bytes=$bytes s3_uri=$s3_uri"
  exit 0
fi

# Determine whether to truncate
truncate_to=""
truncated=0
cap="$ROOT_AGENTS_MAX_ROWS"

if [[ -n "$head_n" ]]; then
  truncate_to="$head_n"
  (( total_rows > head_n )) && truncated=1
elif (( no_row_cap )); then
  # Override: print everything, but warn loudly on stderr
  echo "warning: --no-row-cap on ${total_rows}-row result (~${LAST_QUERY_BYTES} scanned bytes); explain in your reply why this had to land in context" >&2
  _session_log_extra "athena-query" "row_cap_hit=true" "rows=$total_rows" "capped_at=0"
elif (( total_rows > cap )); then
  truncate_to="$cap"
  truncated=1
  _session_log_extra "athena-query" "row_cap_hit=true" "rows=$total_rows" "capped_at=$cap"
fi

if [[ -n "$truncate_to" ]]; then
  # Truncate the CSV to (header + truncate_to data rows)
  truncated_csv="$(printf '%s\n' "$csv" | awk -v n="$truncate_to" 'NR==1 {print; next} NR<=n+1 {print}')"
  format_csv "$format" "$truncated_csv"
  if (( truncated )); then
    cat >&2 <<EOF
... truncated at $truncate_to of $total_rows rows.
Full result: $s3_uri
Re-run with --to-file <path>, --head <N>, or --no-row-cap,
or route via export-results.sh / athena-unload.sh for typed output.
EOF
  fi
else
  format_csv "$format" "$csv"
fi
