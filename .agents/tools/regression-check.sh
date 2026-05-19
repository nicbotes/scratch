#!/usr/bin/env bash
# regression-check.sh <name>
# regression-check.sh --all
# Re-runs each golden's SQL and asserts the result matches the recorded value.
#
# Goldens are stored under .agents/regressions/<org_id_hash>/<name>.json so
# multiple orgs can coexist in one repo without collision. --all iterates
# only the current org's subfolder; other orgs' goldens are ignored.
# See rules.md #25.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

org_hash="$(hash_id "$ROOT_ORG_ID")"
dir="$AGENTS_ROOT/regressions/$org_hash"

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
    echo "no regressions recorded for this org in $dir"
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
  echo "(goldens are scoped to this org's hash; if you expected a cross-org check, switch ROOT_ORG_ID first)" >&2
  exit 64
fi
check_one "$file"
