#!/usr/bin/env bash
# athena-query.sh "<sql>"                        run query, print CSV
# athena-query.sh --dry-run "<sql>"              EXPLAIN only, print scanned-bytes estimate
# athena-query.sh --format json   "<sql>"        emit a single JSON array of row objects
# athena-query.sh --format jsonl  "<sql>"        emit one JSON object per line
# athena-query.sh --format tsv    "<sql>"        emit tab-separated values
# echo "<sql>" | athena-query.sh                 accepts SQL on stdin

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

dry_run=0
format="csv"

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
    echo 'usage: athena-query.sh [--dry-run] [--format csv|json|jsonl|tsv] "<sql>"' >&2
    exit 64
  fi
fi

if (( dry_run )); then
  qid="$(run_athena "EXPLAIN $sql")"
  fetch_results "$qid"
  exit 0
fi

qid="$(run_athena "$sql")"
csv="$(fetch_results "$qid")"

case "$format" in
  csv)
    printf '%s\n' "$csv"
    ;;
  tsv)
    # Minimal CSV->TSV: assumes no embedded commas in quoted fields beyond standard Athena CSV.
    # For richer cases, use --format json and let the consumer convert.
    printf '%s\n' "$csv" | python3 -c '
import csv, sys
r = csv.reader(sys.stdin)
w = csv.writer(sys.stdout, delimiter="\t")
for row in r: w.writerow(row)
' 2>/dev/null || {
      echo "error: --format tsv needs python3 on PATH" >&2
      exit 64
    }
    ;;
  json|jsonl)
    command -v python3 >/dev/null || { echo "error: --format $format needs python3 on PATH" >&2; exit 64; }
    printf '%s\n' "$csv" | python3 -c "
import csv, json, sys
rows = list(csv.reader(sys.stdin))
if not rows:
    sys.exit(0)
header, *body = rows
records = [dict(zip(header, r)) for r in body]
if '$format' == 'json':
    json.dump(records, sys.stdout)
    sys.stdout.write('\n')
else:
    for rec in records:
        sys.stdout.write(json.dumps(rec) + '\n')
"
    ;;
esac
