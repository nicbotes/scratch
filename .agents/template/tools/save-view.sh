#!/usr/bin/env bash
# save-view.sh [--scratch [<ns>]] [--db <path>] <name> "<sql>"
#
# Creates or replaces a DuckDB view in main.duckdb. Enforces the framework
# naming convention (rule #6):
#   bi_<entity>_view            — analytical layer (Kimball discipline)
#   ops_<action>_view           — operational / action-oriented cache
#   scratch_<ns>_<body>_view    — exploratory; namespace required
#
# Flags:
#   --scratch [<ns>]   Build a scratch_<ns>_<body>_view. <ns> resolves in
#                      priority order: explicit > $ROOT_AGENTS_NAMESPACE >
#                      git email local-part > current git branch (not main).

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

scratch_mode=0
scratch_ns=""
db_override=""
positional=()

while (( $# )); do
  case "$1" in
    --scratch)
      scratch_mode=1
      shift
      if [[ $# -ge 3 && "${1:-}" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]]; then
        scratch_ns="$1"
        shift
      fi
      ;;
    --db) db_override="$2"; shift 2 ;;
    --) shift; positional+=("$@"); break ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

name="${1:-}"
sql="${2:-}"
if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: save-view.sh [--scratch [<ns>]] [--db <path>] <name> "<sql>"' >&2
  exit 64
fi

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//'
}

validate_slug() {
  local s="$1" kind="${2:-slug}"
  if [[ ! "$s" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]]; then
    echo "error: $kind '$s' must match ^[a-z0-9][a-z0-9-]{0,30}\$" >&2
    echo "  (kebab-case, starts with letter/digit, max 31 chars)" >&2
    exit 64
  fi
}

resolve_scratch_ns() {
  local source=""
  if [[ -n "$scratch_ns" ]]; then
    scratch_ns="$(slugify "$scratch_ns")"
    source="flag"
  elif [[ -n "${ROOT_AGENTS_NAMESPACE:-}" ]]; then
    scratch_ns="$(slugify "$ROOT_AGENTS_NAMESPACE")"
    source="env"
  else
    local email branch
    email="$(git config user.email 2>/dev/null || true)"
    if [[ -n "$email" ]]; then
      scratch_ns="$(slugify "${email%@*}")"
      source="git-email"
    else
      branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      if [[ -n "$branch" && "$branch" != "main" && "$branch" != "master" && "$branch" != "HEAD" ]]; then
        scratch_ns="$(slugify "$branch")"
        source="git-branch"
      fi
    fi
  fi

  if [[ -z "$scratch_ns" ]]; then
    cat >&2 <<'EOF'
error: --scratch requires a namespace and none could be resolved.
Provide one of, in priority order:
  1. --scratch <ns>                       (explicit, e.g. --scratch nic)
  2. ROOT_AGENTS_NAMESPACE=<ns>           (env var for the session)
  3. git config user.email                (uses local-part before @)
  4. git rev-parse --abbrev-ref HEAD      (when not on main/master)
Slug rule: ^[a-z0-9][a-z0-9-]{0,30}$
EOF
    exit 64
  fi

  validate_slug "$scratch_ns" "namespace slug"
  if [[ "$source" != "flag" ]]; then
    printf 'using scratch namespace: %s (source: %s)\n' "$scratch_ns" "$source" >&2
  fi
}

# Build the final name
if (( scratch_mode )); then
  resolve_scratch_ns
  body="${name%_view}"
  name="scratch_${scratch_ns}_${body}_view"
else
  [[ "$name" != *_view ]] && name="${name}_view"
fi

case "$name" in
  bi_*_view|ops_*_view|scratch_*_view) : ;;
  *)
    cat >&2 <<EOF
error: view name must start with bi_, ops_, or scratch_ and end with _view
  bi_<entity>_view            — analytical (bi-view skill)
  ops_<action>_view           — operational (ops-dataset skill)
  scratch_<ns>_<body>_view    — exploratory (rerun with --scratch [<ns>])
got: $name
EOF
    exit 64
    ;;
esac

command -v duckdb >/dev/null || { echo "error: duckdb not on PATH" >&2; exit 64; }
db_path="${db_override:-$DUCKDB_PATH}"
mkdir -p "$(dirname "$db_path")"

start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
duckdb "$db_path" -c "CREATE OR REPLACE VIEW \"$name\" AS $sql;"
end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
ms=$(( end_ms - start_ms ))

case "$name" in
  bi_*)      view_type=bi ;;
  ops_*)     view_type=ops ;;
  scratch_*) view_type=scratch ;;
  *)         view_type=other ;;
esac

_session_log "save-view" "true" "$ms" "0"
_mixpanel_track "View Saved" "view_name=$name" "tier=$view_type" \
  "scratch=$([[ $scratch_mode -eq 1 ]] && echo true || echo false)"

echo "view created: $name (db=$db_path)"
