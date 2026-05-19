---
name: whoami
description: Resolve which Root org the current AWS credentials and ROOT_ORG_ID point at, by querying the organizations table. Use at session start, whenever ROOT_ORG_ID may have changed, or whenever the user asks "which org am I in?". Do NOT use if you've already called it this session and ROOT_ORG_ID hasn't changed.
---

# Skill: whoami

Identifies the active organization. The four printed lines (`Org`, `Org ID`, `Region`, `Env`) are the anchor every later answer in the session refers back to — print them once at session start.

## Steps

1. Confirm the required env vars are set: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `ROOT_ORG_ID`, `ROOT_ATHENA_S3_BUCKET`. If anything is missing, point the user at `references/env-vars.md`.
2. Run:
   ```bash
   bash .agents/tools/whoami.sh
   ```
3. If the script exits non-zero, the current creds don't have access to the workgroup named `$ROOT_ORG_ID`. Don't retry — surface the failure and ask the user to verify the keypair against the dashboard.

## Reference

The script runs `SELECT organization_id, name FROM organizations WHERE organization_id = '$ROOT_ORG_ID'`. The `organization_id` is the same string used as the Athena workgroup, the schema/database, and the S3 results prefix.

→ Next: `explore-schema` (what tables exist) or jump straight to `run-query` / `analyst-workflow`.
