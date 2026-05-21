---
name: pii-safe-analysis
description: Analytical work that touches PII / restricted / json_sensitive columns (tagged in references/pii-columns.json). Use when the data involves sensitive fields but the answer is a summary, aggregate, or anonymised feed. Do NOT use for purely non-sensitive aggregates (use analyst-workflow), or for row-level compliance pulls (use compliance-query).
---

# Skill: pii-safe-analysis

The right workflow when sensitive columns are unavoidable but the answer doesn't require values entering context. Operates on shape, not values — the agent never sees a name, the answer is correct anyway.

## The two-layer firewall

The PII boundary is enforced at two points by `duckdb-query.sh`, `regression-record.sh`, and `export-results.sh`:

1. **Pre-flight (regex)** — before submitting the query, the SQL text is scanned against `references/pii-columns.json` for sensitive column references and JSON-extract paths. Fast, free; catches obvious cases.
2. **Inline result-schema check (DuckDB DESCRIBE)** — before printing any rows, we ask DuckDB to plan and type the SQL via `DESCRIBE (<sql>)` and check the resulting column names against `pii-columns.json`. This catches aliased PII (`SELECT email AS x`) and computed-PII patterns the regex misses.

Both layers feed the same gate (`pii_required_or_fail` / `pii_required_or_fail_inline`). Same UX (refused → with options or proceed with override). The two-layer design means false negatives from the regex are caught by DESCRIBE, and the regex saves work on obviously-sensitive queries.

## Steps

1. **Scan the SQL first.** Don't run a sensitive query blind:
   ```bash
   bash .agents/tools/pii-scan.sh "SELECT user.email, COUNT(*) FROM raw_github_pulls ..."
   ```
   The scanner returns `pii=...`, `restricted=...`, `json_sensitive=...`, `json_paths=...`. If anything's non-empty, you're in this skill's territory. (`pii-scan.sh` runs the regex only; the DESCRIBE check happens inside the executing tool.)

2. **For JSON / STRUCT columns**, sample one row first to see the safe keys, then add the safe ones to a learned skill so subsequent queries don't trip the firewall on every access:
   ```bash
   bash .agents/tools/duckdb-query.sh \
     --pii-required --reason "discovering JSON shape for github.user struct" \
     "SELECT user FROM raw_github_pulls LIMIT 1" --to-file /tmp/probe.json
   # Inspect /tmp/probe.json. Keys like .login may be PII; .id is safe.
   bash .agents/tools/learn-skill.sh github-user-safe-keys --description "..." \
     --body "safe_keys: [user.id, user.type, user.site_admin]"
   ```

3. **Restructure for shape, not values:**
   - **Pure aggregate?** Drop the PII columns from `SELECT`, keep them only in `WHERE` if a filter needs them. `SELECT COUNT(*) FROM raw_github_pulls WHERE user.email IS NOT NULL` — the column is referenced, the value never reaches stdout. *This still trips the pre-flight* (column-touch); use `--to-file` for the file path + a second query over the file.
   - **Need per-row data but only as identifiers for joins?** Pseudonymise:
     ```bash
     bash .agents/tools/duckdb-query.sh --to-file /tmp/pii.csv \
       --pii-required --reason "cohort analysis on user identifiers" \
       "SELECT id, user.email AS email FROM raw_github_pulls WHERE merged_at IS NOT NULL"
     bash .agents/tools/pseudonymize.sh /tmp/pii.csv --columns email --output /tmp/safe.csv
     bash .agents/tools/duckdb-query.sh \
       "SELECT email_hash, COUNT(*) FROM '/tmp/safe.csv' GROUP BY email_hash ORDER BY 2 DESC"
     ```
     The agent operates on `email_hash`; the raw email is on disk, not in context.

4. **Never `SELECT *`** from a table with tagged columns. The firewall will catch it, but listing columns explicitly is the right discipline anyway — it's how you defend the SQL in a compliance review.

5. **API query parameters carry the same risk** (T5 in `references/pii-safety.md`). Don't `fetch-api.sh /search?email=jane@example.com` — that puts the email in a tool call sent to Anthropic. Use the identifier-based lookup the API provides (`/users/<id>`).

6. **Reply discipline (rule #25).** The agent's chat reply contains no values from sensitive columns. Use pseudonyms ("the user", id prefixes), counts, or `_hash` columns. If you have to talk about a specific record, name the identifier, not the person.

## When --pii-required is appropriate

The override exists for legitimate cases — don't pretend it doesn't. Reasonable reasons that pass review:
- A DSAR fulfilment ("DSAR-2026-Q2-014").
- A regulator request with a written reference.
- A specific support ticket needing a per-subject lookup ("ticket-44521").
- A one-off ad-hoc named for the operator ("nic-troubleshooting-bug-2026-05-22").

Reasons that should make you reach for a different approach instead:
- "exploring the data" → use aggregate restructuring or pseudonymisation.
- "easier this way" → not a reason; the boundary exists for the next session, not just this one.
- (empty / placeholder) → `--reason` is mandatory for a reason.

## Reference

| Pattern | Tool combination |
|---|---|
| Aggregate over PII rows | `duckdb-query.sh --to-file` + a second `duckdb-query.sh` over the file |
| Join-preserving anonymisation | `pseudonymize.sh` between pull and analysis |
| Audit per-subject access | `export-results.sh --pii-required --reason "<ref>"` |
| Verify the boundary held | `compliance-audit.sh --session <id>` |

→ Cross-references: `rules.md` #23, #24, #25; `references/pii-safety.md` (compliance-officer doc); `references/pii-columns.json` (the metadata).
