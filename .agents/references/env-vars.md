# Reference: Environment Variables

Every tool under `.agents/tools/` reads these. They are the only way credentials reach the framework — no MCP, no `~/.aws/credentials`, no profile files.

## Required

| Var | Source | Notes |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Root Dashboard → Data Management → Data Adapter → Generate Access Key | One key per org (per credential) |
| `AWS_SECRET_ACCESS_KEY` | Same place | Treat as a secret. Never paste into chat, queries, manifests, or commit logs |
| `AWS_REGION` | Same place ("AWS Region") | e.g. `eu-west-1`, `us-east-1` |
| `ROOT_ORG_ID` | Same place ("Athena Schema" / "Athena Workgroup") | These three values are identical — the org id |
| `ROOT_ATHENA_S3_BUCKET` | Same place ("S3 Output Location") | The bucket name (without `s3://` and without the trailing `<org-id>/`). Tools derive `s3://$BUCKET/$ROOT_ORG_ID/` automatically |

## Optional

| Var | Default | Purpose |
|---|---|---|
| `ROOT_ENV` | `production` | Used in every `WHERE environment = '...'` filter |
| `ROOT_ORG_IDS` | unset | Comma-separated list for `multi-org-query` |
| `ROOT_AGENTS_DEBUG` | `0` | `1` prints resolved `aws athena` commands, scanned bytes, and query ids to stderr |
| `ROOT_AGENTS_SESSION_ID` | UTC date | Namespace for `.agents/sessions/<id>.jsonl` and `.agents/feedback/<id>.jsonl` |
| `ROOT_API_KEY` | from `.root-auth` if present | Root Dashboard API key. Used by `root-api.sh` for fetching module schemas etc. **Independent of AWS creds** — a different surface |
| `ROOT_API_BASE_URL` | `https://api.rootplatform.com` | Base URL for the Root API. The exact endpoint paths under `/v1/...` (e.g. for product-module-definitions) should be confirmed on first call and recorded in the learned skill that derives the JSONB schema |
| `ROOT_AGENTS_MAX_ROWS` | `1000` | Cap for rows printed to stdout by `athena-query.sh`. Above this, output auto-truncates with a footer naming the escape valves (rules.md #23) |
| `ROOT_AGENTS_MAX_BYTES` | `200000` (200 KB) | Cap for `root-api.sh` response bodies and any future byte-based printer |

## Walkthrough

1. Sign in to the Root Dashboard for the org you want to query.
2. Data Management → Data Adapter → **Generate Access Key**.
3. The modal shows five things you need: `AWS Access Key ID`, `AWS Secret Access Key`, `AWS Region`, `Athena Schema` (= the org id), `S3 Output Location` (e.g. `s3://root-athena-prod-results/8f3c.../`).
4. Strip the `s3://` and the org-id path from the bucket — keep just the bucket name (`root-athena-prod-results`).
5. Export in your shell:
   ```bash
   export AWS_ACCESS_KEY_ID="AKIA..."
   export AWS_SECRET_ACCESS_KEY="..."
   export AWS_REGION="eu-west-1"
   export ROOT_ORG_ID="8f3c..."          # = Athena Schema = Workgroup = S3 prefix
   export ROOT_ATHENA_S3_BUCKET="root-athena-prod-results"
   export ROOT_ENV="production"
   ```
6. Sanity check:
   ```bash
   bash .agents/tools/whoami.sh
   ```

## Multiple orgs

If a single keypair has access to multiple orgs (common for parent organizations):

```bash
export ROOT_ORG_IDS="8f3c...,a921...,b4e0..."
bash .agents/tools/list-orgs.sh   # confirms what's actually accessible
```

To switch the active org in-session, just `export ROOT_ORG_ID=<id>` again — every subsequent tool call picks it up.

## Security notes

- Never commit a `.env` file, your shell history, or anything containing `AWS_SECRET_ACCESS_KEY`.
- The `_lib.sh` redactor never includes credentials in session logs or feedback notes (only the org id and env).
- Evidence manifests (`.agents/evidence/*/manifest.json`) include the query id, not the credentials. That folder is also gitignored.
