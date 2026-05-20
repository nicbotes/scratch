# Proposal 02 — AWS_REGION auto-detect from S3 bucket

**Source feedback notes (`feedback/2026-05-19.jsonl`):**
- `2026-05-19T09:05:16Z` (success-pattern) — `AWS_REGION` derivable from `aws s3api get-bucket-location --bucket $ROOT_ATHENA_S3_BUCKET`
- `2026-05-19T09:05:34Z` (rule-missing) — setup should require 4 dashboard values not 5; region inferred automatically before first use

## Reason

The dashboard's "Generate Access Key" modal surfaces five values: access key id, secret, region, org id, S3 bucket. The region is redundant — the S3 bucket already lives in a region, and `aws s3api get-bucket-location` returns it in one cheap unauthenticated-from-Athena-perspective call (it uses the same key pair, just hits S3 instead of Athena). Cutting required setup from 5 to 4 values reduces one manual lookup at session start and one "wrong region" misconfiguration per onboarding.

## Current state

`tools/_lib.sh::require_env` (line 22-35) checks `AWS_REGION` alongside the other four. If unset, it errors out with `error: missing required env vars: AWS_REGION` before any tool can run.

`references/env-vars.md` lists `AWS_REGION` as required (table line 11) and as step 5 of the walkthrough (line 38: `export AWS_REGION="eu-west-1"`).

`AGENTS.md` lists `AWS_REGION` as required (line 15).

`.agents/.env.example` includes `export AWS_REGION="eu-west-1"` as a template entry.

## Proposed changes

### Change 1: `.agents/tools/_lib.sh::require_env`

Patch the function to attempt auto-detection of `AWS_REGION` from `ROOT_ATHENA_S3_BUCKET` before declaring it missing:

```bash
require_env() {
  # If AWS_REGION is unset but ROOT_ATHENA_S3_BUCKET is set + AWS creds present,
  # derive region from the bucket location. Caches in-process via export.
  if [[ -z "${AWS_REGION:-}" && -n "${ROOT_ATHENA_S3_BUCKET:-}" \
        && -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    local detected
    detected="$(aws s3api get-bucket-location --bucket "$ROOT_ATHENA_S3_BUCKET" \
      --query 'LocationConstraint' --output text 2>/dev/null || true)"
    # us-east-1 returns "None" (legacy AWS quirk); also normalise empty
    if [[ -z "$detected" || "$detected" == "None" ]]; then
      detected="us-east-1"
    fi
    if [[ -n "$detected" ]]; then
      export AWS_REGION="$detected"
      _debug "auto-detected AWS_REGION=$AWS_REGION from $ROOT_ATHENA_S3_BUCKET"
    fi
  fi

  local missing=()
  for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION ROOT_ORG_ID ROOT_ATHENA_S3_BUCKET; do
    if [[ -z "${!v:-}" ]]; then
      missing+=("$v")
    fi
  done
  # ... rest unchanged
}
```

**Note on AWS quirk:** `get-bucket-location` returns `"None"` (or empty) for `us-east-1` buckets — special-case that.

**Note on cost:** Each fresh shell pays one S3 call (~50ms). Subsequent calls in the same process see the exported var and skip. Acceptable.

### Change 2: `.agents/references/env-vars.md`

- Move `AWS_REGION` from "Required" table to "Optional" with default "auto-detected from `ROOT_ATHENA_S3_BUCKET`".
- Adjust walkthrough step 5 to drop the `export AWS_REGION` line and add a note: "Region is auto-detected from the bucket on first tool call — explicitly export only if you need to override (e.g. cross-region replica)."

### Change 3: `.agents/AGENTS.md`

Change the table row:

```diff
-| `AWS_REGION` | yes | Region the org's Athena lives in |
+| `AWS_REGION` | no (auto-detected) | Region the org's Athena lives in. Inferred from `ROOT_ATHENA_S3_BUCKET` via `aws s3api get-bucket-location`. Export only to override. |
```

### Change 4: `.agents/.env.example`

```diff
-export AWS_REGION="eu-west-1"
+# AWS_REGION is auto-detected from ROOT_ATHENA_S3_BUCKET on first tool call.
+# Uncomment to override (e.g. if you query via a regional replica).
+# export AWS_REGION="eu-west-1"
```

## Test

```bash
# Bare shell, no AWS_REGION set
unset AWS_REGION
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... \
       ROOT_ORG_ID=... ROOT_ATHENA_S3_BUCKET=...
bash .agents/tools/whoami.sh   # should succeed and (with ROOT_AGENTS_DEBUG=1) print:
#   [debug] auto-detected AWS_REGION=eu-west-1 from <bucket>
```

Acceptance: a session starts cleanly with only four env vars set (excluding optional `ROOT_ENV`).
