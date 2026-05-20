#!/usr/bin/env bash
# save-view.sh [--scratch [<ns>]] <name> "<sql>"
# Creates or replaces an Athena view. Enforces:
#   - name ends in _view (Root platform requirement)
#   - name starts with one of:
#       fact_  | dim_   — Kimball analytical layer (bi-view)
#       ops_           — action-oriented operational cache (ops-dataset)
#       scratch_<ns>_  — exploratory, namespace required (analyst-workflow)
#
# Without --scratch, <name> must already carry a canonical prefix (fact_/dim_/ops_).
# With --scratch [<ns>], <name> is treated as the BODY and the tool builds
# scratch_<ns>_<name>_view. <ns> resolves in priority order:
#   1. explicit value after --scratch
#   2. $ROOT_AGENTS_NAMESPACE
#   3. git email local-part (text before @)
#   4. current git branch (only if not main/master)

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

scratch_mode=0
scratch_ns=""

# Parse flags. --scratch optionally takes a value as the next arg; if the next
# arg looks like SQL or a view body (not a slug), treat --scratch as bare.
if [[ "${1:-}" == "--scratch" ]]; then
  scratch_mode=1
  shift
  # Peek at next arg: if it's a valid slug AND there are still >=2 args after
  # it, treat it as the namespace value. Otherwise it's the body.
  if [[ $# -ge 3 && "${1:-}" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]]; then
    scratch_ns="$1"
    shift
  fi
fi

name="${1:-}"
sql="${2:-}"
if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: save-view.sh [--scratch [<ns>]] <name> "<sql>"' >&2
  exit 64
fi

slugify() {
  # lowercase; replace anything outside [a-z0-9-] with -; collapse; trim.
  # Underscores become hyphens so the slug stays single-token (ns must not
  # contain underscores — list-views.sh splits on _ to extract <ns>).
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//'
}

validate_slug() {
  local s="$1"
  if [[ ! "$s" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]]; then
    echo "error: namespace slug '$s' must match ^[a-z0-9][a-z0-9-]{0,30}\$" >&2
    echo "  (kebab-case, starts with letter/digit, max 31 chars)" >&2
    exit 64
  fi
}

resolve_scratch_ns() {
  # Priority: explicit > env > git email > non-main branch
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

  validate_slug "$scratch_ns"
  if [[ "$source" != "flag" ]]; then
    printf 'using scratch namespace: %s (source: %s)\n' "$scratch_ns" "$source" >&2
  fi
}

if (( scratch_mode )); then
  resolve_scratch_ns
  # name is the body; strip a trailing _view if the user added one
  body="${name%_view}"
  name="scratch_${scratch_ns}_${body}_view"
else
  # Append _view if missing (forgiving) — but reject if a different suffix is used
  if [[ "$name" != *_view ]]; then
    name="${name}_view"
  fi
fi

case "$name" in
  fact_*_view|dim_*_view|ops_*_view|scratch_*_view) : ;;
  *)
    cat >&2 <<EOF
error: view name must start with fact_, dim_, ops_, or scratch_ (got: $name)
  fact_/dim_   -> bi-view skill (Kimball analytical layer)
  ops_         -> ops-dataset skill (action-oriented cache)
  scratch_<ns> -> exploratory; rerun with --scratch [<ns>]
EOF
    exit 64
    ;;
esac

require_env
qid="$(run_athena "CREATE OR REPLACE VIEW \"$name\" AS $sql")"
echo "view created: $name (query=$qid)"
