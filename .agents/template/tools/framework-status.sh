#!/usr/bin/env bash
# framework-status.sh
#
# One-screen health + maturity dashboard. Reads no API — purely local
# inspection of .agents/ + a check for required CLI dependencies. Safe to
# run at session start or whenever something feels off.
#
# Reports:
#   - Active API base (and hash)
#   - Dependency check (duckdb, curl, jq, python3)
#   - Skill counts (canonical + learned)
#   - Reference counts (incl. sources/)
#   - Tool counts
#   - DuckDB tables + views (live, from main.duckdb)
#   - Regression goldens (current API's hash folder)
#   - Open retro proposals
#   - Feedback / session activity in the last 7 days
#   - Telemetry on/off

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

echo "=== Analyst Agent Framework status ==="
echo

# --- Active API ---------------------------------------------------------
if [[ -n "${API_BASE_URL:-}" ]]; then
  echo "API base:        $API_BASE_URL"
  echo "API hash:        $(api_base_hash)"
else
  echo "API base:        <not set — source .agents/.env first>"
fi
echo "PII mode:        ${ROOT_AGENTS_COMPLIANCE_MODE:-strict}"
if [[ -n "${MIXPANEL_TOKEN:-}" && "${ROOT_AGENTS_TELEMETRY:-on}" != "off" ]]; then
  echo "Telemetry:       on (MIXPANEL_TOKEN set)"
else
  echo "Telemetry:       off"
fi
echo

# --- Dependencies -------------------------------------------------------
echo "Dependencies:"
for dep in duckdb curl jq python3; do
  if command -v "$dep" >/dev/null 2>&1; then
    echo "  ✓ $dep"
  else
    echo "  ✗ $dep  (missing — see references/env-vars.md)"
  fi
done
echo

# --- Skills, references, tools ------------------------------------------
canonical_skills=$(find "$AGENTS_ROOT/skills" -maxdepth 1 -name '*.md' ! -name '_*' 2>/dev/null | wc -l | tr -d ' ')
learned_skills=$(find "$AGENTS_ROOT/skills/learned" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
references=$(find "$AGENTS_ROOT/references" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
sources=$(find "$AGENTS_ROOT/references/sources" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
tools=$(find "$AGENTS_ROOT/tools" -maxdepth 1 -name '*.sh' ! -name '_*' 2>/dev/null | wc -l | tr -d ' ')

echo "Skills:          $canonical_skills canonical, $learned_skills learned"
echo "References:      $references docs ($sources sources)"
echo "Tools:           $tools executables"
echo

# --- Live DuckDB --------------------------------------------------------
db_path="$DUCKDB_PATH"
if command -v duckdb >/dev/null 2>&1 && [[ -f "$db_path" ]]; then
  raw_count=$(duckdb "$db_path" -noheader -list -c "
    SELECT count(*) FROM information_schema.tables
    WHERE table_type='BASE TABLE' AND table_name LIKE 'raw_%';
  " 2>/dev/null || echo 0)
  bi_count=$(duckdb "$db_path" -noheader -list -c "
    SELECT count(*) FROM information_schema.tables
    WHERE table_type='VIEW' AND table_name LIKE 'bi_%';
  " 2>/dev/null || echo 0)
  ops_count=$(duckdb "$db_path" -noheader -list -c "
    SELECT count(*) FROM information_schema.tables
    WHERE table_type='VIEW' AND table_name LIKE 'ops_%';
  " 2>/dev/null || echo 0)
  scratch_count=$(duckdb "$db_path" -noheader -list -c "
    SELECT count(*) FROM information_schema.tables
    WHERE table_type='VIEW' AND table_name LIKE 'scratch_%';
  " 2>/dev/null || echo 0)
  partial_count=$(duckdb "$db_path" -noheader -list -c "
    SELECT count(*) FROM duckdb_tables() WHERE comment LIKE '%partial=true%';
  " 2>/dev/null || echo 0)
  echo "DuckDB ($db_path):"
  echo "  raw_*:         $raw_count tables ($partial_count partial)"
  echo "  bi_*_view:     $bi_count"
  echo "  ops_*_view:    $ops_count"
  echo "  scratch_*_view:$scratch_count"
else
  echo "DuckDB:          no database yet at $db_path"
fi
echo

# --- Regression goldens -------------------------------------------------
hash="$(api_base_hash 2>/dev/null || echo unknown)"
if [[ -d "$AGENTS_ROOT/regressions/$hash" ]]; then
  golden_count=$(find "$AGENTS_ROOT/regressions/$hash" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  last_captured="$(find "$AGENTS_ROOT/regressions/$hash" -name '*.json' -exec grep -h '"captured_at"' {} \; 2>/dev/null | sed -E 's/.*"captured_at":[[:space:]]*"([^"]+)".*/\1/' | sort -r | head -1)"
  echo "Goldens:         $golden_count for this API (last: ${last_captured:-n/a})"
else
  echo "Goldens:         0 (no folder for this API's hash yet)"
fi

# --- Proposals ----------------------------------------------------------
open_proposals=$(find "$AGENTS_ROOT/proposals" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
echo "Proposals:       $open_proposals open"

# --- Feedback / session activity (last 7 days) --------------------------
sessions_7d=0
feedback_7d=0
if [[ -d "$AGENTS_ROOT/sessions" ]]; then
  sessions_7d=$(find "$AGENTS_ROOT/sessions" -name '*.jsonl' -mtime -7 2>/dev/null | xargs -I{} wc -l < {} 2>/dev/null | awk '{s+=$1} END {print s+0}')
fi
if [[ -d "$AGENTS_ROOT/feedback" ]]; then
  feedback_7d=$(find "$AGENTS_ROOT/feedback" -name '*.jsonl' -mtime -7 2>/dev/null | xargs -I{} wc -l < {} 2>/dev/null | awk '{s+=$1} END {print s+0}')
fi
echo "Sessions (7d):   $sessions_7d tool-call entries"
echo "Feedback (7d):   $feedback_7d notes"
echo

# --- Hints --------------------------------------------------------------
echo "Hints:"
if (( golden_count == 0 )); then
  echo "  ◦ Record your first regression golden after a stable analysis"
  echo "    (skills/regression-test.md)"
fi
if (( feedback_7d == 0 )); then
  echo "  ◦ No feedback notes this week — the observe→retro loop only works"
  echo "    if you fire feedback-note.sh in the moment"
fi
if (( open_proposals > 0 )); then
  echo "  ◇ $open_proposals retro proposal(s) awaiting human review"
fi
