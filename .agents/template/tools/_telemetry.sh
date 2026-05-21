#!/usr/bin/env bash
# Mixpanel telemetry helper. Sourced by _lib.sh.
#
# Fires Title Case events at decision-tree milestones (see AGENTS.md
# "Telemetry"). Never blocks the caller: every track call is a backgrounded
# curl with a 2s timeout. Silently no-ops when MIXPANEL_TOKEN is unset or
# ROOT_AGENTS_TELEMETRY=off.

MIXPANEL_API_URL="${MIXPANEL_API_URL:-https://api-eu.mixpanel.com/track}"
ROOT_AGENTS_TELEMETRY="${ROOT_AGENTS_TELEMETRY:-on}"

# Self-contained: provide AGENTS_ROOT and _session_id fallbacks so this file
# can be sourced standalone.
if [[ -z "${AGENTS_ROOT:-}" ]]; then
  AGENTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  export AGENTS_ROOT
fi
if ! declare -f _session_id >/dev/null 2>&1; then
  _session_id() {
    echo "${ROOT_AGENTS_SESSION_ID:-$(date -u +%Y-%m-%d)}"
  }
fi

# Cache identity + version once per shell.
if [[ -z "${ROOT_AGENTS_USER:-}" ]]; then
  ROOT_AGENTS_USER="$(git config user.email 2>/dev/null || echo unknown)"
  export ROOT_AGENTS_USER
fi
if [[ -z "${ROOT_AGENTS_VERSION:-}" ]]; then
  ROOT_AGENTS_VERSION="$(git -C "$AGENTS_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  export ROOT_AGENTS_VERSION
fi

# Cache api_base_hash once per shell.
if [[ -z "${ROOT_AGENTS_API_HASH:-}" && -n "${API_BASE_URL:-}" ]]; then
  if command -v shasum >/dev/null; then
    ROOT_AGENTS_API_HASH="$(printf '%s' "$API_BASE_URL" | shasum -a 256 | cut -c1-16)"
  elif command -v sha256sum >/dev/null; then
    ROOT_AGENTS_API_HASH="$(printf '%s' "$API_BASE_URL" | sha256sum | cut -c1-16)"
  else
    ROOT_AGENTS_API_HASH="unknown"
  fi
  export ROOT_AGENTS_API_HASH
fi

# _mixpanel_track <Event Name> [k=v ...]
# Values that parse as int/float are sent as numbers; everything else is a
# string. Spaces in values are fine (passed via argv, not the shell).
_mixpanel_track() {
  [[ "$ROOT_AGENTS_TELEMETRY" == "off" ]] && return 0
  [[ -z "${MIXPANEL_TOKEN:-}" ]] && return 0
  command -v curl    >/dev/null 2>&1 || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local event="$1"; shift

  local body
  body="$(python3 - "$event" "$MIXPANEL_TOKEN" "$ROOT_AGENTS_USER" \
    "${ROOT_AGENTS_VERSION:-unknown}" \
    "$(_session_id)" \
    "${ROOT_AGENTS_API_HASH:-unknown}" \
    "${ROOT_AGENTS_COMPLIANCE_MODE:-unknown}" \
    "$@" 2>/dev/null <<'PY' || true
import json, sys, time, uuid
args = sys.argv[1:]
event, token, distinct_id, version, session_id, api_base_hash, mode = args[:7]
pairs = args[7:]

props = {
    "token": token,
    "distinct_id": distinct_id,
    "$insert_id": str(uuid.uuid4()),
    "time": int(time.time()),
    "session_id": session_id,
    "api_base_hash": api_base_hash,
    "compliance_mode": mode,
    "agents_version": version,
}

for pair in pairs:
    if "=" not in pair:
        continue
    k, v = pair.split("=", 1)
    if not k:
        continue
    try:
        props[k] = int(v)
        continue
    except ValueError:
        pass
    try:
        props[k] = float(v)
        continue
    except ValueError:
        pass
    props[k] = v

print(json.dumps([{"event": event, "properties": props}]))
PY
  )"

  [[ -z "$body" ]] && return 0

  if [[ "${ROOT_AGENTS_DEBUG:-0}" == "1" ]]; then
    printf '[telemetry] %s\n' "$body" >&2
  fi

  # Fire-and-forget. 2s timeout caps the worst case.
  (curl -sS -m 2 -X POST "$MIXPANEL_API_URL" \
    -H 'Content-Type: application/json' \
    -d "$body" >/dev/null 2>&1) &
  return 0
}
