#!/usr/bin/env bash
# Shared helpers for .agents/tools/*.sh
# Sourced, not executed.

set -euo pipefail

AGENTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AGENTS_ROOT

ROOT_ENV="${ROOT_ENV:-production}"
export ROOT_ENV

_session_id() {
  echo "${ROOT_AGENTS_SESSION_ID:-$(date -u +%Y-%m-%d)}"
}

_debug() {
  [[ "${ROOT_AGENTS_DEBUG:-0}" == "1" ]] || return 0
  printf '[debug] %s\n' "$*" >&2
}

require_env() {
  # Auto-detect AWS_REGION from the bucket when unset. Keeps the dashboard
  # setup at four values (key id, secret, org id, bucket) instead of five.
  # Each fresh shell pays one S3 call (~50ms); subsequent calls reuse the export.
  if [[ -z "${AWS_REGION:-}" && -n "${ROOT_ATHENA_S3_BUCKET:-}" \
        && -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    local detected
    detected="$(aws s3api get-bucket-location --bucket "$ROOT_ATHENA_S3_BUCKET" \
      --query 'LocationConstraint' --output text 2>/dev/null || true)"
    # us-east-1 returns "None" (legacy AWS quirk); also normalise empty.
    if [[ -z "$detected" || "$detected" == "None" ]]; then
      detected="us-east-1"
    fi
    export AWS_REGION="$detected"
    _debug "auto-detected AWS_REGION=$AWS_REGION from $ROOT_ATHENA_S3_BUCKET"
  fi

  local missing=()
  for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION ROOT_ORG_ID ROOT_ATHENA_S3_BUCKET; do
    if [[ -z "${!v:-}" ]]; then
      missing+=("$v")
    fi
  done
  if (( ${#missing[@]} )); then
    printf 'error: missing required env vars: %s\n' "${missing[*]}" >&2
    printf 'see %s/references/env-vars.md\n' "$AGENTS_ROOT" >&2
    exit 64
  fi
  command -v aws >/dev/null || { echo "error: aws CLI not on PATH" >&2; exit 64; }
}

output_location() {
  printf 's3://%s/%s/' "$ROOT_ATHENA_S3_BUCKET" "$ROOT_ORG_ID"
}

# unload_prefix <name>
# S3 prefix for an UNLOAD artefact named <name>. Derived from the workgroup's
# enforced ResultConfiguration.OutputLocation so it lands in a path the IAM
# identity can actually write to — different orgs use different segment
# schemes (e.g. <bucket>/<org>/ vs <bucket>/organizations/<org>/), and UNLOAD
# (unlike normal queries) doesn't get rewritten by the workgroup.
unload_prefix() {
  local name="$1"
  require_env
  local wg_out
  wg_out="$(aws athena get-work-group --work-group "$ROOT_ORG_ID" \
    --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' \
    --output text 2>/dev/null)"
  if [[ -z "$wg_out" || "$wg_out" == "None" ]]; then
    wg_out="$(output_location)"
  fi
  printf '%s/unloads/%s/' "${wg_out%/}" "$name"
}

# lookup_override <map> <key>
# Resolve a per-org override from a "k1:v1,k2:v2" map env var. Used by multi-org
# tools to switch ROOT_ATHENA_S3_BUCKET / AWS_REGION per iteration when some
# orgs live in a different bucket or region. Whitespace-tolerant; returns the
# value on stdout, or non-zero if the key isn't in the map.
lookup_override() {
  local map="$1" key="$2"
  [[ -z "$map" ]] && return 1
  local pair k v
  local -a pairs
  IFS=',' read -ra pairs <<<"$map"
  for pair in "${pairs[@]}"; do
    k="$(printf '%s' "${pair%%:*}" | xargs)"
    v="$(printf '%s' "${pair#*:}" | xargs)"
    if [[ "$k" == "$key" ]]; then
      printf '%s' "$v"
      return 0
    fi
  done
  return 1
}

# hash_id <value>
# Deterministic short hash for committed-artefact identifiers. Used to keep
# org_id (and similar) out of git plaintext while preserving per-org clustering
# (same org -> same hash -> same regressions/<hash>/ folder). 16 hex chars
# (64 bits) is plenty for collision resistance within a single team's golden set.
# See rules.md #25.
hash_id() {
  local value="$1"
  if command -v shasum >/dev/null; then
    printf '%s' "$value" | shasum -a 256 | cut -c1-16
  elif command -v sha256sum >/dev/null; then
    printf '%s' "$value" | sha256sum | cut -c1-16
  else
    echo "error: neither shasum nor sha256sum on PATH" >&2
    return 64
  fi
}

_session_log() {
  local tool="$1" ok="$2" ms="$3" bytes="${4:-0}"
  local dir="$AGENTS_ROOT/sessions"
  mkdir -p "$dir"
  local sid; sid="$(_session_id)"
  printf '{"ts":"%s","session":"%s","tool":"%s","ok":%s,"ms":%s,"bytes_scanned":%s,"org_id":"%s","env":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$tool" "$ok" "$ms" "$bytes" "$ROOT_ORG_ID" "$ROOT_ENV" \
    >> "$dir/$sid.jsonl"
}

# Context-size safety caps. Tools that print to stdout honour these.
ROOT_AGENTS_MAX_ROWS="${ROOT_AGENTS_MAX_ROWS:-1000}"
ROOT_AGENTS_MAX_BYTES="${ROOT_AGENTS_MAX_BYTES:-200000}"
export ROOT_AGENTS_MAX_ROWS ROOT_AGENTS_MAX_BYTES

# After run_athena succeeds, these are populated for the caller.
# LAST_QUERY_ID, LAST_QUERY_BYTES, LAST_QUERY_MS, LAST_QUERY_ROWS
LAST_QUERY_ID=""
LAST_QUERY_BYTES=0
LAST_QUERY_MS=0
LAST_QUERY_ROWS=0

# run_athena <sql>
# Echoes the QueryExecutionId on success. Polls until SUCCEEDED.
# Side effects:
#   - prints scanned bytes / time to stderr if ROOT_AGENTS_DEBUG=1
#   - populates LAST_QUERY_{ID,BYTES,MS,ROWS} globals
run_athena() {
  local sql="$1"
  require_env

  _debug "sql: $sql"
  _debug "aws athena start-query-execution --work-group $ROOT_ORG_ID --query-execution-context Database=$ROOT_ORG_ID --result-configuration OutputLocation=$(output_location)"

  local qid
  qid="$(aws athena start-query-execution \
    --query-string "$sql" \
    --work-group "$ROOT_ORG_ID" \
    --query-execution-context "Database=$ROOT_ORG_ID" \
    --result-configuration "OutputLocation=$(output_location)" \
    --output text --query 'QueryExecutionId')"

  _debug "query execution id: $qid"

  # Poll with backoff: 1s, 1s, 2s, 3s, 5s, 8s, 13s (Fibonacci-ish), max 60s
  local waits=(1 1 2 3 5 8 13 21 34 60)
  local i=0 state="" reason="" bytes=0 ms=0 rows=0
  while :; do
    local sleep_s="${waits[$i]:-60}"
    sleep "$sleep_s"
    local info
    info="$(aws athena get-query-execution --query-execution-id "$qid" \
      --output text \
      --query 'QueryExecution.[Status.State,Status.StateChangeReason,Statistics.DataScannedInBytes,Statistics.EngineExecutionTimeInMillis,Statistics.OutputRows]')"
    state="$(echo "$info" | awk '{print $1}')"
    reason="$(echo "$info" | cut -f2- | sed "s/^$state[[:space:]]*//")"
    # Tail of the line is: <bytes> <ms> <rows>
    bytes="$(echo "$info" | awk '{print $(NF-2)}')"
    ms="$(echo "$info"    | awk '{print $(NF-1)}')"
    rows="$(echo "$info"  | awk '{print $NF}')"
    # Normalise to 0 if Athena emitted "None"
    [[ "$bytes" == "None" ]] && bytes=0
    [[ "$ms"    == "None" ]] && ms=0
    [[ "$rows"  == "None" ]] && rows=0
    _debug "state=$state bytes=$bytes ms=$ms rows=$rows"
    case "$state" in
      SUCCEEDED) break ;;
      FAILED|CANCELLED)
        echo "athena query $state: $reason" >&2
        _session_log "run_athena" "false" "${ms:-0}" "${bytes:-0}"
        return 1
        ;;
    esac
    (( i++ ))
  done

  LAST_QUERY_ID="$qid"
  LAST_QUERY_BYTES="${bytes:-0}"
  LAST_QUERY_MS="${ms:-0}"
  LAST_QUERY_ROWS="${rows:-0}"

  _session_log "run_athena" "true" "${ms:-0}" "${bytes:-0}"
  printf '%s\n' "$qid"
}

# _session_log_extra <key=value> ... — append a one-off event row
# (e.g. row_cap_hit=true) to the session log without overwriting run_athena's
# regular log line.
_session_log_extra() {
  local tool="$1"; shift
  local dir="$AGENTS_ROOT/sessions"
  mkdir -p "$dir"
  local sid; sid="$(_session_id)"
  local extra=""
  for kv in "$@"; do
    local k="${kv%%=*}" v="${kv#*=}"
    extra+=",\"$k\":$v"
  done
  printf '{"ts":"%s","session":"%s","tool":"%s"%s,"org_id":"%s","env":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$tool" "$extra" "$ROOT_ORG_ID" "$ROOT_ENV" \
    >> "$dir/$sid.jsonl"
}

# fetch_results <query-execution-id>
# Prints results as CSV on stdout. Pulls from S3 for large result sets.
fetch_results() {
  local qid="$1"
  require_env
  # Try get-query-results first (capped at 1000 rows per page); fall back to S3 copy
  local out_uri
  out_uri="$(aws athena get-query-execution --query-execution-id "$qid" \
    --output text --query 'QueryExecution.ResultConfiguration.OutputLocation')"
  _debug "result s3 uri: $out_uri"
  aws s3 cp "$out_uri" - 2>/dev/null
}
