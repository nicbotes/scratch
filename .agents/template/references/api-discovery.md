# Reference: API discovery template

Pattern for documenting a new API source so subsequent fetches don't re-probe.

For each new source, create `references/sources/<name>.md` (kebab-case) using the structure below. See `references/sources/github.md` for a worked example.

## Operating-doc structure

```markdown
# Source: <Name>

One-paragraph description of what this API serves and why we care.

## Auth
Header:       Authorization: Bearer $API_TOKEN
Token type:   <PAT | API key | OAuth bearer | basic>
Scopes:       <list of scopes the framework's read flows need>
Generate at:  <URL where the user creates the token>

## Pagination
Style:        <link | cursor | offset | none>
Flag:         --paginate <link|cursor|offset>
Per-page:     <max page size>
Notes:        <e.g. "Link header with rel=next", "cursor in response body .next_cursor">

## Rate limits
Authenticated:    <N> requests / <window>
Unauthenticated:  <N> requests / <window>
Headers:          X-RateLimit-Remaining, X-RateLimit-Reset (epoch / RFC3339)
On 429:           <recovery behaviour — Retry-After header? Wait until reset?>

## Reference endpoints
| Entity | Endpoint | Notes |
|---|---|---|
| <name> | GET <path> | <quirks, filters, gotchas> |

## Worked example
```bash
bash .agents/tools/fetch-api.sh <endpoint> \
  --query "<filter>" --paginate <style> \
  --source <name> --entity <entity>
bash .agents/tools/land-to-duckdb.sh <entity> --source <name>
bash .agents/tools/profile-table.sh raw_<name>_<entity>
```

## Known PII columns
See `references/pii-columns.json`. Default tags this source's responses commonly include:
- `<col>` — `pii` | `restricted` | `json_sensitive`
- ...
```

## Discovery checklist

Use `skills/discover-api.md` for the active workflow. The findings go in the operating doc above. Probe in this order:

1. **Auth shape.** Hit the simplest authenticated endpoint (`/user`, `/me`, `/whoami`). Confirm header name + token shape. Use `bash .agents/tools/whoami.sh --endpoint /user` as the first call.

2. **Pagination style.** Pull one page of a list endpoint. Inspect headers and body:
   - Link header with `rel="next"` → `--paginate link`
   - Cursor in body (`.next_cursor`, `.cursors.after`, `.response_metadata.next_cursor`) → `--paginate cursor --cursor-key <key>`
   - Offset/page in query params → `--paginate offset`

3. **Rate limits.** Read the relevant headers. Find:
   - Remaining-requests header name
   - Reset header name (epoch seconds vs RFC3339 vs `Retry-After` seconds)
   - The window (per minute / per hour / per day / per token)

4. **Core endpoints.** List the 3–5 endpoints relevant to the analyses you'll run. For each:
   - Method (GET / POST)
   - Required query params
   - Response shape (top-level array vs `.items` vs `.results`)

5. **Sensitive fields.** Pull one record. Note which fields are PII (user names, emails, free-text bodies). Add them to `references/pii-columns.json` keyed on the table `raw_<source>_<entity>`.

## Output of this skill

Two files:
- `references/api-discovery.md` — probe log entries (one append per probe).
- `references/sources/<name>.md` — the operating doc the next session reads instead of re-probing.

If the API has a recurring quirk worth surfacing (e.g. GitHub's GraphQL preview headers, Jira's `expand=` parameter set, Stripe's idempotency keys), capture it as a learned skill via `learn-skill.sh`.

## Probe log

(Append one section per probe. Newer entries at the top.)
