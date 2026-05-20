#!/usr/bin/env bash
# cross-org-pull.sh
#
# Loop over $ROOT_ORG_IDS, run the same query per org via athena-query.sh,
# and load all per-org CSVs into one DuckDB database file as table `unified`,
# with `org_id` and `org_name` prepended as the first two columns.
#
# Usage:
#   cross-org-pull.sh --view <name>          [--out <path>] [--table <name>]
#   cross-org-pull.sh --sql  "<inline sql>"  [--out <path>] [--table <name>]
#   echo "<sql>" | cross-org-pull.sh         [--out <path>] [--table <name>]
#
# Defaults:
#   --out    .agents/cross-org/<UTC-ts>/unified.duckdb
#   --table  unified
#
# Behaviour:
#   - Reads $ROOT_ORG_IDS (comma-separated). Errors if unset.
#   - For each org: exports ROOT_ORG_ID, resolves org name via whoami.sh,
#     runs the query, writes per-org CSV alongside the .duckdb file.
#   - Orgs where the query fails (e.g. view missing in that org) are logged
#     to stderr and skipped; the run continues for the rest.
#   - Restores the original ROOT_ORG_ID on exit (trap).
#   - DuckDB ingest: first successful org creates `unified`; subsequent orgs
#     INSERT BY NAME with constant org_id / org_name columns. Schema drift
#     across orgs surfaces as a DuckDB error rather than silent NULL-fill.
#
# This is the per-org-views -> DuckDB-aggregation workflow described in
# skills/cross-org-explore.md. Rule #16: never use this for compliance.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

view_name=""
sql_inline=""
out_path=""
table_name="unified"

while (( $# )); do
  case "$1" in
    --view)  view_name="${2:-}"; shift 2 ;;
    --sql)   sql_inline="${2:-}"; shift 2 ;;
    --out)   out_path="${2:-}"; shift 2 ;;
    --table) table_name="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)
      if [[ -z "$sql_inline" ]]; then sql_inline="$1"; else
        echo "error: unexpected positional arg: $1" >&2; exit 64
      fi
      shift
      ;;
  esac
done

if [[ -z "$view_name" && -z "$sql_inline" && ! -t 0 ]]; then
  sql_inline="$(cat)"
fi

if [[ -z "$view_name" && -z "$sql_inline" ]]; then
  cat >&2 <<'EOF'
usage: cross-org-pull.sh --view <name>          [--out <path>] [--table <name>]
       cross-org-pull.sh --sql  "<inline sql>"  [--out <path>] [--table <name>]
       echo "<sql>" | cross-org-pull.sh         [--out <path>] [--table <name>]
EOF
  exit 64
fi

if [[ -n "$view_name" && -n "$sql_inline" ]]; then
  echo "error: pass --view OR --sql, not both" >&2
  exit 64
fi

if [[ -z "${ROOT_ORG_IDS:-}" ]]; then
  cat >&2 <<'EOF'
error: ROOT_ORG_IDS is unset.
Set it to a comma-separated list of org UUIDs your credentials can access:
  export ROOT_ORG_IDS="<uuid-1>,<uuid-2>,..."
Run list-orgs.sh to discover which orgs your credentials can see.
EOF
  exit 64
fi

if ! command -v duckdb >/dev/null; then
  cat >&2 <<'EOF'
error: duckdb not on PATH.
Install: brew install duckdb (macOS) or pip install duckdb.
EOF
  exit 64
fi

# Pre-flight: check the non-per-org env vars once so we fail fast with a single
# clear message rather than emitting an identical require_env error per org.
# AWS_REGION is intentionally omitted — _lib.sh:require_env auto-detects it
# from the (per-org) bucket via aws s3api get-bucket-location.
missing_env=()
for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY ROOT_ATHENA_S3_BUCKET; do
  [[ -z "${!v:-}" ]] && missing_env+=("$v")
