#!/usr/bin/env bash
# feedback-note.sh --kind <kind> --target <file> --note "<msg>"
# Appends one JSON line to .agents/feedback/<session>.jsonl.
# See .agents/references/feedback-schema.md for the valid --kind values.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

kind=""
target=""
note=""

while (( $# )); do
  case "$1" in
    --kind)   kind="$2";   shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --note)   note="$2";   shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

if [[ -z "$kind" || -z "$target" || -z "$note" ]]; then
  echo 'usage: feedback-note.sh --kind <kind> --target <file> --note "<msg>"' >&2
  exit 64
fi

case "$kind" in
  description-miss|reference-thrash|tool-gap|rule-missing|progressive-disclosure|success-pattern) : ;;
  *)
    echo "error: --kind must be one of: description-miss reference-thrash tool-gap rule-missing progressive-disclosure success-pattern" >&2
    echo "see .agents/references/feedback-schema.md" >&2
    exit 64
    ;;
esac

dir="$AGENTS_ROOT/feedback"
mkdir -p "$dir"
sid="$(_session_id)"
hash="$(api_base_hash)"

escape_json() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))' 2>/dev/null \
    || printf '"%s"' "$(sed 's/\\/\\\\/g; s/"/\\"/g' <<<"$1")"
}

n_target="$(printf '%s' "$target" | escape_json)"
n_note="$(printf '%s' "$note"     | escape_json)"

printf '{"ts":"%s","session":"%s","kind":"%s","target":%s,"note":%s,"api_base_hash":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "$kind" "$n_target" "$n_note" "$hash" \
  >> "$dir/$sid.jsonl"

_mixpanel_track "Feedback Noted" "kind=$kind" "target=$target" \
  "length_chars=${#note}"

echo "feedback noted: $kind -> $target"
