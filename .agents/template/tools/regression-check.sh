#!/usr/bin/env bash
# regression-check.sh <name> [--db <path>]
# regression-check.sh --all  [--db <path>]
#
# Re-runs each golden's SQL against the current DuckDB and asserts the result
# matches what was recorded. Goldens live under
# .agents/regressions/<api_base_hash>/<name>.json so multiple APIs can coexist
# in one repo. --all iterates only the current API's subfolder.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

db_override=""
positional=()
while (( $# )); do
  case "$1" in
    --db) db_override="$2"; shift 2 ;;
    --all) positional+=("--all"); shift ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }
db_path="${db_override:-$DUCKDB_PATH}"

hash="$(api_base_hash)"
dir="$AGENTS_ROOT/regressions/$hash"

DIFF_CAP=50

print_capped() {
  local label="$1" body="$2"
  local total
  total="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
  echo "  $label:"
  printf '%s\n' "$body" | head -n "$DIFF_CAP" | sed 's/^/    /'
  if (( total > DIFF_CAP )); then
    echo "    ... truncated ($((total - DIFF_CAP)) more lines; see full value in the regression JSON)"
  fi
}

check_one() {
  local file="$1"
  local name; name="$(basename "$file" .json)"
  local sql expected
  sql="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sql"])' "$file")"
  expected="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"])' "$file")"

  local actual
  if ! actual="$(duckdb "$db_path" -csv -c "$sql" 2>&1)"; then
    echo "FAIL $name (sql error)"
    print_capped "error" "$actual"
    return 1
  fi

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
    echo "no regressions recorded for this API in $dir"
    exit 0
  fi
  pass=0; fail=0
  for f in "${files[@]}"; do
    if check_one "$f"; then (( pass++ )); else (( fail++ )); fi
  done
  echo "---"
  echo "passed: $pass   failed: $fail"
  _session_log "regression-check" "$([[ $fail -eq 0 ]] && echo true || echo false)" "0" "0"
  _mixpanel_track "Regression Checked" "scope=all" "passed=$pass" "failed=$fail" "api_base_hash=$hash"
  (( fail == 0 ))
  exit
fi

name="${1:-}"
if [[ -z "$name" ]]; then
  echo "usage: regression-check.sh <name> | --all [--db <path>]" >&2
  exit 64
fi

file="$dir/$name.json"
if [[ ! -e "$file" ]]; then
  echo "error: no such golden: $file" >&2
  echo "(goldens are scoped to this API; if you expected one from a different source," >&2
  echo "switch API_BASE_URL first.)" >&2
  exit 64
fi
check_one "$file" && passed=1 || passed=0
_session_log "regression-check" "$([[ $passed -eq 1 ]] && echo true || echo false)" "0" "0"
_mixpanel_track "Regression Checked" "scope=one" "golden_name=$name" "passed=$passed" "api_base_hash=$hash"
(( passed == 1 ))
