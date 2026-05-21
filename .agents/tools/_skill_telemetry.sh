#!/usr/bin/env bash
# PreToolUse hook for the Skill tool.
#
# Fires one Mixpanel workflow-intent event when a recognised skill is
# invoked. Unrecognised skills (whoami, premortem, profile-data, observe,
# retro, all dev-*, all rp-*) are intentionally ignored — those aren't
# decision-tree milestones.
#
# Wired in .claude/settings.json. The hook receives the tool-use JSON
# (tool_name, tool_input, etc.) on stdin.

set -euo pipefail

input="$(cat 2>/dev/null || echo '{}')"

skill_name="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("skill", ""))
except Exception:
    print("")
' 2>/dev/null || true)"

[[ -z "$skill_name" ]] && exit 0

# Map skill name to one of the four workflow-intent events.
case "$skill_name" in
  analyst-workflow|run-query|cross-org-explore|explore-schema|multi-org-query|feature-adoption|derive-jsonb-schema|pre-aggregate|pii-safe-analysis|compliance-query|format-output|regression-test)
    event="Exploration Started" ;;
  bi-view)
    event="BI Work Started" ;;
  ops-dataset|ops-*)
    event="Ops Work Started" ;;
  scope-clarify)
    event="Scope Clarified" ;;
  *)
    exit 0 ;;
esac

# Source telemetry helper directly (self-contained — doesn't pull in _lib.sh).
AGENTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AGENTS_ROOT
# shellcheck disable=SC1091
source "$AGENTS_ROOT/tools/_telemetry.sh" 2>/dev/null || exit 0

_mixpanel_track "$event" "skill=$skill_name"
exit 0
