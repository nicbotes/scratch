#!/usr/bin/env bash
# list-views.sh [--tier <fact|dim|ops|scratch>] [--ns <ns>]
# Lists Athena views in the current org's database ($ROOT_ORG_ID), grouped
# by tier. scratch_<ns>_*_view entries are sub-grouped by namespace so you
# can see at a glance who created what.
#
# Examples:
#   list-views.sh                       # all views, grouped by tier
#   list-views.sh --tier scratch        # only scratch views
#   list-views.sh --tier scratch --ns nic
#   list-views.sh --ns agents-example-use

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

filter_tier=""
filter_ns=""
while (( $# )); do
  case "$1" in
    --tier)
      filter_tier="${2:-}"
      shift 2
      ;;
    --ns)
      filter_ns="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown flag: $1" >&2
      exit 64
      ;;
  esac
done

case "${filter_tier:-any}" in
  any|fact|dim|ops|scratch) : ;;
  *)
    echo "error: --tier must be one of: fact, dim, ops, scratch (got: $filter_tier)" >&2
    exit 64
    ;;
esac

require_env

qid="$(run_athena "SHOW VIEWS IN \"$ROOT_ORG_ID\"")"
raw="$(fetch_results "$qid")"

# fetch_results returns CSV with a header row. Strip it, strip CRs, drop blanks.
names="$(printf '%s\n' "$raw" \
  | tr -d '\r' \
  | tail -n +2 \
  | sed -E 's/^"(.*)"$/\1/' \
  | grep -v '^$' || true)"

if [[ -z "$names" ]]; then
  echo "(no views in database $ROOT_ORG_ID)"
  exit 0
fi

# Build a tab-separated stream: <tier>\t<ns>\t<name>
# - fact_*_view  -> tier=fact, ns=""
# - dim_*_view   -> tier=dim,  ns=""
# - ops_*_view   -> tier=ops,  ns=""
# - scratch_<ns>_<body>_view -> tier=scratch, ns=<ns>  (ns = first _-token, since slug forbids _)
# - anything else -> tier=other, ns=""
classified="$(printf '%s\n' "$names" | awk -F'\t' '
{
  name = $0
  if (name ~ /^fact_.*_view$/)    { print "fact\t\t" name; next }
  if (name ~ /^dim_.*_view$/)     { print "dim\t\t" name; next }
  if (name ~ /^ops_.*_view$/)     { print "ops\t\t" name; next }
  if (name ~ /^scratch_[a-z0-9][a-z0-9-]*_.*_view$/) {
    rest = substr(name, 9)            # strip "scratch_"
    p = index(rest, "_")
    ns = substr(rest, 1, p-1)
    print "scratch\t" ns "\t" name
    next
  }
  print "other\t\t" name
}')"

# Apply filters
if [[ -n "$filter_tier" ]]; then
  classified="$(printf '%s\n' "$classified" | awk -F'\t' -v t="$filter_tier" '$1==t')"
fi
if [[ -n "$filter_ns" ]]; then
  classified="$(printf '%s\n' "$classified" | awk -F'\t' -v n="$filter_ns" '$2==n')"
fi

if [[ -z "$classified" ]]; then
  echo "(no views match the filter)"
  exit 0
fi

# Print, grouped by tier (then by ns for scratch).
for tier in fact dim ops scratch other; do
  rows="$(printf '%s\n' "$classified" | awk -F'\t' -v t="$tier" '$1==t')"
  [[ -z "$rows" ]] && continue
  case "$tier" in
    fact)    echo "# fact_*_view  (Kimball facts)" ;;
    dim)     echo "# dim_*_view   (Kimball dimensions)" ;;
    ops)     echo "# ops_*_view   (operational caches)" ;;
    scratch) echo "# scratch_*_view (exploratory, by namespace)" ;;
    other)   echo "# (unclassified — pre-convention views?)" ;;
  esac
  if [[ "$tier" == "scratch" ]]; then
    # sub-group by ns
    namespaces="$(printf '%s\n' "$rows" | awk -F'\t' '{print $2}' | sort -u)"
    while IFS= read -r ns; do
      [[ -z "$ns" ]] && continue
      echo "  [$ns]"
      printf '%s\n' "$rows" | awk -F'\t' -v n="$ns" '$2==n {print "    " $3}' | sort
    done <<< "$namespaces"
  else
    printf '%s\n' "$rows" | awk -F'\t' '{print "  " $3}' | sort
  fi
  echo
done