done
if (( ${#missing_env[@]} )); then
  printf 'error: missing required env vars: %s\n' "${missing_env[*]}" >&2
  printf 'see %s/references/env-vars.md\n' "$AGENTS_ROOT" >&2
  exit 64
fi

if [[ -n "$view_name" ]]; then
  per_org_sql="SELECT * FROM \"$view_name\""
else
  per_org_sql="$sql_inline"
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
workspace_dir="$AGENTS_ROOT/cross-org/$ts"
mkdir -p "$workspace_dir"

if [[ -z "$out_path" ]]; then
  out_path="$workspace_dir/unified.duckdb"
fi
case "$out_path" in
  /*) : ;;
  *)  out_path="$(pwd)/$out_path" ;;
esac
mkdir -p "$(dirname "$out_path")"

if [[ -e "$out_path" ]]; then
  echo "error: $out_path already exists. Pick a different --out or remove the file." >&2
  exit 64
fi

original_org_id="${ROOT_ORG_ID:-}"
original_bucket="${ROOT_ATHENA_S3_BUCKET:-}"
original_region="${AWS_REGION:-}"
restore_env() {
  [[ -n "$original_org_id" ]] && export ROOT_ORG_ID="$original_org_id"
  [[ -n "$original_bucket" ]] && export ROOT_ATHENA_S3_BUCKET="$original_bucket"
  [[ -n "$original_region" ]] && export AWS_REGION="$original_region"
  return 0   # don't let an empty original_* leak a non-zero exit via the EXIT trap
}
trap restore_env EXIT

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

IFS=',' read -ra orgs <<<"$ROOT_ORG_IDS"
created=0
total_orgs=0
included_orgs=0
skipped_orgs=0

for raw_org in "${orgs[@]}"; do
  org="$(printf '%s' "$raw_org" | xargs)"
  [[ -z "$org" ]] && continue
  total_orgs=$((total_orgs + 1))

  export ROOT_ORG_ID="$org"

  # Per-org overrides for bucket and (rarely) region. Some orgs live in a
  # different S3 bucket than the default; ROOT_ATHENA_S3_BUCKET_BY_ORG carries
  # a "uuid:bucket,uuid:bucket" map consulted here. Region usually follows
  # the bucket automatically — _lib.sh:require_env auto-detects AWS_REGION
  # from the bucket's location when AWS_REGION is unset, so we unset it
  # between iterations to let that detection re-fire for the new bucket.
  if bucket_override="$(lookup_override "${ROOT_ATHENA_S3_BUCKET_BY_ORG:-}" "$org")"; then
    export ROOT_ATHENA_S3_BUCKET="$bucket_override"
  else
    export ROOT_ATHENA_S3_BUCKET="$original_bucket"
  fi
  if region_override="$(lookup_override "${AWS_REGION_BY_ORG:-}" "$org")"; then
    export AWS_REGION="$region_override"
  elif [[ -n "$original_region" ]]; then
    export AWS_REGION="$original_region"
  else
    unset AWS_REGION
  fi

  org_name=""
  if name_line="$(bash "$AGENTS_ROOT/tools/whoami.sh" 2>/dev/null | awk -F: '/^Org:/{sub(/^[[:space:]]+/,"",$2); print $2; exit}')"; then
    org_name="$name_line"
  fi

  per_org_csv="$workspace_dir/$org.csv"

  if ! err_out="$(bash "$AGENTS_ROOT/tools/athena-query.sh" --to-file "$per_org_csv" "$per_org_sql" 2>&1)"; then
    echo "skip org=$org name=\"$org_name\" reason=\"query failed: $(printf '%s' "$err_out" | tr '\n' ' ' | cut -c1-200)\"" >&2
    skipped_orgs=$((skipped_orgs + 1))
    continue
  fi

  org_esc="$(sql_escape "$org")"
  name_esc="$(sql_escape "$org_name")"
  csv_esc="$(sql_escape "$per_org_csv")"

  if (( created == 0 )); then
    duckdb_sql="CREATE TABLE \"$table_name\" AS SELECT '$org_esc' AS org_id, '$name_esc' AS org_name, * FROM read_csv_auto('$csv_esc', header=true);"
  else
    duckdb_sql="INSERT INTO \"$table_name\" BY NAME SELECT '$org_esc' AS org_id, '$name_esc' AS org_name, * FROM read_csv_auto('$csv_esc', header=true);"
  fi

  if ! duck_err="$(duckdb "$out_path" -c "$duckdb_sql" 2>&1)"; then
    echo "skip org=$org name=\"$org_name\" reason=\"duckdb ingest failed: $(printf '%s' "$duck_err" | tr '\n' ' ' | cut -c1-200)\"" >&2
    skipped_orgs=$((skipped_orgs + 1))
    continue
  fi

  if (( created == 0 )); then created=1; fi

  row_count="$(duckdb "$out_path" -csv -c "SELECT COUNT(*) FROM \"$table_name\" WHERE org_id = '$org_esc';" | tail -n 1)"
  bytes="$(wc -c < "$per_org_csv" | tr -d ' ')"
  echo "ok   org=$org name=\"$org_name\" rows=$row_count bytes=$bytes csv=$per_org_csv" >&2
  included_orgs=$((included_orgs + 1))
done

if (( created == 0 )); then
  echo "error: no org returned data. unified DuckDB file not created." >&2
  exit 1
fi

total_rows="$(duckdb "$out_path" -csv -c "SELECT COUNT(*) FROM \"$table_name\";" | tail -n 1)"
echo "$out_path table=$table_name orgs=$included_orgs/$total_orgs skipped=$skipped_orgs rows=$total_rows"
