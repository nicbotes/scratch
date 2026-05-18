---
name: multi-org-query
description: Run the same analytical query across multiple orgs by looping over ROOT_ORG_IDS and re-exporting ROOT_ORG_ID per iteration. Use when the user asks "across all our orgs" and the credentials have access. Do NOT use for compliance (compliance is per-org, see rules.md #16), when only one org is in scope, or for operational queues (each org's ops_*_view is independent).
---

# Skill: multi-org-query

Fan-out without MCP, without Athena federation. Just a shell loop, one `ROOT_ORG_ID` at a time, results stitched together with an `org_name` column prepended.

## Steps

1. Confirm `ROOT_ORG_IDS` is set. If not, run `list-orgs.sh` to discover what the creds can see and ask the user which orgs are in scope.
2. Save the analytical SQL into a file (Heredoc or `sql.txt`) so each iteration runs the same statement byte-for-byte.
3. Loop:
   ```bash
   IFS=',' read -ra orgs <<<"$ROOT_ORG_IDS"
   for org in "${orgs[@]}"; do
     export ROOT_ORG_ID="$org"
     name="$(bash .agents/tools/whoami.sh | awk -F: '/^Org:/{sub(/^[[:space:]]+/,"",$2); print $2}')"
     bash .agents/tools/athena-query.sh "$(cat sql.txt)" \
       | awk -v org="$org" -v n="$name" 'NR==1{print "org_id,org_name,"$0; next} {print org","n","$0}'
   done
   ```
4. Concatenate the per-org CSVs (skip extra headers after the first) into one consolidated result.
5. Always restore the original `ROOT_ORG_ID` at the end of the loop, or call `whoami` to confirm which org you ended up in.

## Reference

When the fan-out is recurring (e.g. weekly KPI across orgs), the cleanest pattern is one `fact_*_view` per org with identical schema, then a separate top-level aggregator script that does the loop. Don't try to build a single cross-org view inside Athena — each org has its own workgroup.

→ Cross-references: `rules.md` #16 (never fan compliance across orgs).
