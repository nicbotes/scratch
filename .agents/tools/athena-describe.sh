#!/usr/bin/env bash
# athena-describe.sh             SHOW TABLES
# athena-describe.sh <table>     DESCRIBE <table>

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

if [[ -z "${1:-}" ]]; then
  qid="$(run_athena "SHOW TABLES")"
else
  qid="$(run_athena "DESCRIBE $1")"
fi
fetch_results "$qid"
