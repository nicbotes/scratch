#!/usr/bin/env bash
# regression-check.sh <name>
# regression-check.sh --all
# Re-runs each golden's SQL and asserts the result matches the recorded value.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

dir="$AGENTS_ROOT/regressions"

DIFF_CAP=50

print_capped() {
  local label="$1" body="$2"
  local total
  total="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
  echo "  $label:"
  printf '%s\n' "$body" | head -n "$DIFF_CAP" | sed 's/^/    /'
  if (( total > DIFF_CAP )); then
    echo "    ... truncated ($((total - DIFF_CAP)) more lines; see the full value in the regression JSON file)"
  fi
}

check_one() {
  local file="$1"
  local name; name="$(basename "$file" .json)"
  local sql expected
  sql="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sql"])' "$file")"
  expected="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$file")"

  local qid; qid="$(run_athena "$sql")"
  local actual; actual="$(fetch_results "$qid")"

  if [[ "$actual" == "$expected" ]]; then
    echo "OK   $name"
    return 0
  fi

  echo "FAIL $name (regression file: $file)"
  print_capped "expected" "$expected"
  print_capped "actual"   "$actual"
  return 1
}

if [[ "${1:-}" == "--all" ]]; then
  shopt -s nullglob
  files=("$dir"/*.json)
  if (( ${#files[@]} == 0 )); then
    echo "no regressions recorded in $dir"
    exit 0
  fi
  pass=0; fail=0
  for f in "${files[@]}"; do
    if check_one "$f"; then (( pass++ )); else (( fail++ )); fi
  done
  echo "---"
  echo "passed: $pass   failed: $fail"
  (( fail == 0 ))
  exit
fi

name="${1:-}"
if [[ -z "$name" ]]; then
  echo "usage: regression-check.sh <name> | --all" >&2
  exit 64
fi

file="$dir/$name.json"
if [[ ! -e "$file" ]]; then
  echo "error: no such golden: $file" >&2
  exit 64
fi
check_one "$file"
