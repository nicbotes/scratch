#!/usr/bin/env bash
# migrate-view-prefix.sh [--dry-run]
#
# One-shot helper to rename existing Athena views to the rp_ framework
# prefix (rule #6, Phase 8). Idempotent — running it twice is a no-op.
#
# What it does:
#   1. Lists existing views in the active org's Athena database via Glue.
#   2. For any view without an rp_ prefix that otherwise matches the
#      framework's prefix conventions (fact_/dim_/ops_/scratch_),
#      creates a rp_-prefixed alias via CREATE OR REPLACE VIEW.
#   3. Rewrites the `sql` field in regression goldens under
#      .agents/regressions/<org_id_hash>/*.json to reference the renamed
#      view (only when the old reference is present).
#   4. Reports what was changed and what was skipped.
#
# Does NOT drop the old view names — leaving them in place avoids breaking
# downstream consumers (BI tools, dbt staging, ad-hoc queries that pointed
# at the unprefixed names). After consumers have been migrated, drop the
# old names manually with drop-view.sh.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
fi

require_env

# List views via Glue — same surface as list-views.sh, but we filter by
# the framework's prefix conventions ourselves.
echo "Listing views in database '$ROOT_ORG_ID' via Glue..." >&2
all_views="$(aws glue get-tables \
  --database-name "$ROOT_ORG_ID" \
  --query 'TableList[?TableType==`VIRTUAL_VIEW`].Name' \
  --output text 2>/dev/null || echo "")"

if [[ -z "$all_views" ]]; then
  echo "no views found (or Glue access denied)" >&2
  exit 0
fi

# Convert tab-separated names to an array (bash 3.x compatible — no mapfile).
# aws --output text emits multiple names tab-separated on one line.
views=()
while IFS= read -r line; do
  [[ -n "$line" ]] && views+=("$line")
done < <(printf '%s\n' "$all_views" | tr '\t' '\n')

# Filter to framework-managed shapes that need migrating
declare -a to_rename
for v in "${views[@]}"; do
  [[ -z "$v" ]] && continue
  # Skip if already rp_-prefixed (nothing to do)
  [[ "$v" == rp_* ]] && continue
  # Match framework shapes
  case "$v" in
    fact_*_view|dim_*_view|ops_*_view|scratch_*_view)
      to_rename+=("$v")
      ;;
  esac
done

if (( ${#to_rename[@]} == 0 )); then
  echo "all framework views already have rp_ prefix — nothing to migrate" >&2
  exit 0
fi

echo "Found ${#to_rename[@]} view(s) to migrate:" >&2
for v in "${to_rename[@]}"; do
  echo "  $v -> rp_$v" >&2
done
echo

if (( dry_run )); then
  echo "[dry-run] no changes made. Re-run without --dry-run to apply." >&2
  exit 0
fi

# Step 1: create rp_-prefixed aliases in Athena
echo "Creating rp_-prefixed aliases in Athena..." >&2
for v in "${to_rename[@]}"; do
  new_name="rp_$v"
  alias_sql="CREATE OR REPLACE VIEW \"$new_name\" AS SELECT * FROM \"$v\""
  if qid="$(run_athena "$alias_sql" 2>&1)"; then
    echo "  ✓ $new_name (query=$qid)" >&2
  else
    echo "  ✗ failed to create $new_name: $qid" >&2
  fi
done

# Step 2: rewrite regression-golden sql fields
org_hash="$(hash_id "$ROOT_ORG_ID")"
regressions_dir="$AGENTS_ROOT/regressions/$org_hash"
if [[ -d "$regressions_dir" ]]; then
  echo >&2
  echo "Rewriting regression-golden sql fields under $regressions_dir..." >&2
  changed=0
  for golden in "$regressions_dir"/*.json; do
    [[ -f "$golden" ]] || continue
    # Use python3 for safe JSON in-place rewrite
    python3 - "$golden" "${to_rename[@]}" <<'EOF'
import json, sys, re

golden_path = sys.argv[1]
old_names = sys.argv[2:]

with open(golden_path) as f:
    data = json.load(f)

sql = data.get("sql", "")
changed = False
for old in old_names:
    # Match the old name as a word (avoid partial matches like fact_payment
    # inside fact_payments).
    pattern = r"\b" + re.escape(old) + r"\b"
    new = "rp_" + old
    if re.search(pattern, sql):
        sql = re.sub(pattern, new, sql)
        changed = True

if changed:
    data["sql"] = sql
    with open(golden_path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print(f"  ✓ {golden_path}", file=sys.stderr)
EOF
  done
fi

echo >&2
echo "Migration complete." >&2
echo >&2
echo "Next steps:" >&2
echo "  1. Verify renames: bash .agents/tools/list-views.sh | grep ^rp_" >&2
echo "  2. Run goldens:    bash .agents/tools/regression-check.sh --all" >&2
echo "  3. Once downstream consumers have switched to rp_ names, drop the" >&2
echo "     old un-prefixed views manually:" >&2
for v in "${to_rename[@]}"; do
  echo "       bash .agents/tools/drop-view.sh $v" >&2
done
