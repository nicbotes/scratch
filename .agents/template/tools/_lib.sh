#!/usr/bin/env bash
# Shared helpers for .agents/tools/*.sh
# Sourced, not executed.

set -euo pipefail

AGENTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AGENTS_ROOT

# Mixpanel telemetry — no-ops when MIXPANEL_TOKEN unset.
# shellcheck disable=SC1091
source "$AGENTS_ROOT/tools/_telemetry.sh"

_session_id() {
  echo "${ROOT_AGENTS_SESSION_ID:-$(date -u +%Y-%m-%d)}"
}

_debug() {
  [[ "${ROOT_AGENTS_DEBUG:-0}" == "1" ]] || return 0
  printf '[debug] %s\n' "$*" >&2
}

# require_api_env
# Asserts the two required env vars are set before any tool that hits the API
# can proceed. API_TOKEN is allowed to be empty for public-only fetches; tools
# that need it call require_api_token instead.
require_api_env() {
  local missing=()
  [[ -z "${API_BASE_URL:-}" ]] && missing+=("API_BASE_URL")
  if (( ${#missing[@]} )); then
    printf 'error: missing required env vars: %s\n' "${missing[*]}" >&2
    printf 'see %s/references/env-vars.md\n' "$AGENTS_ROOT" >&2
    exit 64
  fi
}

require_api_token() {
  require_api_env
  if [[ -z "${API_TOKEN:-}" ]]; then
    printf 'error: API_TOKEN unset; this endpoint requires authentication\n' >&2
    printf 'see %s/references/env-vars.md\n' "$AGENTS_ROOT" >&2
    exit 64
  fi
}

# hash_id <value>
# Deterministic short hash for committed-artefact identifiers. 16 hex chars
# (64 bits) is plenty for collision resistance within a single team's golden
# set. See rules.md (committed identifiers are hashed).
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

# api_base_hash
# Hash of the current API_BASE_URL. Used in session logs and committed paths
# to keep raw URLs out of git plaintext while preserving per-API clustering.
api_base_hash() {
  hash_id "${API_BASE_URL:-unknown}"
}
export -f api_base_hash 2>/dev/null || true

# Path to the local DuckDB database. All landed data and views live here.
DUCKDB_PATH="${DUCKDB_PATH:-$AGENTS_ROOT/data/db/main.duckdb}"
export DUCKDB_PATH

# Context-size safety caps. Tools that print to stdout honour these.
ROOT_AGENTS_MAX_ROWS="${ROOT_AGENTS_MAX_ROWS:-1000}"
ROOT_AGENTS_MAX_BYTES="${ROOT_AGENTS_MAX_BYTES:-200000}"
export ROOT_AGENTS_MAX_ROWS ROOT_AGENTS_MAX_BYTES

_session_log() {
  local tool="$1" ok="$2" ms="$3" bytes="${4:-0}"
  local dir="$AGENTS_ROOT/sessions"
  mkdir -p "$dir"
  local sid; sid="$(_session_id)"
  local hash; hash="$(api_base_hash)"
  printf '{"ts":"%s","session":"%s","tool":"%s","ok":%s,"ms":%s,"bytes":%s,"api_base_hash":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$tool" "$ok" "$ms" "$bytes" "$hash" \
    >> "$dir/$sid.jsonl"
}

# _session_log_extra <tool> <key=value> ... — one-off event row
# (e.g. row_cap_hit=true, pii_required=true) appended alongside _session_log.
_session_log_extra() {
  local tool="$1"; shift
  local dir="$AGENTS_ROOT/sessions"
  mkdir -p "$dir"
  local sid; sid="$(_session_id)"
  local hash; hash="$(api_base_hash)"
  local extra=""
  for kv in "$@"; do
    local k="${kv%%=*}" v="${kv#*=}"
    extra+=",\"$k\":$v"
  done
  printf '{"ts":"%s","session":"%s","tool":"%s"%s,"api_base_hash":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$tool" "$extra" "$hash" \
    >> "$dir/$sid.jsonl"
}

# run_duckdb <sql>
# Executes SQL against $DUCKDB_PATH; echoes nothing on success.
# Populates LAST_QUERY_MS for callers.
LAST_QUERY_MS=0
LAST_QUERY_ROWS=0
run_duckdb() {
  local sql="$1"
  command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }
  mkdir -p "$(dirname "$DUCKDB_PATH")"
  local started=$EPOCHREALTIME
  duckdb "$DUCKDB_PATH" -c "$sql"
  local ended=$EPOCHREALTIME
  LAST_QUERY_MS=$(awk -v s="$started" -v e="$ended" 'BEGIN { printf "%d", (e-s)*1000 }')
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
#   --pii-required --reason "<text>" to proceed.
#
# is_sensitive_query <sql>
#   Returns 0 if the SQL touches any sensitive column, 1 otherwise.
#
# pii_required_or_fail <sql> <pii_required_flag> <reason> <tool> <override_ok>
#   The shared pre-flight gate. If the SQL is sensitive and --pii-required
#   wasn't passed, prints a clear error and exits 64. <override_ok> = 1 lets
#   --to-file alone serve as the override in 'standard' mode.
#
# pii_required_or_fail_inline <sql> <pii_required_flag> <reason> <tool> <override_ok>
#   The post-execution (authoritative) gate. Runs DESCRIBE (<sql>) against the
#   DuckDB database, inspects the resulting column names, and re-applies the
#   same gating. Catches aliased PII that the pre-flight regex might miss.
#
# pii_posture_block
#   Echoes the appropriate posture banner for the current
#   ROOT_AGENTS_COMPLIANCE_MODE.

ROOT_AGENTS_COMPLIANCE_MODE="${ROOT_AGENTS_COMPLIANCE_MODE:-strict}"
export ROOT_AGENTS_COMPLIANCE_MODE

PII_META_PATH="$AGENTS_ROOT/references/pii-columns.json"

scan_sql_for_sensitivity() {
  local sql="$1"
  if [[ ! -f "$PII_META_PATH" ]]; then
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
scrubbed = re.sub(r"'(?:[^'\\\\]|\\\\.)*'", "''", sql)
scrubbed_lower = scrubbed.lower()

# Strip -- and /* */ comments
scrubbed_lower = re.sub(r'--[^\n]*', '', scrubbed_lower)
scrubbed_lower = re.sub(r'/\*.*?\*/', '', scrubbed_lower, flags=re.DOTALL)

pii_cols = set()
restricted_cols = set()
json_sensitive_cols = set()
json_paths = set()

all_cols = {}
rank = {"pii": 3, "restricted": 2, "json_sensitive": 1}
for tbl, tbl_meta in meta.get("tables", {}).items():
    for col, col_meta in tbl_meta.get("columns", {}).items():
        sens = col_meta.get("sensitivity")
        if not sens:
            continue
        existing = all_cols.get(col.lower())
        if existing is None or rank.get(sens, 0) > rank.get(existing, 0):
            all_cols[col.lower()] = sens

for col, sens in all_cols.items():
    if re.search(r'\b' + re.escape(col) + r'\b', scrubbed_lower):
        if sens == "pii":
            pii_cols.add(col)
        elif sens == "restricted":
            restricted_cols.add(col)
        elif sens == "json_sensitive":
            json_sensitive_cols.add(col)

# DuckDB JSON-path access: json_extract_string(<col>, '<path>') and dot-notation
# (<col>.<key>) on STRUCT/JSON typed columns.
for col in list(json_sensitive_cols):
    pat_fn = re.compile(
        r"json_extract(?:_string|_scalar)?\s*\(\s*" + re.escape(col) +
        r"\s*,\s*'([^']+)'",
        re.IGNORECASE,
    )
    for m in pat_fn.finditer(sql):
        json_paths.add(col + ":" + m.group(1))
    pat_dot = re.compile(
        r"\b" + re.escape(col) + r"\.([A-Za-z_][A-Za-z0-9_]*)\b",
        re.IGNORECASE,
    )
    for m in pat_dot.finditer(scrubbed):
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
  echo "$scan" | grep -Eq '(pii|restricted|json_sensitive|json_paths)=[^ ]+' && return 0
  return 1
}

_sensitive_summary() {
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
pii_required_or_fail() {
  local sql="$1" required="$2" reason="$3" tool="$4" override_ok="${5:-0}"
  local scan; scan="$(scan_sql_for_sensitivity "$sql")"

  if ! echo "$scan" | grep -Eq '(pii|restricted|json_sensitive|json_paths)=[^ ]+'; then
    return 0
  fi

  local summary; summary="$(_sensitive_summary "$scan")"
  local mode="$ROOT_AGENTS_COMPLIANCE_MODE"

  local p r j jp
  p="$(echo "$scan"  | grep -oE 'pii=[^ ]*'             | cut -d= -f2-)"
  r="$(echo "$scan"  | grep -oE 'restricted=[^ ]*'      | cut -d= -f2-)"
  j="$(echo "$scan"  | grep -oE 'json_sensitive=[^ ]*'  | cut -d= -f2-)"
  jp="$(echo "$scan" | grep -oE 'json_paths=[^ ]*'      | cut -d= -f2-)"

  if [[ "$mode" == "off" ]]; then
    echo "[PII SAFETY OFF — DEV MODE] $summary" >&2
    _mixpanel_track "PII Touched" "route=dev-mode-off" "tool=$tool" \
      "pii_columns=$p" "restricted_columns=$r" "json_sensitive=$j"
    return 0
  fi

  if (( required == 1 )); then
    if [[ -z "$reason" ]]; then
      echo "error: --pii-required requires --reason \"<text>\"" >&2
      echo "Touched: $summary" >&2
      exit 64
    fi
    local esc_reason
    esc_reason="$(printf '%s' "$reason" | sed 's/"/\\"/g')"
    _session_log_extra "$tool" \
      "pii_required=true" \
      "reason=\"$esc_reason\"" \
      "touched_pii=\"$p\"" \
      "touched_restricted=\"$r\"" \
      "touched_json_sensitive=\"$j\"" \
      "touched_json_paths=\"$jp\""
    _mixpanel_track "PII Approved" "tool=$tool" "reason=$reason" \
      "pii_columns=$p" "restricted_columns=$r" "json_sensitive=$j"
    return 0
  fi

  if [[ "$mode" == "standard" ]] && (( override_ok == 1 )); then
    _session_log_extra "$tool" \
      "pii_to_file=true" \
      "touched_pii=\"$p\"" \
      "touched_restricted=\"$r\"" \
      "touched_json_sensitive=\"$j\"" \
      "touched_json_paths=\"$jp\""
    _mixpanel_track "PII Touched" "route=to-file" "tool=$tool" \
      "pii_columns=$p" "restricted_columns=$r" "json_sensitive=$j"
    return 0
  fi

  cat >&2 <<EOF
error: this query touches sensitive columns.
  $summary
Refusing to send these values into agent context.

Options:
  1. Route to a file:      --to-file <path>   (then operate on the file)
  2. Override with reason: --pii-required --reason "<why this needs PII in context>"
  3. Restructure to be aggregate-shaped (counts, group-bys) and remove the sensitive columns

See rules.md and skills/pii-safe-analysis.md.
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
pii_posture_block

# ----------------------------------------------------------------------------
# Inline result-schema firewall — the authoritative DuckDB layer.
#
# The pre-flight regex (scan_sql_for_sensitivity) is fast and saves cost on
# obvious cases, but it's approximate — it can miss aliased columns and
# false-positive on names appearing in string literals. The authoritative check
# uses DuckDB's `DESCRIBE (<sql>)` to ask what the query will actually produce,
# and checks those names against pii-columns.json.

# get_result_schema_duckdb <sql>
# Echoes one column name per line (lowercased), without executing the query
# fully — DuckDB plans + types the SQL but doesn't materialise rows.
get_result_schema_duckdb() {
  local sql="$1"
  command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; return 64; }
  # Single-quote escape SQL for embedding in DESCRIBE(...)
  local escaped; escaped="$(printf '%s' "$sql" | sed "s/'/''/g")"
  duckdb "$DUCKDB_PATH" -noheader -list \
    -c "SELECT lower(column_name) FROM (DESCRIBE ($sql))" 2>/dev/null || true
}

check_executed_query_sensitivity_duckdb() {
  local sql="$1"
  if [[ ! -f "$PII_META_PATH" ]]; then
    echo "pii= restricted= json_sensitive= json_paths="
    return 0
  fi
  local schema
  schema="$(get_result_schema_duckdb "$sql")"
  python3 - "$PII_META_PATH" <<EOF
import json, sys

meta = json.load(open(sys.argv[1]))
schema_lines = """$schema""".strip()
result_cols = [c.strip() for c in schema_lines.split("\n") if c.strip()]

all_cols = {}
rank = {"pii": 3, "restricted": 2, "json_sensitive": 1}
for tbl_meta in meta.get("tables", {}).values():
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

# pii_required_or_fail_inline <sql> <pii_required_flag> <reason> <tool> <override_ok>
# Authoritative post-plan gate. Uses DuckDB DESCRIBE so we see the actual
# result column names (catching aliased PII the pre-flight could miss).
pii_required_or_fail_inline() {
  local sql="$1" required="$2" reason="$3" tool="$4" override_ok="${5:-0}"

  local exec_scan; exec_scan="$(check_executed_query_sensitivity_duckdb "$sql")"
  local sql_scan;  sql_scan="$(scan_sql_for_sensitivity "$sql")"

  local exec_pii exec_restricted exec_json_sens sql_json_paths
  exec_pii="$(echo "$exec_scan"        | grep -oE 'pii=[^ ]*'            | cut -d= -f2-)"
  exec_restricted="$(echo "$exec_scan" | grep -oE 'restricted=[^ ]*'     | cut -d= -f2-)"
  exec_json_sens="$(echo "$exec_scan"  | grep -oE 'json_sensitive=[^ ]*' | cut -d= -f2-)"
  sql_json_paths="$(echo "$sql_scan"   | grep -oE 'json_paths=[^ ]*'     | cut -d= -f2-)"

  local merged="pii=$exec_pii restricted=$exec_restricted json_sensitive=$exec_json_sens json_paths=$sql_json_paths"

  if ! echo "$merged" | grep -Eq '(pii|restricted|json_sensitive|json_paths)=[^ ]+'; then
    return 0
  fi

  local summary; summary="$(_sensitive_summary "$merged")"
  local mode="$ROOT_AGENTS_COMPLIANCE_MODE"

  if [[ "$mode" == "off" ]]; then
    echo "[PII SAFETY OFF — DEV MODE] $summary (result-schema check)" >&2
    _mixpanel_track "PII Touched" "route=dev-mode-off" "tool=$tool" "inline_check=true" \
      "pii_columns=$exec_pii" "restricted_columns=$exec_restricted" "json_sensitive=$exec_json_sens"
    return 0
  fi

  if (( required == 1 )); then
    if [[ -z "$reason" ]]; then
      echo "error: --pii-required requires --reason \"<text>\" (result-schema check)" >&2
      echo "Touched: $summary" >&2
      exit 64
    fi
    local esc_reason
    esc_reason="$(printf '%s' "$reason" | sed 's/"/\\"/g')"
    _session_log_extra "$tool" \
      "pii_required=true" \
      "inline_check=true" \
      "reason=\"$esc_reason\"" \
      "touched_pii=\"$exec_pii\"" \
      "touched_restricted=\"$exec_restricted\"" \
      "touched_json_sensitive=\"$exec_json_sens\"" \
      "touched_json_paths=\"$sql_json_paths\""
    _mixpanel_track "PII Approved" "tool=$tool" "reason=$reason" "inline_check=true" \
      "pii_columns=$exec_pii" "restricted_columns=$exec_restricted" "json_sensitive=$exec_json_sens"
    return 0
  fi

  if [[ "$mode" == "standard" ]] && (( override_ok == 1 )); then
    _session_log_extra "$tool" \
      "pii_to_file=true" \
      "inline_check=true" \
      "touched_pii=\"$exec_pii\"" \
      "touched_restricted=\"$exec_restricted\"" \
      "touched_json_sensitive=\"$exec_json_sens\"" \
      "touched_json_paths=\"$sql_json_paths\""
    _mixpanel_track "PII Touched" "route=to-file" "tool=$tool" "inline_check=true" \
      "pii_columns=$exec_pii" "restricted_columns=$exec_restricted" "json_sensitive=$exec_json_sens"
    return 0
  fi

  cat >&2 <<EOF
error: result-schema check — this query's actual result contains sensitive columns.
  $summary
The pre-flight scan didn't catch this (possibly aliased or computed columns).

Options:
  1. Re-run with --to-file <path> to write the result locally without printing
  2. Re-run with --pii-required --reason "<why>" to override
  3. Restructure the SELECT to drop the sensitive columns

See rules.md and skills/pii-safe-analysis.md.
EOF
  exit 64
}
