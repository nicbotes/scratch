#!/usr/bin/env bash
# export-results.sh <name> "<sql>" [--pii-required --reason "<why>"]
#
# Runs the SQL and persists the CSV + a manifest. Non-sensitive exports land
# under .agents/evidence/<utc-ts>-<name>/. Sensitive exports land under
# .agents/sensitive/<utc-ts>-<name>/ (separately gitignored, separately
# prefixed for tighter access control downstream).
#
# The manifest captures org id, env, sql, query execution id, row count, sha256
# of the CSV, and sensitivity tags so the export is verifiable independent of
# the agent session that produced it.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

pii_required=0
reason=""
positional=()

while (( $# )); do
  case "$1" in
    --pii-required) pii_required=1; shift ;;
    --reason)       reason="$2";    shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

name="${1:-}"
sql="${2:-}"
if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: export-results.sh <name> "<sql>" [--pii-required --reason "<why>"]' >&2
  exit 64
fi

# Scan for sensitivity tags before gating
scan="$(scan_sql_for_sensitivity "$sql")"
contains_pii=false
contains_restricted=false
contains_json_sensitive=false
echo "$scan" | grep -q 'pii=[^ ]'             && contains_pii=true
echo "$scan" | grep -q 'restricted=[^ ]'      && contains_restricted=true
echo "$scan" | grep -q 'json_sensitive=[^ ]'  && contains_json_sensitive=true

# PII firewall — writing to disk is the legitimate path for sensitive output
# (compliance evidence, DSAR fulfilment). But --pii-required + reason is
# still required so the lookup is auditable.
pii_required_or_fail "$sql" "$pii_required" "$reason" "export-results" 0

require_env

ts="$(date -u +%Y%m%dT%H%M%SZ)"

# Sensitive exports land under .agents/sensitive/; everything else under
# .agents/evidence/. Both are gitignored.
if [[ "$contains_pii" == "true" || "$contains_restricted" == "true" || "$contains_json_sensitive" == "true" ]]; then
  dir="$AGENTS_ROOT/sensitive/$ts-$name"
else
  dir="$AGENTS_ROOT/evidence/$ts-$name"
fi
mkdir -p "$dir"

qid="$(run_athena "$sql")"

# Inline result-schema check — augment the pre-flight scan with what Athena
# actually returned. If the result schema reveals sensitivity the regex
# missed, switch to the sensitive prefix and update the manifest tags.
inline_scan="$(check_executed_query_sensitivity "$qid")"
echo "$inline_scan" | grep -q 'pii=[^ ]'            && contains_pii=true
echo "$inline_scan" | grep -q 'restricted=[^ ]'     && contains_restricted=true
echo "$inline_scan" | grep -q 'json_sensitive=[^ ]' && contains_json_sensitive=true

# Re-pick the destination directory if the inline check flipped any flag.
if [[ "$contains_pii" == "true" || "$contains_restricted" == "true" || "$contains_json_sensitive" == "true" ]]; then
  if [[ "$dir" != "$AGENTS_ROOT/sensitive/"* ]]; then
    new_dir="$AGENTS_ROOT/sensitive/$ts-$name"
    mkdir -p "$new_dir"
    rmdir "$dir" 2>/dev/null || true
    dir="$new_dir"
  fi
fi

csv_path="$dir/results.csv"
fetch_results "$qid" > "$csv_path"

rows="$(($(wc -l < "$csv_path") - 1))"
sha="$(sha256sum "$csv_path" | awk '{print $1}')"
org_hash="$(hash_id "$ROOT_ORG_ID")"

# Escape sensitive fields safely for JSON
escape_json() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))' 2>/dev/null \
    || printf '"%s"' "$(sed 's/\\/\\\\/g; s/"/\\"/g' <<<"$1")"
}
j_sql="$(printf '%s' "$sql" | escape_json)"
j_reason="$(printf '%s' "$reason" | escape_json)"

cat > "$dir/manifest.json" <<EOF
{
  "name": "$name",
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "org_id_hash": "$org_hash",
  "env": "$ROOT_ENV",
  "region": "${AWS_REGION:-unknown}",
  "query_execution_id": "$qid",
  "row_count": $rows,
  "sha256": "$sha",
  "contains_pii": $contains_pii,
  "contains_restricted": $contains_restricted,
  "contains_json_sensitive": $contains_json_sensitive,
  "pii_required_reason": $j_reason,
  "sql": $j_sql
}
EOF

echo "$dir"
