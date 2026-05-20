#!/usr/bin/env bash
# migrate-regressions.sh                migrate every flat regressions/*.json
# migrate-regressions.sh --dry-run      preview the move plan, no writes
# migrate-regressions.sh --force        overwrite existing hashed copies
#
# One-off migration tool for legacy regression goldens captured before
# Phase 6's hash-based redaction landed (see DESIGN.md §"Phase 6 additions").
#
# For each .json directly under .agents/regressions/ that still has an
# `org_id` field, this:
#   - hashes the org_id with hash_id() from _lib.sh
#   - rewrites the JSON to drop `org_id` + `query_execution_id`,
#     adding `org_id_hash` in `org_id`'s place
#   - writes to regressions/<org_hash>/<name>.json
#   - removes the legacy flat file
#
# Files already living under a subfolder are skipped (already migrated).
# Refuses to clobber an existing hashed copy unless --force.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

command -v jq >/dev/null || { echo "error: jq is required but not on PATH" >&2; exit 64; }

dry_run=0
force=0

while (( $# )); do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --force)   force=1;   shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)  echo "unexpected argument: $1" >&2; exit 64 ;;
  esac
done

regressions_dir="$AGENTS_ROOT/regressions"
if [[ ! -d "$regressions_dir" ]]; then
  echo "no regressions directory at $regressions_dir — nothing to migrate"
  exit 0
fi

shopt -s nullglob
flat_files=( "$regressions_dir"/*.json )

if (( ${#flat_files[@]} == 0 )); then
  echo "no flat .json files in $regressions_dir — nothing to migrate"
  exit 0
fi

migrated=0
skipped=0
errors=0

for src in "${flat_files[@]}"; do
  name="$(basename "$src" .json)"

  # File must contain `org_id` — otherwise it's already in Phase 6 shape or
  # is some other artefact. Skip with a warning.
  org_id="$(jq -er '.org_id // empty' "$src" 2>/dev/null || true)"
  if [[ -z "$org_id" ]]; then
    echo "skip: $name (no org_id field — already migrated or unexpected shape)" >&2
    (( skipped++ )) || true
    continue
  fi

  org_hash="$(hash_id "$org_id")"
  dst_dir="$regressions_dir/$org_hash"
  dst="$dst_dir/$name.json"

  if [[ -e "$dst" && $force -eq 0 ]]; then
    echo "skip: $name (destination $org_hash/$name.json already exists; pass --force to overwrite)" >&2
    (( skipped++ )) || true
    continue
  fi

  if (( dry_run )); then
    echo "would migrate $name -> $org_hash/$name.json"
    (( migrated++ )) || true
    continue
  fi

  mkdir -p "$dst_dir"

  # Reshape: drop org_id + query_execution_id, add org_id_hash. jq preserves
  # field order, so org_id_hash lands in the same slot org_id used to be in.
  if ! jq --arg h "$org_hash" '
        (. | to_entries | map(
              if .key == "org_id" then {key:"org_id_hash", value:$h}
              elif .key == "query_execution_id" then empty
              else . end
            ) | from_entries)
      ' "$src" > "$dst.tmp"; then
    echo "error: jq transform failed for $name" >&2
    rm -f "$dst.tmp"
    (( errors++ )) || true
    continue
  fi

  mv "$dst.tmp" "$dst"
  rm -f "$src"
  echo "migrated $name -> $org_hash/$name.json"
  (( migrated++ )) || true
done

echo
if (( dry_run )); then
  echo "dry-run summary: $migrated would migrate, $skipped skipped, $errors errors"
else
  echo "summary: $migrated migrated, $skipped skipped, $errors errors"
fi

(( errors == 0 ))
