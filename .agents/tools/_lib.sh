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

  # Fail-fast on empty/None qid. Command substitution doesn't trip `set -e`,
  # so a SQL syntax error (or unauthorised workgroup) silently produces an
  # empty qid and the polling loop below would otherwise call
  # get-query-execution with --query-execution-id "" forever.
  if [[ -z "$qid" || "$qid" == "None" ]]; then
    echo "athena start-query-execution returned no QueryExecutionId — usually a SQL syntax error or unauthorised database/workgroup" >&2
    _session_log "run_athena" "false" "0" "0"
    return 1
  fi

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

# ----------------------------------------------------------------------------
# PII safety boundary — rules #26, #27, #28
#
# scan_sql_for_sensitivity <sql>
#   Inspects SQL for sensitive column references against
#   .agents/references/pii-columns.json. Prints a single line:
#     pii=col1,col2 restricted=col3 json_sensitive=col4 json_paths=mod.path1
#   Empty fields are omitted. Conservative: regex-based, false-positives over
#   false-negatives. The agent that hits a false positive can pass
#   --pii-required "<reason>" to proceed.
#
# is_sensitive_query <sql>
#   Returns 0 if the SQL touches any sensitive column, 1 otherwise.
#
# pii_required_or_fail <sql> <pii_required_flag> <reason> <tool> <override_ok>
#   The shared gate. If the SQL is sensitive and --pii-required wasn't passed,
#   prints a clear error and exits 64. If --pii-required was passed with a
#   reason, logs it to the session and returns 0. <override_ok> = 1 lets
#   --to-file alone serve as the override in 'standard' mode.
#
# pii_posture_block
#   Echoes the appropriate posture banner for the current
#   ROOT_AGENTS_COMPLIANCE_MODE. Tools call it once per invocation in 'off'
#   mode (to remind the user dev mode is on).

ROOT_AGENTS_COMPLIANCE_MODE="${ROOT_AGENTS_COMPLIANCE_MODE:-strict}"
export ROOT_AGENTS_COMPLIANCE_MODE

PII_META_PATH="$AGENTS_ROOT/references/pii-columns.json"

scan_sql_for_sensitivity() {
  local sql="$1"
  if [[ ! -f "$PII_META_PATH" ]]; then
    # No metadata loaded — fail safe (treat nothing as sensitive). Caller
    # decides whether to refuse the operation; we don't want a missing
    # metadata file to be a silent kill switch on the whole framework.
    echo "pii= restricted= json_sensitive= json_paths="
    return 0
  fi
  command -v python3 >/dev/null || {
    echo "error: PII scan needs python3 on PATH" >&2
    return 64
  }
  python3 - "$PII_META_PATH" <<EOF
import json, re, sys

meta_path = sys.argv[1]
sql = """$(printf '%s' "$sql" | sed 's/\\/\\\\/g; s/"/\\"/g')"""

with open(meta_path) as f:
    meta = json.load(f)

# Strip out string literals so we don't match column names inside 'foo' strings.
# Conservative — just strip single-quoted literals.
scrubbed = re.sub(r"'(?:[^'\\\\]|\\\\.)*'", "''", sql)
scrubbed_lower = scrubbed.lower()

# Strip out -- and /* */ comments
scrubbed_lower = re.sub(r'--[^\n]*', '', scrubbed_lower)
scrubbed_lower = re.sub(r'/\*.*?\*/', '', scrubbed_lower, flags=re.DOTALL)

pii_cols = set()
restricted_cols = set()
json_sensitive_cols = set()
json_paths = set()

# Build a set of all column names we care about, keyed by lowercased name
# (Athena columns are case-insensitive in practice).
all_cols = {}  # col_lower -> sensitivity
for tbl, tbl_meta in meta["tables"].items():
    for col, col_meta in tbl_meta.get("columns", {}).items():
        sens = col_meta.get("sensitivity")
        if sens:
            # If the column is in multiple tables with different sensitivity,
            # the stricter wins (pii > restricted > json_sensitive).
            existing = all_cols.get(col.lower())
            rank = {"pii": 3, "restricted": 2, "json_sensitive": 1}
            if existing is None or rank.get(sens, 0) > rank.get(existing, 0):
                all_cols[col.lower()] = sens

# Token-level match against the scrubbed SQL. Conservative — any standalone
# occurrence of a sensitive column name counts.
for col, sens in all_cols.items():
    if re.search(r'\b' + re.escape(col) + r'\b', scrubbed_lower):
        if sens == "pii":
            pii_cols.add(col)
        elif sens == "restricted":
            restricted_cols.add(col)
        elif sens == "json_sensitive":
            json_sensitive_cols.add(col)

# Extract JSON paths for tagged json_sensitive columns.
# Pattern: JSON_EXTRACT[_SCALAR]?\s*\(\s*<col>\s*,\s*'<path>'
for col in list(json_sensitive_cols):
    pat = re.compile(
        r"json_extract(?:_scalar)?\s*\(\s*" + re.escape(col) +
        r"\s*,\s*'([^']+)'",
        re.IGNORECASE,
    )
    for m in pat.finditer(sql):
        json_paths.add(col + ":" + m.group(1))

def fmt(s):
    return ",".join(sorted(s))

print(
    f"pii={fmt(pii_cols)} "
    f"restricted={fmt(restricted_cols)} "
    f"json_sensitive={fmt(json_sensitive_cols)} "
    f"json_paths={fmt(json_paths)}"
)
EOF
}

