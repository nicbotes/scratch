#!/usr/bin/env bash
# whoami.sh [--endpoint <path>]
#
# Confirm the framework's API credentials work. By default hits the API base
# URL itself (no path) which most APIs answer with a service blurb or 404
# that at least proves connectivity. For nicer output, pass a specific
# authenticated endpoint (e.g. /user for GitHub, /me for many SaaS APIs).
#
# Prints a four-line summary: api base, hash, identity (if available), mode.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

endpoint=""
while (( $# )); do
  case "$1" in
    --endpoint) endpoint="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

require_api_env
command -v curl >/dev/null || { echo "error: curl not on PATH" >&2; exit 64; }

hash="$(api_base_hash)"
mode="${ROOT_AGENTS_COMPLIANCE_MODE:-strict}"

cat <<EOF
API base:    $API_BASE_URL
API hash:    $hash
Mode:        $mode
Token set:   $([[ -n "${API_TOKEN:-}" ]] && echo yes || echo no)
EOF

# Optional probe
url="${API_BASE_URL%/}"
[[ -n "$endpoint" ]] && url="${url}/${endpoint#/}"

set +e
if [[ -n "${API_TOKEN:-}" ]]; then
  http_status="$(curl -sS -o /tmp/whoami.body.$$ -m 10 -w '%{http_code}' \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Accept: application/json" "$url" 2>/dev/null)"
else
  http_status="$(curl -sS -o /tmp/whoami.body.$$ -m 10 -w '%{http_code}' \
    -H "Accept: application/json" "$url" 2>/dev/null)"
fi
curl_exit=$?
set -e

if (( curl_exit != 0 )); then
  echo "Probe:       FAILED (curl exit $curl_exit, $url)"
  rm -f /tmp/whoami.body.$$
  exit 1
fi

echo "Probe URL:   $url"
echo "Probe:       HTTP $http_status"

# If JSON, show a one-line summary of common identity fields
if [[ "$http_status" =~ ^2[0-9][0-9]$ ]] && command -v jq >/dev/null; then
  identity="$(jq -r '
    if type == "object" then
      [.login, .name, .email, .display_name, .username, .id] | map(select(. != null and . != "")) | join(" / ")
    else
      "(non-object response)"
    end
  ' /tmp/whoami.body.$$ 2>/dev/null || true)"
  [[ -n "$identity" && "$identity" != "null" ]] && echo "Identity:    $identity"
fi

rm -f /tmp/whoami.body.$$

_session_log "whoami" "true" "0" "0"
_mixpanel_track "API Discovery Started" "tool=whoami" "http_status=$http_status"
