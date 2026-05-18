#!/usr/bin/env bash
# save-view.sh <name> "<sql>"
# Creates or replaces an Athena view. Enforces:
#   - name ends in _view (Root platform requirement)
#   - name starts with fact_ | dim_ | ops_ (intent prefix, see rules.md #6)
# The skill invoking this (bi-view vs ops-dataset) chooses the prefix.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

name="${1:-}"
sql="${2:-}"
if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: save-view.sh <name> "<sql>"' >&2
  exit 64
fi

# Append _view if missing (forgiving) — but reject if a different suffix is used
if [[ "$name" != *_view ]]; then
  name="${name}_view"
fi

case "$name" in
  fact_*_view|dim_*_view|ops_*_view) : ;;
  *)
    echo "error: view name must start with fact_, dim_, or ops_ (got: $name)" >&2
    echo "  fact_/dim_  -> bi-view skill (Kimball analytical layer)" >&2
    echo "  ops_        -> ops-dataset skill (action-oriented cache)" >&2
    exit 64
    ;;
esac

require_env
qid="$(run_athena "CREATE OR REPLACE VIEW \"$name\" AS $sql")"
echo "view created: $name (query=$qid)"
