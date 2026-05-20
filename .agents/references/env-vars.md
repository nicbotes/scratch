# Reference: Environment Variables

Every tool under `.agents/tools/` reads these. They are the only way credentials reach the framework — no MCP, no `~/.aws/credentials`, no profile files.

## Required

| Var | Source | Notes |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Root Dashboard → Data Management → Data Adapter → Generate Access Key | One key per org (per credential) |
| `AWS_SECRET_ACCESS_KEY` | Same place | Treat as a secret. Never paste into chat, queries, manifests, or commit logs |
| `ROOT_ORG_ID` | Same place ("Athena Schema" / "Athena Workgroup") | These three values are identical — the org id |
| `ROOT_ATHENA_S3_BUCKET` | Same place ("S3 Output Location") | The bucket name (without `s3://` and without the trailing `<org-id>/`). Tools derive `s3://$BUCKET/$ROOT_ORG_ID/` automatically |

## Optional

| Var | Default | Purpose |
|---|---|---|
| `AWS_REGION` | auto-detected from `ROOT_ATHENA_S3_BUCKET` | Region of the org's Athena. `_lib.sh::require_env` calls `aws s3api get-bucket-location` on first tool invocation when unset and caches the result. Export explicitly only to override (e.g. cross-region replica). |
| `ROOT_ENV` | `production` | Used in every `WHERE environment = '...'` filter |
| `ROOT_ORG_IDS` | unset | Comma-separated list for `multi-org-query` / `cross-org-explore` |
| `ROOT_ATHENA_S3_BUCKET_BY_ORG` | unset | `uuid:bucket,uuid:bucket` overrides. Consulted by `cross-org-pull.sh` per iteration when an org's S3 output bucket differs from `ROOT_ATHENA_S3_BUCKET`. Orgs not in the map fall back to the default |
| `AWS_REGION_BY_ORG` | unset | `uuid:region,uuid:region` overrides. Same shape and use as the bucket map, for orgs in a different region than `AWS_REGION` |
| `ROOT_AGENTS_DEBUG` | `0` | `1` prints resolved `aws athena` commands, scanned bytes, and query ids to stderr |
| `ROOT_AGENTS_SESSION_ID` | UTC date | Namespace for `.agents/sessions/<id>.jsonl` and `.agents/feedback/<id>.jsonl` |
| `ROOT_API_KEY` | from `.root-auth` if present | Root Dashboard API key. Used by `root-api.sh` for fetching module schemas etc. **Independent of AWS creds** — a different surface |
| `ROOT_API_BASE_URL` | `https://api.rootplatform.com` | Base URL for the Root API. The exact endpoint paths under `/v1/...` (e.g. for product-module-definitions) should be confirmed on first call and recorded in the learned skill that derives the JSONB schema |
| `ROOT_AGENTS_MAX_ROWS` | `1000` | Cap for rows printed to stdout by `athena-query.sh`. Above this, output auto-truncates with a footer naming the escape valves (rules.md #23) |
| `ROOT_AGENTS_MAX_BYTES` | `200000` (200 KB) | Cap for `root-api.sh` response bodies and any future byte-based printer |

## Local tooling

Two binaries are required on `$PATH`:

| Tool | Install | Why |
|---|---|---|
| `aws` CLI v2 | `brew install awscli` | Every tool under `.agents/tools/` shells out to it |
| `duckdb` | `brew install duckdb` | Local pre-aggregation (`tools/duckdb-query.sh`, rules.md #24, `skills/cross-org-explore.md`) |

`python3` is also assumed present (macOS ships it) — used by `--format json/jsonl/tsv` in `athena-query.sh` and by the timing fallback in `duckdb-query.sh`.

## Walkthrough

1. Sign in to the Root Dashboard for the org you want to query.
2. Data Management → Data Adapter → **Generate Access Key**.
3. The modal shows five things; you only need four: `AWS Access Key ID`, `AWS Secret Access Key`, `Athena Schema` (= the org id), `S3 Output Location` (e.g. `s3://root-athena-prod-results/8f3c.../`). The fifth — `AWS Region` — is auto-detected from the bucket on first tool call; only export it manually to override.
4. Strip the `s3://` and the org-id path from the bucket — keep just the bucket name (`root-athena-prod-results`).
5. Copy the committed template and fill it in:
   ```bash
   cp .agents/.env.example .agents/.env   # one time
   # edit .agents/.env with the four values from step 3–4
   source .agents/.env                     # each session
   ```
   `.env` is gitignored alongside `.root-auth`. Sourcing it once per shell beats re-exporting every session.
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

### Orgs on different buckets or regions

Most multi-org setups share one bucket and one region across all orgs in `ROOT_ORG_IDS`. When that doesn't hold — e.g. one org's data adapter was provisioned against a different S3 bucket — supply override maps so `cross-org-pull.sh` can switch destination per iteration:

```bash
export ROOT_ATHENA_S3_BUCKET="bucket-default"   # used for orgs NOT in the map
export AWS_REGION="eu-west-1"                   # ditto
export ROOT_ATHENA_S3_BUCKET_BY_ORG="<uuid-x>:bucket-other"
export AWS_REGION_BY_ORG="<uuid-x>:us-east-1"   # only set if region also differs
```

The single multi-org access key handles auth across all orgs; the maps only switch the per-org destination values that the Athena workgroup expects. Orgs not in a map fall back to the default env var.

## Security notes

- Never commit a `.env` file, your shell history, or anything containing `AWS_SECRET_ACCESS_KEY`.
- The `_lib.sh` redactor never includes credentials in session logs or feedback notes (only the org id and env).
- Evidence manifests (`.agents/evidence/*/manifest.json`) include the query id, not the credentials. That folder is also gitignored.
