#!/usr/bin/env bash
# learn-skill.sh <name> --description "<frontmatter>" \
#                       (--body "<inline>" | --body-file <path>) \
#                       [--from-task "<one-line>"]
#
# Persists an agent-discovered workflow as a learned skill under
# .agents/skills/learned/<name>.md. The frontmatter carries provenance
# (when, in which session, from what task). The body is prefixed with a
# "learned, not yet curated" banner so the routing agent flags it.
#
# Rejects if a canonical skills/<name>.md already exists — that case is an
# observe-note proposing an edit, not a shadow skill.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

name=""
description=""
body=""
body_file=""
from_task=""

# Positional name, then flags
if [[ "${1:-}" && "${1:-}" != --* ]]; then
  name="$1"
  shift
fi

while (( $# )); do
  case "$1" in
    --description) description="$2"; shift 2 ;;
    --body)        body="$2";        shift 2 ;;
    --body-file)   body_file="$2";   shift 2 ;;
    --from-task)   from_task="$2";   shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

if [[ -z "$name" || -z "$description" ]]; then
  echo 'usage: learn-skill.sh <name> --description "..." (--body "..." | --body-file <path>) [--from-task "..."]' >&2
  exit 64
fi
if [[ -z "$body" && -z "$body_file" ]]; then
  echo 'error: provide --body "..." or --body-file <path>' >&2
  exit 64
fi
if [[ ! "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "error: name must be lowercase alphanumeric with - or _ (got: $name)" >&2
  exit 64
fi

canonical="$AGENTS_ROOT/skills/$name.md"
if [[ -e "$canonical" ]]; then
  echo "error: a canonical skill already exists at $canonical" >&2
  echo "Don't shadow it. Use 'observe --kind progressive-disclosure --target skills/$name.md'" >&2
  echo "to propose an edit through retro instead." >&2
  exit 64
fi

target_dir="$AGENTS_ROOT/skills/learned"
mkdir -p "$target_dir"
target="$target_dir/$name.md"

if [[ -n "$body_file" ]]; then
  [[ -f "$body_file" ]] || { echo "error: --body-file not found: $body_file" >&2; exit 64; }
  body="$(cat "$body_file")"
fi

sid="$(_session_id)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  printf -- '---\n'
  printf 'name: %s\n' "$name"
  printf 'description: %s\n' "$description"
  printf 'learned: true\n'
  printf 'learned_at: %s\n' "$ts"
  printf 'learned_in_session: %s\n' "$sid"
  if [[ -n "$from_task" ]]; then
    printf 'learned_from_task: %s\n' "$from_task"
  fi
  printf -- '---\n\n'
  printf '> **Learned skill** — written by the agent in-session, not yet curated. Treat the steps as a hypothesis. Retro will propose promotion to canonical `.agents/skills/` after review.\n\n'
  printf '%s\n' "$body"
} > "$target"

# Session log
dir="$AGENTS_ROOT/sessions"
mkdir -p "$dir"
printf '{"ts":"%s","session":"%s","tool":"learn-skill","ok":true,"name":"%s"}\n' \
  "$ts" "$sid" "$name" >> "$dir/$sid.jsonl"

_mixpanel_track "Skill Learned" "skill_name=$name" \
  "from_task=${from_task:-none}"

echo "learned skill written: $target"
