#!/usr/bin/env bash
# drop-view.sh [--force-canonical] <name>
# Drops an Athena view.
#
# By default, refuses to drop canonical fact_/dim_/ops_ views — they're
# shared production artefacts and a fat-fingered drop can take down a
# dashboard. Pass --force-canonical to override.
#
# scratch_*_view drops never need the flag — they're owned by whoever
# created them and intended to be ephemeral.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

force_canonical=0
if [[ "${1:-}" == "--force-canonical" ]]; then
  force_canonical=1
  shift
fi

name="${1:-}"
if [[ -z "$name" ]]; then
  echo 'usage: drop-view.sh [--force-canonical] <name>' >&2
  exit 64
fi

case "$name" in
  scratch_*_view)
    : # always allowed
    ;;
  fact_*_view|dim_*_view|ops_*_view)
    if (( ! force_canonical )); then
      cat >&2 <<EOF
error: $name is a canonical view (fact_/dim_/ops_).
Dropping a canonical view can break dashboards and downstream consumers.
If you're sure, rerun with --force-canonical:
  drop-view.sh --force-canonical $name
EOF
      exit 64
    fi
    ;;
  *_view)
    echo "warn: $name does not match a known tier prefix; proceeding anyway" >&2
    ;;
  *)
    echo "error: $name does not look like a view (must end in _view)" >&2
    exit 64
    ;;
esac

require_env
qid="$(run_athena "DROP VIEW IF EXISTS \"$name\"")"
echo "view dropped: $name (query=$qid)"
