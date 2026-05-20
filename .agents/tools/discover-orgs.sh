#!/usr/bin/env bash
# discover-orgs.sh [--regions <comma-list>] | [--from-csv <path>]
#
# First-time / new-credentials helper. Emits a ready-to-paste .env to stdout.
# Two modes:
#
#  1. --from-csv <path>   (recommended when you already know your orgs)
#       Reads `org_id,bucket[,name]` rows (header row optional, lines starting
#       with `#` skipped) and assembles the .env without touching AWS. No
#       IAM permissions needed, no pagination concerns, deterministic.
#       Useful when you maintain an internal list of accessible orgs in a
#       spreadsheet or wiki.
#
#  2. --regions <comma-list>   (default: af-south-1,eu-west-2)
#       Probes `aws athena list-work-groups` in each region and reads each
#       workgroup's ResultConfiguration.OutputLocation to recover the bucket.
#       Requires athena:ListWorkGroups + athena:GetWorkGroup on each target.
#       Degrades to a partial .env if GetWorkGroup is denied — see the
#       degraded-mode block below.
#
# Output: stdout = .env block; stderr = principal, scan progress, distribution
# summary. Pipe to a file:
#
#   bash .agents/tools/discover-orgs.sh --from-csv orgs.csv > .env.suggested
#   diff -u .agents/.env .env.suggested   # review before swapping

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

regions="af-south-1,eu-west-2"
from_csv=""

while (( $# )); do
  case "$1" in
    --regions)  regions="${2:-}";  shift 2 ;;
    --from-csv) from_csv="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
usage: discover-orgs.sh [--regions <comma-list>] | [--from-csv <path>]

Emits a suggested .env block to stdout.

Modes:
  --from-csv <path>   Read org_id,bucket[,name] from a CSV. No AWS calls.
                      Header row optional; comment lines start with `#`.
  --regions <list>    Probe Athena workgroups (default: af-south-1,eu-west-2).
                      Requires athena:ListWorkGroups + athena:GetWorkGroup.

Pre-AWS-call requirements (probe mode only):
  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and Athena permissions above.
EOF
      exit 0
      ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)  echo "unexpected arg: $1" >&2; exit 64 ;;
  esac
done

if [[ -n "$from_csv" ]]; then
  if [[ ! -r "$from_csv" ]]; then
    echo "error: --from-csv path not readable: $from_csv" >&2
    exit 64
  fi
  echo "mode: csv ($from_csv)" >&2
