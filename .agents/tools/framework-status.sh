#!/usr/bin/env bash
# framework-status.sh
#
# One-screen health + maturity dashboard. Reads no AWS — purely local
# inspection of .agents/ + a check for required CLI dependencies. Safe
# to run at session start or whenever something feels off.
#
# Reports:
#   - Active org (from env vars; doesn't call Athena)
#   - Dependency check (aws CLI, duckdb, python3)
#   - Skill counts (canonical + learned)
#   - Reference counts
#   - Tool counts
#   - View counts by prefix and per-client breakdown (from .agents/bi/
#     and .agents/ops/ markdown docs — local, no Athena query)
#   - Regression goldens (current org's hash folder)
#   - Open retro proposals
#   - Maturity flags pointing at the next step on the learning curve

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

echo "=== Root Data Adapter framework status ==="
echo

# --- Active org ---------------------------------------------------------
if [[ -n "${ROOT_ORG_ID:-}" ]]; then
  echo "Active org:     (run 'bash .agents/tools/whoami.sh' for the name)"
  echo "Org ID:         $ROOT_ORG_ID"
  if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
    org_hash="$(hash_id "$ROOT_ORG_ID")"
    echo "Org hash:       $org_hash"
  fi
else
  echo "Active org:     <not set — source .agents/.env first>"
  org_hash=""
fi
echo "Region:         ${AWS_REGION:-<auto-detect>}"
echo "Env:            ${ROOT_ENV:-production}"
echo "PII mode:       ${ROOT_AGENTS_COMPLIANCE_MODE:-strict}"
echo

# --- Dependencies -------------------------------------------------------
echo "Dependencies:"
for dep in aws duckdb python3; do
  if command -v "$dep" >/dev/null 2>&1; then
    echo "  ✓ $dep"
  else
    echo "  ✗ $dep  (missing — see references/env-vars.md)"
  fi
done
echo

# --- Skills, references, tools ------------------------------------------
canonical_skills=$(find "$AGENTS_ROOT/skills" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
learned_skills=$(find "$AGENTS_ROOT/skills/learned" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
references=$(find "$AGENTS_ROOT/references" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
tools=$(find "$AGENTS_ROOT/tools" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')

echo "Skills:         $canonical_skills canonical, $learned_skills learned"
echo "References:     $references documents"
echo "Tools:          $tools executables"
echo

# --- Views (from local markdown docs) -----------------------------------
echo "Views (this org, rp_ namespace — read from local docs):"

universal_fact=$(find "$AGENTS_ROOT/bi" -maxdepth 1 -name 'fact_*.md' 2>/dev/null | wc -l | tr -d ' ')
universal_dim=$(find "$AGENTS_ROOT/bi" -maxdepth 1 -name 'dim_*.md' 2>/dev/null | wc -l | tr -d ' ')
universal_ops=$(find "$AGENTS_ROOT/ops" -maxdepth 1 -name 'ops_*.md' 2>/dev/null | wc -l | tr -d ' ')
echo "  Universal:    $universal_fact rp_fact_*, $universal_dim rp_dim_*, $universal_ops rp_ops_*"

# Per-client breakdown — portable to bash 3.x (no associative arrays)
client_count=0
client_list=""
if [[ -d "$AGENTS_ROOT/bi/clients" ]] || [[ -d "$AGENTS_ROOT/ops/clients" ]]; then
  # Collect slug:count lines, one per slug, summed across bi/ and ops/.
  client_tally="$(
    for client_dir in "$AGENTS_ROOT/bi/clients"/*/ "$AGENTS_ROOT/ops/clients"/*/; do
      [[ -d "$client_dir" ]] || continue
      slug="$(basename "$client_dir")"
      [[ "$slug" == ".gitkeep" || "$slug" == "*" ]] && continue
      vc=$(find "$client_dir" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
      (( vc > 0 )) && printf '%s %s\n' "$slug" "$vc"
    done \
    | awk '{ counts[$1] += $2 } END { for (s in counts) printf "%s:%d ", s, counts[s] }'
  )"

  if [[ -n "$client_tally" ]]; then
    client_list="$client_tally"
    # Count tokens in client_tally
    # shellcheck disable=SC2086
    set -- $client_tally
    client_count=$#
    echo "  Per-client:   $client_count clients ($client_list)"
  else
    echo "  Per-client:   none"
  fi
else
  echo "  Per-client:   none (no .agents/bi/clients/ yet)"
fi
echo

# --- Regression goldens -------------------------------------------------
if [[ -n "$org_hash" && -d "$AGENTS_ROOT/regressions/$org_hash" ]]; then
  golden_count=$(find "$AGENTS_ROOT/regressions/$org_hash" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  last_captured="$(find "$AGENTS_ROOT/regressions/$org_hash" -name '*.json' -exec grep -h '"captured_at"' {} \; 2>/dev/null | sed -E 's/.*"captured_at":[[:space:]]*"([^"]+)".*/\1/' | sort -r | head -1)"
  echo "Regression goldens: $golden_count recorded (last captured: ${last_captured:-n/a})"
else
  echo "Regression goldens: 0 (no folder for this org's hash yet)"
fi
echo

# --- Retro proposals ----------------------------------------------------
if [[ -d "$AGENTS_ROOT/proposals" ]]; then
  open_proposals=$(find "$AGENTS_ROOT/proposals" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  echo "Retro proposals:    $open_proposals open"
else
  echo "Retro proposals:    0 open"
fi
echo

# --- Maturity flags -----------------------------------------------------
echo "Maturity flags:"

# Conformed dimensions emerging?
if (( universal_dim >= 3 )); then
  echo "  ✓ Conformed dimensions layer emerging ($universal_dim rp_dim_* views)"
elif (( universal_dim > 0 )); then
  echo "  ◦ $universal_dim rp_dim_* view(s) — conformed dim layer takes shape at ≥3"
else
  echo "  ◦ No conformed dimensions yet — first dim view bootstraps the analytical layer"
fi

# Per-client mart maturity → dbt candidate?
if (( ${client_count:-0} >= 3 )); then
  echo "  ◇ Per-client mart maturing — $client_count clients with bespoke views"
  echo "    Consider dbt promotion (FUTURE.md §9) when shape is stable across consumers"
elif (( ${client_count:-0} > 0 )); then
  echo "  ◦ $client_count client(s) with bespoke views — dbt candidacy at ≥3"
fi

# Open retro proposals?
if (( open_proposals > 0 )); then
  echo "  ◇ $open_proposals retro proposal(s) awaiting human review (.agents/proposals/)"
fi

# Stale scratch views?  (We can't tell from local docs since scratch views
# are intentionally undocumented. Surfacing this would need an Athena call;
# defer to list-views.sh.)
echo
echo "Hint: 'bash .agents/tools/list-views.sh' shows live Athena views; this"
echo "      report reflects local doc state only."