is_sensitive_query() {
  local sql="$1"
  local scan; scan="$(scan_sql_for_sensitivity "$sql")"
  # Sensitive if any of the four buckets has content.
  echo "$scan" | grep -Eq '(pii|restricted|json_sensitive|json_paths)=[^ ]+' && return 0
  return 1
}

_sensitive_summary() {
  # Convert scan output into a human-readable line.
  local scan="$1"
  local out=""
  local pii restricted json_sens json_paths
  pii="$(echo "$scan" | grep -oE 'pii=[^ ]*' | cut -d= -f2-)"
  restricted="$(echo "$scan" | grep -oE 'restricted=[^ ]*' | cut -d= -f2-)"
  json_sens="$(echo "$scan" | grep -oE 'json_sensitive=[^ ]*' | cut -d= -f2-)"
  json_paths="$(echo "$scan" | grep -oE 'json_paths=[^ ]*' | cut -d= -f2-)"
  [[ -n "$pii" ]]        && out+="PII columns: $pii. "
  [[ -n "$restricted" ]] && out+="Restricted columns: $restricted. "
  [[ -n "$json_sens" ]]  && out+="JSON-sensitive columns: $json_sens. "
  [[ -n "$json_paths" ]] && out+="JSON paths touched: $json_paths. "
  printf '%s' "$out"
}

# pii_required_or_fail <sql> <pii_required_flag> <reason> <tool> <override_ok>
#   override_ok = 1 → in 'standard' mode, --to-file alone serves as override
#                     (caller passes 1 when --to-file was given).
pii_required_or_fail() {
  local sql="$1" required="$2" reason="$3" tool="$4" override_ok="${5:-0}"
  local scan; scan="$(scan_sql_for_sensitivity "$sql")"

  if ! echo "$scan" | grep -Eq '(pii|restricted|json_sensitive|json_paths)=[^ ]+'; then
    return 0
  fi

  local summary; summary="$(_sensitive_summary "$scan")"
  local mode="$ROOT_AGENTS_COMPLIANCE_MODE"

  if [[ "$mode" == "off" ]]; then
    echo "[PII SAFETY OFF — DEV MODE] $summary" >&2
    return 0
  fi

  if (( required == 1 )); then
    if [[ -z "$reason" ]]; then
      echo "error: --pii-required requires --reason \"<text>\"" >&2
      echo "Touched: $summary" >&2
      exit 64
    fi
    _session_log_extra "$tool" "pii_required=true" "reason=\"$(printf '%s' "$reason" | sed 's/"/\\"/g')\""
    return 0
  fi

  # No override and the query is sensitive.
  if [[ "$mode" == "standard" ]] && (( override_ok == 1 )); then
    # standard + --to-file is acceptable; log it.
    _session_log_extra "$tool" "pii_to_file=true"
    return 0
  fi

  cat >&2 <<EOF
error: this query touches sensitive columns.
  $summary
Refusing to send these values into agent context.

Options:
  1. Route to a file:    --to-file <path>   (then operate on the file with duckdb-query.sh)
  2. Override with reason: --pii-required --reason "<why this needs PII in context>"
  3. Restructure to be aggregate-shaped (counts, group-bys) and remove the sensitive columns
  4. For JSON columns, run derive-jsonb-schema first so safe keys are tagged

See rules.md #26, #27, #28 and skills/pii-safe-analysis.md.
EOF
  exit 64
}

