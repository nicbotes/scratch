#!/usr/bin/env bash
# glue-describe.sh                              list all tables in the org's Glue database
# glue-describe.sh <table>                      list columns + types for one table
# glue-describe.sh --columns <table>            same as above, machine-readable (tab-separated)
# glue-describe.sh --has-column <table> <col>   exit 0 if column exists, 1 if not (silent)
# glue-describe.sh --schema-md                  emit a fresh references/schema.md skeleton
#
# Reads from the AWS Glue metastore directly — no Athena query, no bytes
# scanned. The metastore is the source of truth that Athena's
# information_schema.columns view wraps. Use this in preference to
# `athena-query.sh "SELECT ... FROM information_schema.columns"`.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

mode="list"
table=""
column=""

while (( $# )); do
  case "$1" in
    --columns) mode="columns"; table="${2:-}"; shift 2 ;;
    --has-column) mode="has-column"; table="${2:-}"; column="${3:-}"; shift 3 ;;
    --schema-md) mode="schema-md"; shift ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)
      if [[ -z "$table" ]]; then
        table="$1"; mode="describe"
      fi
      shift
      ;;
  esac
done

case "$mode" in
  list)
    aws glue get-tables --database-name "$ROOT_ORG_ID" \
      --query 'TableList[].Name' --output text | tr '\t' '\n' | sort
    ;;

  describe|columns)
    if [[ -z "$table" ]]; then
      echo "usage: glue-describe.sh [--columns] <table>" >&2; exit 64
    fi
    if [[ "$mode" == "describe" ]]; then
      echo "=== $table (org=$ROOT_ORG_ID) ==="
    fi
    aws glue get-table --database-name "$ROOT_ORG_ID" --name "$table" \
      --query 'Table.StorageDescriptor.Columns[].[Name,Type]' \
      --output text
    ;;

  has-column)
    if [[ -z "$table" || -z "$column" ]]; then
      echo "usage: glue-describe.sh --has-column <table> <column>" >&2; exit 64
    fi
    aws glue get-table --database-name "$ROOT_ORG_ID" --name "$table" \
      --query "Table.StorageDescriptor.Columns[?Name=='$column'].Name" \
      --output text | grep -q . && exit 0 || exit 1
    ;;

  schema-md)
    # Emit a markdown skeleton suitable as a diff anchor against the
    # human-curated references/schema.md (PII tags, JSONB hints, etc. live
    # there and are not regenerable from the metastore).
    echo "# Reference: Athena Schema — Full Data Dictionary"
    echo
    echo "Generated from AWS Glue metastore on $(date -u +%Y-%m-%d)."
    echo "Refresh skeleton with: \`bash .agents/tools/glue-describe.sh --schema-md > /tmp/schema.md.new\`"
    echo
    aws glue get-tables --database-name "$ROOT_ORG_ID" \
      --query 'TableList[].[Name]' --output text | tr '\t' '\n' | sort | while read -r t; do
      [[ -z "$t" ]] && continue
      echo "### \`$t\`"
      echo
      echo "| Column | Type |"
      echo "|---|---|"
      aws glue get-table --database-name "$ROOT_ORG_ID" --name "$t" \
        --query 'Table.StorageDescriptor.Columns[].[Name,Type]' --output text \
        | awk -F'\t' '{printf "| `%s` | %s |\n", $1, $2}'
      echo
    done
    ;;
esac
