#!/usr/bin/env bash
# athena-unload.sh <name> "<sql>" [--format parquet|orc|json] [--compression snappy|gzip|none] [--partition-by col1,col2] [--re-unload]
#
# Wraps Athena's UNLOAD statement. Writes typed columnar output (default
# Parquet, snappy-compressed) to <workgroup-output-location>/unloads/<name>/
# (resolved at runtime via unload_prefix in _lib.sh), so downstream pipelines
# (Spark, dbt, Node/Python apps) can pull from S3.
#
# Refuses DDL keywords in the SQL — UNLOAD wraps SELECT only.
# Refuses overwrite without --re-unload — never silently overwrite a published artefact.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

format="parquet"
compression="snappy"
partition_by=""
re_unload=0
pii_required=0
reason=""
positional=()

while (( $# )); do
  case "$1" in
    --format)        format="$2";       shift 2 ;;
    --compression)   compression="$2";  shift 2 ;;
    --partition-by)  partition_by="$2"; shift 2 ;;
    --re-unload)     re_unload=1;       shift ;;
    --pii-required)  pii_required=1;    shift ;;
    --reason)        reason="$2";       shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

name="${1:-}"
sql="${2:-}"

if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: athena-unload.sh <name> "<sql>" [--format parquet|orc|json] [--compression snappy|gzip|none] [--partition-by col1,col2] [--re-unload]' >&2
  exit 64
fi

# Validate format
case "$format" in
  parquet|orc|json) : ;;
  *) echo "error: --format must be one of: parquet orc json (got: $format)" >&2; exit 64 ;;
esac

# Validate compression
case "$compression" in
  snappy|gzip|none) : ;;
  *) echo "error: --compression must be one of: snappy gzip none (got: $compression)" >&2; exit 64 ;;
esac

# Validate name (also becomes part of an S3 path)
if [[ ! "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "error: name must be lowercase alphanumeric with - or _ (got: $name)" >&2
  exit 64
fi

# Reject DDL/DML keywords — UNLOAD wraps SELECT only
if grep -Eqi '\b(CREATE|DROP|ALTER|INSERT|DELETE|UPDATE|GRANT|REVOKE|TRUNCATE)\b' <<<"$sql"; then
  echo "error: SQL contains DDL/DML keywords; athena-unload wraps SELECT only." >&2
  exit 64
fi

# PII firewall — rule #26. UNLOAD lands in S3 (not stdout), so this is
# write-with-explicit-acknowledgement rather than write-to-context. We still
# require --pii-required so the agent thinks twice before producing typed
# Parquet exports of PII at scale. Sensitive UNLOADs route to a separate
# 'sensitive/' subprefix for tighter S3 policy scoping.
pii_required_or_fail "$sql" "$pii_required" "$reason" "athena-unload" 0

require_env

# Check for existing unload prefix unless --re-unload
prefix="$(unload_prefix "$name")"

# Sensitive prefix for sensitive SQL
if is_sensitive_query "$sql"; then
  prefix="${prefix%/}/sensitive/"
fi
if (( re_unload == 0 )); then
  if aws s3 ls "$prefix" >/dev/null 2>&1; then
    echo "error: $prefix already exists. Pass --re-unload to overwrite." >&2
    exit 64
  fi
fi

# Compose WITH clause
with_parts=("format='$format'")
if [[ "$compression" != "none" ]]; then
  with_parts+=("compression='$compression'")
fi
if [[ -n "$partition_by" ]]; then
  # ARRAY['col1','col2']
  IFS=',' read -ra parts <<<"$partition_by"
  arr=""
  for c in "${parts[@]}"; do
    c="${c// /}"
    arr+="'$c',"
  done
  arr="${arr%,}"
  with_parts+=("partitioned_by=ARRAY[$arr]")
fi
with_clause="WITH ($(IFS=', '; echo "${with_parts[*]}"))"

unload_sql="UNLOAD ($sql) TO '$prefix' $with_clause"

qid="$(run_athena "$unload_sql")"

echo "unload complete: $prefix"
echo "query execution id: $qid"