else
  # Probe-mode pre-flight
  missing=()
  for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
    [[ -z "${!v:-}" ]] && missing+=("$v")
  done
  if (( ${#missing[@]} )); then
    printf 'error: missing required env vars: %s\n' "${missing[*]}" >&2
    exit 64
  fi
  command -v aws >/dev/null || { echo "error: aws CLI not on PATH" >&2; exit 64; }
fi

# Identity (informational — printed so the user can confirm they're using
# the multi-org-scoped key, not a single-org one).
# Identity (probe mode only — CSV mode skips the AWS call entirely)
identity_arn=""
identity_acct=""
if [[ -z "$from_csv" ]]; then
  if ! identity_json="$(aws sts get-caller-identity --output json 2>&1)"; then
    echo "error: aws sts get-caller-identity failed:" >&2
    echo "$identity_json" >&2
    exit 1
  fi
  identity_arn="$(printf '%s' "$identity_json" | sed -nE 's/.*"Arn": *"([^"]+)".*/\1/p')"
  identity_acct="$(printf '%s' "$identity_json" | sed -nE 's/.*"Account": *"([^"]+)".*/\1/p')"
  echo "principal: arn=$identity_arn account=$identity_acct" >&2
fi

uuid_re='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# Two ledgers: `records` for orgs where we got bucket+region (full discovery),
# `listed` for orgs we saw via list-work-groups but couldn't read config for
# (degraded — common when the IAM principal has ListWorkGroups but not
# GetWorkGroup). The script still emits useful output from `listed` alone.
records="$(mktemp)"
listed="$(mktemp)"
trap "rm -f '$records' '$listed'" EXIT

# CSV branch: populate `records` directly, then skip the AWS probe.
# Region is auto-detected per-bucket downstream (via _lib.sh:require_env), so
# CSV rows only need org_id + bucket. Optional 3rd column = friendly name
# (currently informational; not emitted in the .env to avoid PII drift).
if [[ -n "$from_csv" ]]; then
  csv_rows=0
  csv_skipped=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip CR (Windows line endings) and trim
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue   # comments
    # Header row detection: contains 'org_id' as a token
    if [[ "$line" == *org_id* ]]; then continue; fi

    # Parse first two CSV fields (org_id, bucket). Simple split on comma —
    # quoted-comma values are not supported (org_id is a UUID, bucket name
    # doesn't contain commas, so this is safe in practice).
    org_id="$(printf '%s' "$line" | awk -F, '{print $1}' | xargs)"
    bucket="$(printf '%s' "$line" | awk -F, '{print $2}' | xargs)"

    if [[ -z "$org_id" || -z "$bucket" ]]; then
      echo "  skip line (missing org_id or bucket): $(printf '%s' "$line" | cut -c1-80)" >&2
      csv_skipped=$((csv_skipped + 1))
      continue
    fi
    if ! [[ "$org_id" =~ $uuid_re ]]; then
      echo "  skip line (org_id not UUID-shaped): $org_id" >&2
      csv_skipped=$((csv_skipped + 1))
      continue
    fi

    # Region is auto-detected from the bucket downstream, so we record
    # "auto" as a placeholder here. Defaults/overrides logic groups by bucket
    # (not region) when region is "auto" for every row.
    printf '%s\t%s\t%s\n' "$org_id" "auto" "$bucket" >> "$records"
    printf '%s\t%s\n'     "$org_id" "auto"           >> "$listed"
    csv_rows=$((csv_rows + 1))
  done < "$from_csv"

  echo "csv: ingested $csv_rows row(s) ($csv_skipped skipped)" >&2
fi

# Skip the AWS probe block entirely in CSV mode.
if [[ -n "$from_csv" ]]; then
  region_list=()
else
  IFS=',' read -ra region_list <<<"$regions"
fi
for raw_region in "${region_list[@]+"${region_list[@]}"}"; do
  region="$(printf '%s' "$raw_region" | xargs)"
  [[ -z "$region" ]] && continue
  echo "scanning region=$region ..." >&2

  if ! wgs="$(aws athena list-work-groups --region "$region" \
              --query 'WorkGroups[].Name' --output text 2>&1)"; then
    echo "  list-work-groups failed: $(printf '%s' "$wgs" | tr '\n' ' ' | cut -c1-200)" >&2
    continue
  fi

  region_listed=0
  region_full=0
  for wg in $wgs; do
    [[ "$wg" =~ $uuid_re ]] || continue
    printf '%s\t%s\n' "$wg" "$region" >> "$listed"
    region_listed=$((region_listed + 1))

    if ! out_loc="$(aws athena get-work-group --region "$region" --work-group "$wg" \
                    --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' \
                    --output text 2>&1)"; then
      # Suppress per-org spam in the common AccessDenied case; we count
      # these and report a single summary line per region instead.
      continue
    fi
    if [[ "$out_loc" == "None" || -z "$out_loc" ]]; then
      continue
    fi
    bucket="$(printf '%s' "$out_loc" | sed -E 's|^s3://([^/]+)/.*|\1|; s|^s3://([^/]+)$|\1|')"
    if [[ -z "$bucket" || "$bucket" == "$out_loc" ]]; then
      continue
    fi
    printf '%s\t%s\t%s\n' "$wg" "$region" "$bucket" >> "$records"
    region_full=$((region_full + 1))
  done
  echo "  listed $region_listed org(s) in $region (bucket resolved for $region_full)" >&2
done

n_full="$(wc -l < "$records" | tr -d ' ')"
n_listed="$(wc -l < "$listed" | tr -d ' ')"

if (( n_listed == 0 )); then
  cat >&2 <<EOF
error: no orgs discovered in region(s)=$regions

Check:
  - Your IAM principal has athena:ListWorkGroups on the Athena service.
    Without this the probe sees nothing.
  - Some orgs may be in a region you didn't pass. Try
      discover-orgs.sh --regions <comma-list>
    with a wider set.
EOF
  exit 1
fi

# Degraded mode: we listed workgroups but couldn't read any bucket.
# Usually means athena:GetWorkGroup is denied on the principal's policies.
# Still emit a useful .env: full org list + bucket as TODO.
if (( n_full == 0 )); then
  cat >&2 <<EOF

note: listed $n_listed workgroup(s) but couldn't read bucket config for any
      (athena:GetWorkGroup denied). Emitting a partial .env with the org
      list and a TODO for ROOT_ATHENA_S3_BUCKET — look it up via the Root
      Dashboard for any one org (Data Adapter -> Generate Access Key).
EOF

  all_org_ids="$(awk -F'\t' '{print $1}' "$listed" | paste -sd, -)"

  echo "region distribution:" >&2
  awk -F'\t' '{print $2}' "$listed" | sort | uniq -c | sort -rn | sed 's/^/  /' >&2
  echo >&2

  cat <<EOF
# Suggested .env — generated by .agents/tools/discover-orgs.sh (PARTIAL)
# Listed $n_listed workgroup(s) via $identity_arn but could not read each
# workgroup's S3 bucket (athena:GetWorkGroup denied on this principal).
#
# To complete: open the Root Dashboard for any one org, go to Data Management ->
# Data Adapter -> Generate Access Key, copy the bucket name (without s3:// and
# without the trailing /<org-id>/) into ROOT_ATHENA_S3_BUCKET below. AWS_REGION
# is auto-detected from the bucket on first tool call.
#
# Workgroups by region:
EOF
  awk -F'\t' '{print "#   "$2"  "$1}' "$listed" | sort | sed 's/^/  /' || true

  cat <<EOF

AWS_ACCESS_KEY_ID="<your existing key id>"
AWS_SECRET_ACCESS_KEY="<your existing secret>"
ROOT_ATHENA_S3_BUCKET="<TODO: look up via Root Dashboard>"
ROOT_ENV="production"

# Full list of workgroups visible to this principal. Filter to the orgs you
# actually want to query — most users only need a subset.
ROOT_ORG_IDS="$all_org_ids"

# ROOT_ATHENA_S3_BUCKET_BY_ORG: add entries here if some orgs live in a
# different bucket than the default above.
EOF

  exit 0
fi

echo "discovered $n_full org(s) total with bucket info (out of $n_listed listed)" >&2
echo >&2
echo "region distribution:" >&2
awk -F'\t' '{print $2}' "$records" | sort | uniq -c | sort -rn | sed 's/^/  /' >&2
echo "bucket distribution:" >&2
awk -F'\t' '{print $3}' "$records" | sort | uniq -c | sort -rn | sed 's/^/  /' >&2
echo >&2

default_region="$(awk -F'\t' '{print $2}' "$records" | sort | uniq -c | sort -rn | head -1 | awk '{$1=""; sub(/^ /,""); print}')"
default_bucket="$(awk -F'\t' '{print $3}' "$records" | sort | uniq -c | sort -rn | head -1 | awk '{$1=""; sub(/^ /,""); print}')"

all_org_ids="$(awk -F'\t' '{print $1}' "$records" | paste -sd, -)"
region_overrides="$(awk -F'\t' -v def="$default_region" '$2 != def {print $1":"$2}' "$records" | paste -sd, -)"
bucket_overrides="$(awk -F'\t' -v def="$default_bucket" '$3 != def {print $1":"$3}' "$records" | paste -sd, -)"

# Emit suggested .env to stdout. AWS_REGION is intentionally omitted: the
# framework auto-detects it from ROOT_ATHENA_S3_BUCKET via aws s3api
# get-bucket-location (see _lib.sh:require_env). Per-org bucket overrides
# pick up the right region the same way, so AWS_REGION_BY_ORG is rarely
# needed — only emitted here when a region differs WITHOUT a bucket override,
# which doesn't happen in normal Data Adapter setups (buckets are region-locked).

if [[ -n "$from_csv" ]]; then
  source_line="from CSV $from_csv"
  region_note="AWS_REGION is auto-detected from each bucket via aws s3api get-bucket-location."
else
  source_line="via $identity_arn (account=$identity_acct)"
  region_note="Majority region is $default_region (auto-detected from the bucket above)."
fi

cat <<EOF
# Suggested .env — generated by .agents/tools/discover-orgs.sh
# Discovered $n_full org(s) $source_line
# Region/bucket defaults below are the majority; minority orgs go into the
# *_BY_ORG override maps. AWS_REGION is auto-detected from the bucket — only
# set it manually to override. Review before sourcing.

AWS_ACCESS_KEY_ID="<your existing key id>"
AWS_SECRET_ACCESS_KEY="<your existing secret>"
ROOT_ATHENA_S3_BUCKET="$default_bucket"
ROOT_ENV="production"

# $region_note
ROOT_ORG_IDS="$all_org_ids"
EOF

if [[ -n "$bucket_overrides" ]]; then
  echo "ROOT_ATHENA_S3_BUCKET_BY_ORG=\"$bucket_overrides\""
else
  echo "# ROOT_ATHENA_S3_BUCKET_BY_ORG: not needed (all orgs share $default_bucket)"
fi
# Suppress AWS_REGION_BY_ORG when every override-bucket org's region is
# already implied by its bucket. We only emit it for orgs whose region
# differs AND whose bucket is the default — a corner case worth flagging.
unexpected_region_overrides="$(awk -F'\t' -v def_r="$default_region" -v def_b="$default_bucket" '$2 != def_r && $3 == def_b {print $1":"$2}' "$records" | paste -sd, -)"
if [[ -n "$unexpected_region_overrides" ]]; then
  echo "AWS_REGION_BY_ORG=\"$unexpected_region_overrides\"   # unusual: same bucket, different region"
else
  echo "# AWS_REGION_BY_ORG: not needed (per-org regions follow per-org buckets via auto-detect)"
fi