pii_posture_block() {
  case "$ROOT_AGENTS_COMPLIANCE_MODE" in
    off)
      echo "[PII SAFETY OFF — DEV MODE] Every tool invocation will emit this warning. Set ROOT_AGENTS_COMPLIANCE_MODE=strict for distribution-safe defaults." >&2
      ;;
  esac
}

# Emit the off-mode warning at source time so it fires on every tool that
# sources _lib.sh. Strict and standard are silent (the posture block in
# AGENTS.md handles their messaging to the agent).
pii_posture_block

# ----------------------------------------------------------------------------
# Inline result-schema firewall — the authoritative layer.
#
# The regex pre-flight (scan_sql_for_sensitivity) is fast and saves cost on
# obvious cases, but it's approximate — it can miss aliased columns and
# false-positive on column names appearing in string literals. The
# authoritative check runs AFTER Athena returns the qid but BEFORE we fetch
# the result CSV: we ask Athena what column schema the query actually
# produces, and check those names against pii-columns.json.
#
# This catches:
#   - Computed/derived columns that surface PII (e.g. CONCAT(first_name, ' ',
#     last_name) AS x — the alias 'x' is checked AND the source columns are
#     in the FROM-clause regex sweep)
#   - SELECT * where the table happens to have PII columns
#   - Aliases of PII columns (the result column name is the alias; we check
#     against the catalog by source-table mapping where possible)
#
# Tools call this AFTER run_athena and BEFORE fetch_results. If sensitive,
# the firewall applies the same gating as the pre-flight (route to file,
# require --pii-required, etc).

# get_result_schema <qid>
# Echoes one column name per line (lowercased, as Athena reports).
get_result_schema() {
  local qid="$1"
  command -v python3 >/dev/null || { echo "error: needs python3" >&2; return 64; }
  aws athena get-query-results --query-execution-id "$qid" --max-results 1 \
    --output json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cols = data.get("ResultSet", {}).get("ResultSetMetadata", {}).get("ColumnInfo", [])
for c in cols:
    name = (c.get("Name") or "").lower()
    label = (c.get("Label") or "").lower()
    # Athena reports both Name (catalog source) and Label (alias). Emit both
    # so the firewall catches "SELECT first_name AS x" via Name even when
    # Label is "x". When they match (no alias) we still print once.
    if name:
        print(name)
    if label and label != name:
        print(label)
'
}

# check_executed_query_sensitivity <qid>
# Reads the query's actual result schema from Athena and checks against
# pii-columns.json. Emits the same format as scan_sql_for_sensitivity.
check_executed_query_sensitivity() {
  local qid="$1"
  if [[ ! -f "$PII_META_PATH" ]]; then
    echo "pii= restricted= json_sensitive= json_paths="
    return 0
  fi
  local schema
  schema="$(get_result_schema "$qid")"
  python3 - "$PII_META_PATH" <<EOF
import json, sys

meta = json.load(open(sys.argv[1]))
schema_lines = """$schema""".strip()
result_cols = [c for c in schema_lines.split("\n") if c]

all_cols = {}
rank = {"pii": 3, "restricted": 2, "json_sensitive": 1}
for tbl_meta in meta["tables"].values():
    for col, col_meta in tbl_meta.get("columns", {}).items():
        sens = col_meta.get("sensitivity")
        if not sens:
            continue
        existing = all_cols.get(col.lower())
        if existing is None or rank.get(sens, 0) > rank.get(existing, 0):
            all_cols[col.lower()] = sens

pii_cols = set()
restricted_cols = set()
json_sens = set()
for col in result_cols:
    sens = all_cols.get(col)
    if sens == "pii":
        pii_cols.add(col)
    elif sens == "restricted":
        restricted_cols.add(col)
    elif sens == "json_sensitive":
        json_sens.add(col)

def fmt(s): return ",".join(sorted(s))
print(
    f"pii={fmt(pii_cols)} "
    f"restricted={fmt(restricted_cols)} "
    f"json_sensitive={fmt(json_sens)} "
    f"json_paths="
)
EOF
}

