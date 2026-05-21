# Reference: environment variables

Everything the framework reads. Defaults shown in `[brackets]`. Set in `.agents/.env` and `source` once per shell.

## Required

| Var | Purpose |
|---|---|
| `API_BASE_URL` | Root URL of the API the framework targets. Examples: `https://api.github.com`, `https://<your-domain>.atlassian.net/rest/api/3`. No trailing slash. |
| `API_TOKEN` | Bearer / personal-access / API-key token. Required for most APIs; can be empty for public-only fetches. |

## PII safety

| Var | Purpose |
|---|---|
| `ROOT_AGENTS_COMPLIANCE_MODE` `[strict]` | One of `strict`, `standard`, `off`. See `references/pii-safety.md`. |

## Telemetry

| Var | Purpose |
|---|---|
| `MIXPANEL_TOKEN` | When set, the framework fires workflow events to Mixpanel (EU endpoint). Disable by leaving unset. |
| `ROOT_AGENTS_TELEMETRY` `[on]` | Set to `off` to disable telemetry even when a token is set. |

## Output caps (rule #20)

| Var | Purpose |
|---|---|
| `ROOT_AGENTS_MAX_ROWS` `[1000]` | Max rows tools print to stdout before truncating. |
| `ROOT_AGENTS_MAX_BYTES` `[200000]` | Max bytes tools print to stdout before truncating. |

## DuckDB

| Var | Purpose |
|---|---|
| `DUCKDB_PATH` `[$AGENTS_ROOT/data/db/main.duckdb]` | Override the database location. Most projects never need this; useful for parallel sessions on different snapshots. |

## Debug / session

| Var | Purpose |
|---|---|
| `ROOT_AGENTS_DEBUG` `[0]` | `1` = verbose tool output to stderr (SQL, request URLs, paging cursors, telemetry bodies). |
| `ROOT_AGENTS_SESSION_ID` `[YYYY-MM-DD]` | Namespace for session traces & feedback. Override to group multiple shells into one session. |
| `ROOT_AGENTS_NAMESPACE` | Default `<ns>` for `save-view.sh --scratch` when no flag is passed. |

## Authentication shapes the framework supports

For sources that don't fit `Authorization: Bearer $API_TOKEN`, pass per-tool flags. `fetch-api.sh`:

| Auth style | Example |
|---|---|
| Bearer (default) | `fetch-api.sh /endpoint` — sends `Authorization: Bearer $API_TOKEN`. |
| Custom header | `fetch-api.sh /endpoint --auth header --auth-header-name X-API-Key` — sends `X-API-Key: $API_TOKEN`. |
| None / public | `fetch-api.sh /endpoint --auth none` — no auth header. |

Basic auth and OAuth refresh flows are out-of-scope for v1. Document the source's quirks in `references/sources/<name>.md` and add a learned skill if the workflow becomes routine.

## First-run setup walkthrough

```bash
cp .agents/.env.example .agents/.env
# Open .agents/.env and set at minimum:
#   API_BASE_URL=https://api.github.com
#   API_TOKEN=ghp_...
source .agents/.env

bash .agents/tools/whoami.sh --endpoint /user
# Expected: API base + hash + identity line.

bash .agents/tools/framework-status.sh
# Expected: deps OK, 0 views, 0 goldens, 0 proposals.
```
