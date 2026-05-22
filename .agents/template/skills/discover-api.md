---
name: discover-api
description: Probe a new HTTP API to map its auth, pagination, rate limits, and core endpoints, then document them in references/sources/<name>.md. Use the first time the framework points at a new API source, or when an endpoint behaves differently from documentation. Do NOT use for a routine fetch against an API already documented (use land-data).
---

# Skill: discover-api

The reconnaissance step. Pay this cost once; every later fetch reads the source doc instead of re-probing.

## Steps

1. **Confirm credentials work.** `bash .agents/tools/whoami.sh --endpoint /user` (or the simplest authenticated endpoint your API exposes). 200 = proceed; 401/403 = fix the token first.

2. **Establish auth shape.** Most APIs accept `Authorization: Bearer $API_TOKEN`. Some need a custom header (`X-API-Key`, `PRIVATE-TOKEN`, etc.). Test the simplest case:
   ```bash
   # Default (bearer):
   bash .agents/tools/fetch-api.sh /user --max-pages 1 --out /tmp/probe.jsonl --dry-run
   # Custom header:
   bash .agents/tools/fetch-api.sh /v1/me --auth header --auth-header-name X-API-Key --max-pages 1 --out /tmp/probe.jsonl --dry-run
   ```

3. **Pagination.** Pull one page of a list endpoint with `--paginate none --max-pages 1`. Inspect the response:
   - **Link header** with `rel="next"` (GitHub, GitLab, some Stripe) → `--paginate link`.
   - **Cursor in body** (`.next_cursor`, `.cursors.after`, `.response_metadata.next_cursor`) → `--paginate cursor --cursor-key <key>`.
   - **Page / offset in query** (Jira, older REST) → `--paginate offset`.
   - **No pagination** (single-record endpoint) → `--paginate none`.

4. **Rate limits.** Read the response headers. Find:
   - Remaining-requests header (`X-RateLimit-Remaining`, `X-Rate-Limit-Remaining`).
   - Reset header (`X-RateLimit-Reset` as epoch seconds, RFC3339, or `Retry-After` seconds).
   - The window (per minute / hour / day / token).

5. **Core endpoints.** List the 3–5 endpoints relevant to the analyses you'll run. For each:
   - Method (GET / POST).
   - Required query params.
   - Response shape (top-level array vs `.items` vs `.results` — passed via `fetch-api.sh --jq-extract '.items[]'`).

6. **Sensitive fields.** Pull one record. Note which fields are PII (user names, emails, free-text bodies). Add them to `references/pii-columns.json` keyed on the table `raw_<source>_<entity>` (which `land-to-duckdb.sh` will create on the next pull).

7. **Write it down.**
   - **`references/api-discovery.md`** — append a probe log entry with date, findings, surprises.
   - **`references/sources/<name>.md`** — write or update the operating doc per the template in `references/api-discovery.md`. This is the doc the next session reads.

8. **Capture as a learned skill** if the API has a recurring quirk worth surfacing (GitHub's GraphQL preview headers, Jira's `expand=` parameter set, Stripe's idempotency keys, etc.).

→ Next: `land-data` to pull the first slice.
