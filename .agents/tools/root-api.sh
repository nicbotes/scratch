#!/usr/bin/env bash
# root-api.sh <METHOD> <path> [--data '<json>']
#
# Wraps curl against the Root API. Independent of AWS env vars.
# Reads ROOT_API_KEY from env, or from a line matching ROOT_API_KEY= in
# ./.root-auth (the convention used by /rp-setup).
#
# Examples:
#   bash .agents/tools/root-api.sh GET /v1/organizations
#   bash .agents/tools/root-api.sh GET /v1/policies/abc-123
#   bash .agents/tools/root-api.sh POST /v1/something --data '{"foo":"bar"}'

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

method=""
path=""
data=""
max_bytes="$ROOT_AGENTS_MAX_BYTES"
no_truncate=0
positional=()

while (( $# )); do
  case "$1" in
    --data)        data="$2";        shift 2 ;;
    --max-bytes)   max_bytes="$2";   shift 2 ;;
    --no-truncate) no_truncate=1;    shift ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

method="${1:-}"
path="${2:-}"

if [[ -z "$method" || -z "$path" ]]; then
  echo "usage: root-api.sh <METHOD> <path> [--data '<json>'] [--max-bytes N] [--no-truncate]" >&2
  exit 64
fi

if ! [[ "$max_bytes" =~ ^[0-9]+$ ]]; then
  echo "error: --max-bytes expects an integer (got: $max_bytes)" >&2
  exit 64
fi

# Resolve API key: env first, then .root-auth in cwd, then parent of cwd.
if [[ -z "${ROOT_API_KEY:-}" ]]; then
  for candidate in ./.root-auth ../.root-auth; do
    if [[ -f "$candidate" ]]; then
      key="$(grep -E '^ROOT_API_KEY=' "$candidate" | head -1 | cut -d= -f2-)"
      if [[ -n "$key" ]]; then
        ROOT_API_KEY="$key"
        export ROOT_API_KEY
        break
      fi
    fi
  done
fi

if [[ -z "${ROOT_API_KEY:-}" ]]; then
  echo "error: ROOT_API_KEY is not set and no .root-auth file found." >&2
  echo "Generate a key at Root Dashboard → Workbench → API Keys." >&2
  echo "See .agents/references/env-vars.md." >&2
  exit 64
fi

base="${ROOT_API_BASE_URL:-https://api.rootplatform.com}"
# Strip a trailing slash on base, ensure path starts with one
base="${base%/}"
[[ "$path" == /* ]] || path="/$path"
url="$base$path"

command -v curl >/dev/null || { echo "error: curl not on PATH" >&2; exit 64; }

_debug "root-api: $method $url"

start_ms="$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')"

if [[ -n "$data" ]]; then
  resp="$(curl -sS --fail -X "$method" \
    -H "Authorization: Bearer $ROOT_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$data" \
    "$url")"
else
  resp="$(curl -sS --fail -X "$method" \
    -H "Authorization: Bearer $ROOT_API_KEY" \
    "$url")"
fi

end_ms="$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

# Session log (no key material — only method, path, ms)
dir="$AGENTS_ROOT/sessions"
mkdir -p "$dir"
sid="$(_session_id)"
printf '{"ts":"%s","session":"%s","tool":"root-api","ok":true,"method":"%s","path":"%s","ms":%s}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$method" "$path" "$ms" \
  >> "$dir/$sid.jsonl"

resp_bytes=${#resp}
if (( no_truncate == 0 )) && (( resp_bytes > max_bytes )); then
  # Print first $max_bytes bytes, then a loud footer to stderr.
  printf '%s' "${resp:0:$max_bytes}"
  echo
  cat >&2 <<EOF
... truncated at $max_bytes of $resp_bytes bytes.
Re-run with --max-bytes <N> or --no-truncate, or pipe through 'jq .field'
to extract just the part you need.
EOF
  _session_log_extra "root-api" "byte_cap_hit=true" "bytes=$resp_bytes" "capped_at=$max_bytes"
else
  printf '%s\n' "$resp"
fi
