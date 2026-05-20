# Proposal 04 — New tool: `tools/glue-describe.sh`

**Source feedback note (`feedback/2026-05-19.jsonl`):**
- `2026-05-19T13:44:00Z` (tool-gap) — `aws glue get-tables --database-name $ROOT_ORG_ID` reads the Glue metastore directly. No Athena query execution, no bytes scanned, instant. Replaces the `information_schema.columns` workaround used to regenerate `references/schema.md`.

## Reason

Schema introspection today goes through Athena (`SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = '$ROOT_ORG_ID'`). Per `references/schema.md` line 4, this is the documented refresh command. It works but pays for itself: every refresh starts an Athena query, polls for completion, scans bytes (small but non-zero), and incurs ~1-2s overhead.

The Glue metastore is the source of truth. `aws glue get-tables --database-name <org>` answers the same question in ~200ms with zero Athena bytes scanned. It's the right tool for the job.

Adding this also unblocks Proposal 05 (env-column guard in `profile-table.sh`) — the guard needs a cheap "does this table have an `environment` column?" query, and `glue-describe.sh --columns <table>` is the natural answer.

## Current state

No `glue-describe.sh` exists in `tools/`. Schema refresh runs through `athena-query.sh "SELECT ... FROM information_schema.columns ..."` as documented in `references/schema.md:4`.

`profile-table.sh:34` does `DESCRIBE "$table"` via Athena — same overhead, same workaround.

## Proposed change

### New file: `.agents/tools/glue-describe.sh`

```bash
#!/usr/bin/env bash
# glue-describe.sh                              list all tables in the org's Glue database
# glue-describe.sh <table>                      list columns + types for one table
# glue-describe.sh --columns <table>            same as above, machine-readable (tab-separated)
# glue-describe.sh --has-column <table> <col>   exit 0 if column exists, 1 if not (silent)
# glue-describe.sh --schema-md                  emit a fresh references/schema.md skeleton
#
# Reads from the AWS Glue metastore directly — no Athena query, no bytes
# scanned. The metastore is the source of truth that Athena's
# information_schema.columns view wraps.

set -euo pipefail
source "$(dirname "$0")/_lib.sh"
require_env

mode="list"
table=""
column=""

while (( $# )); do
  case "$1" in
    --columns) mode="columns"; table="${2:-}"; shift 2 ;;
    --has-column) mode="has-column"; table="${2:-}"; column="${3:-}"; shift 3 ;;
    --schema-md) mode="schema-md"; shift ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)
      if [[ -z "$table" ]]; then
        table="$1"; mode="describe"
      fi
      shift
      ;;
  esac
done

case "$mode" in
  list)
    aws glue get-tables --database-name "$ROOT_ORG_ID" \
      --query 'TableList[].Name' --output text | tr '\t' '\n' | sort
    ;;

  describe|columns)
    if [[ -z "$table" ]]; then
      echo "usage: glue-describe.sh [--columns] <table>" >&2; exit 64
    fi
    if [[ "$mode" == "describe" ]]; then
      echo "=== $table (org=$ROOT_ORG_ID) ==="
    fi
    aws glue get-table --database-name "$ROOT_ORG_ID" --name "$table" \
      --query 'Table.StorageDescriptor.Columns[].[Name,Type]' \
      --output text
    ;;

  has-column)
    if [[ -z "$table" || -z "$column" ]]; then
      echo "usage: glue-describe.sh --has-column <table> <column>" >&2; exit 64
    fi
    aws glue get-table --database-name "$ROOT_ORG_ID" --name "$table" \
      --query "Table.StorageDescriptor.Columns[?Name=='$column'].Name" \
      --output text | grep -q . && exit 0 || exit 1
    ;;

  schema-md)
    # Emit a markdown skeleton suitable for piping into references/schema.md.
    # Does not replace human-curated notes; meant as a diff anchor.
    echo "# Reference: Athena Schema — Full Data Dictionary"
    echo
    echo "Generated from AWS Glue metastore on $(date -u +%Y-%m-%d)."
    echo "Refresh with: \`bash .agents/tools/glue-describe.sh --schema-md > references/schema.md.new\`"
    echo
    aws glue get-tables --database-name "$ROOT_ORG_ID" \
      --query 'TableList[].[Name]' --output text | tr '\t' '\n' | sort | while read -r t; do
      [[ -z "$t" ]] && continue
      echo "### \`$t\`"
      echo
      echo "| Column | Type |"
      echo "|---|---|"
      aws glue get-table --database-name "$ROOT_ORG_ID" --name "$t" \
        --query 'Table.StorageDescriptor.Columns[].[Name,Type]' --output text \
        | awk -F'\t' '{printf "| `%s` | %s |\n", $1, $2}'
      echo
    done
    ;;
esac
```

Make executable: `chmod +x .agents/tools/glue-describe.sh`.

## Notes

- IAM: requires `glue:GetTables` and `glue:GetTable` on the org's database. Confirm the existing Data Adapter key already grants these (it has to — Athena queries against `information_schema.columns` succeed today, which goes through Glue under the hood). If not, that's a third platform-side ask.
- The `--schema-md` mode is a *skeleton*, not a drop-in replacement. The current `references/schema.md` has hand-curated notes (PII tags, `No environment column` annotations, JSONB shape hints). Use the skeleton as a diff anchor: regenerate, diff against current, merge the new column additions, keep the curation.

## Test

```bash
# List tables in org
bash .agents/tools/glue-describe.sh
# → policies, policyholders, payments, claims, ... (sorted)

# Describe one table
bash .agents/tools/glue-describe.sh users
# → id  varchar
#   email  varchar
#   ... (tab-separated)

# Predicate check (used by Proposal 05)
bash .agents/tools/glue-describe.sh --has-column policies environment && echo yes  # → yes
bash .agents/tools/glue-describe.sh --has-column users    environment || echo no   # → no

# Schema skeleton
bash .agents/tools/glue-describe.sh --schema-md > /tmp/schema.md.new
diff .agents/references/schema.md /tmp/schema.md.new | head -50   # column additions visible
```

Acceptance: all four modes work; `--has-column` exit code is reliable enough to drive Proposal 05.
