#!/usr/bin/env bash
# save-view.sh [--scratch [<ns>]] [--client <slug>] <name> "<sql>"
#
# Creates or replaces an Athena view. Every view gets the rp_ framework
# prefix automatically — distinguishes views created by this framework
# from views the BI / data engineering teams may create against the same
# Athena workgroup. Rules #6, #25.
#
# Final view names produced:
#   rp_fact_<entity>_view                 — universal Kimball fact
#   rp_dim_<entity>_view                  — universal Kimball dim
#   rp_ops_<action>_view                  — universal operational cache
#   rp_fact_<entity>_<client>_view        — per-client fact (--client)
#   rp_dim_<entity>_<client>_view         — per-client dim (--client)
#   rp_ops_<action>_<client>_view         — per-client ops cache (--client)
#   rp_scratch_<ns>_<body>_view           — exploratory (--scratch)
#
# Flags:
#   --scratch [<ns>]   Build a scratch_<ns>_<body>_view. <ns> resolves in
#                      priority order: explicit > $ROOT_AGENTS_NAMESPACE >
#                      git email local-part > current git branch (not main).
#   --client <slug>    Insert client slug before _view. Slug must match
#                      ^[a-z][a-z0-9-]*$ (kebab-case). Warns if not in
#                      references/clients.txt.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

scratch_mode=0
scratch_ns=""
client_slug=""
positional=()

# Parse flags. --scratch optionally takes a value as the next arg; if the
# next arg looks like SQL or a view body (not a slug), treat --scratch as
# bare. --client always takes a value.
while (( $# )); do
  case "$1" in
    --scratch)
      scratch_mode=1
      shift
      # Peek at next arg: if it's a valid slug AND there are still >=2 args
      # remaining (name + sql), treat it as the namespace value.
      if [[ $# -ge 3 && "${1:-}" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]]; then
        scratch_ns="$1"
        shift
      fi
      ;;
    --client)
      client_slug="${2:-}"
      shift 2
      ;;
    --) shift; positional+=("$@"); break ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

name="${1:-}"
sql="${2:-}"
if [[ -z "$name" || -z "$sql" ]]; then
  echo 'usage: save-view.sh [--scratch [<ns>]] [--client <slug>] <name> "<sql>"' >&2
  exit 64
fi

slugify() {
  # lowercase; replace anything outside [a-z0-9-] with -; collapse; trim.
  # Underscores become hyphens so the slug stays single-token.
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

check_client_registry() {
  local slug="$1"
  local registry="$AGENTS_ROOT/references/clients.txt"
  if [[ ! -f "$registry" ]]; then
    echo "warning: references/clients.txt does not exist; can't verify client slug" >&2
    return 0
  fi
  if ! grep -Eq "^[[:space:]]*${slug}([[:space:]]|#|$)" "$registry"; then
    cat >&2 <<EOF
warning: client '$slug' not in references/clients.txt
         if this is genuinely a new client, add the slug + a one-line note
         to that file in this same commit.
EOF
  fi
}

# Build the final name based on flags
if (( scratch_mode )); then
  if [[ -n "$client_slug" ]]; then
    echo "error: --scratch and --client are mutually exclusive" >&2
    echo "  (scratch views are exploratory; promote to per-client once stable)" >&2
    exit 64
  fi
  resolve_scratch_ns
  body="${name%_view}"
  name="scratch_${scratch_ns}_${body}_view"
elif [[ -n "$client_slug" ]]; then
  validate_slug "$client_slug" "client slug"
  check_client_registry "$client_slug"
  body="${name%_view}"
  name="${body}_${client_slug}_view"
else
  # No flags — bare name. Append _view if missing.
  [[ "$name" != *_view ]] && name="${name}_view"
fi

# Strip any user-supplied rp_ to check the inner prefix uniformly, then
# auto-prepend rp_. Idempotent — same input always produces the same output.
inner_name="$name"
[[ "$inner_name" == rp_* ]] && inner_name="${inner_name#rp_}"

case "$inner_name" in
  fact_*_view|dim_*_view|ops_*_view|scratch_*_view) : ;;
  *)
    cat >&2 <<EOF
error: view name must start with fact_, dim_, ops_, or scratch_ after the
rp_ framework prefix (got inner: $inner_name)
  fact_/dim_     -> bi-view skill (Kimball analytical layer)
  ops_           -> ops-dataset skill (action-oriented cache)
  scratch_<ns>_  -> exploratory; rerun with --scratch [<ns>]

For per-client views, use --client <slug>:
  save-view.sh --client acme fact_invoice "<sql>"
  -> rp_fact_invoice_acme_view
EOF
    exit 64
    ;;
esac

name="rp_$inner_name"

require_env
qid="$(run_athena "CREATE OR REPLACE VIEW \"$name\" AS $sql")"
echo "view created: $name (query=$qid)"