# pii_required_or_fail_inline <qid> <sql> <pii_required_flag> <reason> <tool> <override_ok>
# Authoritative post-execution gate. Combines the executed-query schema check
# with the SQL's JSON-path regex (json_paths can't be detected from the result
# schema alone). Same UX as pii_required_or_fail.
pii_required_or_fail_inline() {
  local qid="$1" sql="$2" required="$3" reason="$4" tool="$5" override_ok="${6:-0}"

  local exec_scan; exec_scan="$(check_executed_query_sensitivity "$qid")"
  local sql_scan;  sql_scan="$(scan_sql_for_sensitivity "$sql")"

  # Merge: exec_scan provides authoritative column-level sensitivity;
  # sql_scan provides json_paths (the only thing not visible in result schema).
  local exec_pii exec_restricted exec_json_sens sql_json_paths
  exec_pii="$(echo "$exec_scan"      | grep -oE 'pii=[^ ]*'             | cut -d= -f2-)"
  exec_restricted="$(echo "$exec_scan" | grep -oE 'restricted=[^ ]*'    | cut -d= -f2-)"
  exec_json_sens="$(echo "$exec_scan" | grep -oE 'json_sensitive=[^ ]*' | cut -d= -f2-)"
  sql_json_paths="$(echo "$sql_scan"  | grep -oE 'json_paths=[^ ]*'     | cut -d= -f2-)"

  local merged="pii=$exec_pii restricted=$exec_restricted json_sensitive=$exec_json_sens json_paths=$sql_json_paths"

  # Sensitive if any of the four buckets is non-empty.
  if ! echo "$merged" | grep -Eq '(pii|restricted|json_sensitive|json_paths)=[^ ]+'; then
    return 0
  fi

  local summary; summary="$(_sensitive_summary "$merged")"
  local mode="$ROOT_AGENTS_COMPLIANCE_MODE"

  if [[ "$mode" == "off" ]]; then
    echo "[PII SAFETY OFF — DEV MODE] $summary (result-schema check)" >&2
    return 0
  fi

  if (( required == 1 )); then
    if [[ -z "$reason" ]]; then
      echo "error: --pii-required requires --reason \"<text>\" (result-schema check)" >&2
      echo "Touched: $summary" >&2
      exit 64
    fi
    _session_log_extra "$tool" "pii_required=true" "inline_check=true" "reason=\"$(printf '%s' "$reason" | sed 's/"/\\"/g')\""
    return 0
  fi

  if [[ "$mode" == "standard" ]] && (( override_ok == 1 )); then
    _session_log_extra "$tool" "pii_to_file=true" "inline_check=true"
    return 0
  fi

  cat >&2 <<EOF
error: result-schema check — this query's actual result contains sensitive columns.
  $summary
The pre-flight scan didn't catch this (possibly aliased or computed columns).
Athena has already executed the query; the data is in S3 results, but we
refuse to fetch it into context without an explicit override.

Options:
  1. Re-run with --to-file <path> to write the result locally without printing
  2. Re-run with --pii-required --reason "<why>" to override
  3. Restructure the SELECT to drop the sensitive columns and try again

See rules.md #26, #27, #28 and skills/pii-safe-analysis.md.
EOF
  exit 64
}
