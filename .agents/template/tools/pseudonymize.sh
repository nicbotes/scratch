#!/usr/bin/env bash
# pseudonymize.sh <input.csv> --columns col1,col2,... [--salt <key>] [--output <path>]
#
# Replaces values in named columns with deterministic SHA-256 truncated to
# 16 hex chars. Same value → same hash within the salt scope (joins preserved).
# Different salt scopes produce different hashes so cross-source joins don't
# accidentally line up.
#
# Default salt is api_base_hash($API_BASE_URL). Pass --salt explicitly to
# override (e.g. when joining datasets from two sources).
#
# Output: a new CSV with the named columns hash-replaced. Defaults to stdout;
# use --output <path> to write to a file. The named columns are renamed to
# <col>_hash so the consumer knows they're pseudonymised.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

input=""
columns=""
salt=""
output=""

while (( $# )); do
  case "$1" in
    --columns) columns="$2"; shift 2 ;;
    --salt)    salt="$2";    shift 2 ;;
    --output)  output="$2";  shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)
      if [[ -z "$input" ]]; then
        input="$1"
      else
        echo "error: only one input file allowed" >&2
        exit 64
      fi
      shift
      ;;
  esac
done

if [[ -z "$input" || -z "$columns" ]]; then
  echo 'usage: pseudonymize.sh <input.csv> --columns col1,col2,... [--salt <key>] [--output <path>]' >&2
  exit 64
fi
if [[ ! -f "$input" ]]; then
  echo "error: input not found: $input" >&2
  exit 64
fi

# Default salt: api_base_hash (same value → same hash within an API source)
if [[ -z "$salt" ]]; then
  if [[ -n "${API_BASE_URL:-}" ]]; then
    salt="$(api_base_hash)"
  else
    echo "error: no API_BASE_URL set and no --salt provided. Either set API_BASE_URL or pass --salt <key> explicitly." >&2
    exit 64
  fi
fi

command -v python3 >/dev/null || { echo "error: pseudonymize.sh needs python3 on PATH" >&2; exit 64; }

python3 - "$input" "$columns" "$salt" <<'EOF' > "${output:-/dev/stdout}"
import csv, hashlib, sys

input_path = sys.argv[1]
cols_to_hash = set(c.strip() for c in sys.argv[2].split(','))
salt = sys.argv[3]

def h(v):
    return hashlib.sha256((salt + ':' + v).encode('utf-8')).hexdigest()[:16]

with open(input_path) as f:
    reader = csv.reader(f)
    rows = list(reader)

if not rows:
    sys.exit(0)

header = rows[0]
hash_indices = []
new_header = []
for i, col in enumerate(header):
    if col in cols_to_hash:
        hash_indices.append(i)
        new_header.append(col + '_hash')
    else:
        new_header.append(col)

present = set(header)
missing = [c for c in cols_to_hash if c not in present]
if missing:
    sys.stderr.write(
        "error: requested columns not in input: " + ', '.join(missing) + "\n"
        "available columns: " + ', '.join(header) + "\n"
    )
    sys.exit(64)

writer = csv.writer(sys.stdout)
writer.writerow(new_header)
for row in rows[1:]:
    out = list(row)
    for i in hash_indices:
        if i < len(out) and out[i] != '':
            out[i] = h(out[i])
    writer.writerow(out)
EOF

if [[ -n "$output" ]]; then
  rows="$(($(wc -l < "$output") - 1))"
  bytes="$(wc -c < "$output" | tr -d ' ')"
  echo "$output rows=$rows bytes=$bytes (pseudonymised columns: $columns)" >&2
fi
