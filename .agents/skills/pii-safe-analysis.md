---
name: pii-safe-analysis
description: Analytical work that touches PII tables (policyholders, members, leads, payment_methods, calls) or json_sensitive columns (policies.module, applications.app_data, policies.beneficiaries, etc.). Use when the data involves sensitive fields but the answer is a summary, aggregate, or anonymised feed. Do NOT use for purely non-sensitive aggregates (use analyst-workflow), for row-level compliance pulls (use compliance-query), or for "look up this one person" requests (use pii-lookup directly).
---

# Skill: pii-safe-analysis

The right workflow when sensitive columns are unavoidable but the answer doesn't require values entering context. Operates on shape, not values — Claude never sees a name, the answer is correct anyway.

## The two-layer firewall

The PII boundary is enforced at two points by `athena-query.sh`, `regression-record.sh`, and `export-results.sh`:

1. **Pre-flight (regex)** — before submitting the query to Athena, the SQL text is scanned against `references/pii-columns.json` for sensitive column references and JSON-extract paths. Fast, free, catches the obvious cases without paying for the query.
2. **Inline result-schema check** — after Athena executes the query (but before we fetch the result CSV), we call `aws athena get-query-results --max-results 1` to read the `ResultSetMetadata.ColumnInfo` — Athena's authoritative list of what columns the result actually contains. Each name is checked against `pii-columns.json`. This catches aliased PII columns (`SELECT first_name AS x ...` — Athena reports both `Name=first_name` and `Label=x`, both are checked) and computed-PII patterns the regex misses.

Both layers feed the same gate (`pii_required_or_fail` / `pii_required_or_fail_inline`). Same UX (refused → with options or proceed with override). The two-layer design means false negatives from the regex are caught by the inline check, and the regex saves cost on obviously-sensitive queries by refusing before execution.

## Steps

1. **Scan the SQL first.** Don't run a sensitive query blind:
   ```bash
   bash .agents/tools/pii-scan.sh "SELECT first_name, COUNT(*) FROM policyholders ..."
   ```
   The scanner returns `pii=...`, `restricted=...`, `json_sensitive=...`, `json_paths=...`. If anything's non-empty, you're in this skill's territory. (Note: `pii-scan.sh` runs the regex only — the inline result-schema check happens at execution time inside `athena-query.sh`.)

2. **For JSON columns**, run `derive-jsonb-schema` if you haven't this session. The firewall refuses `JSON_EXTRACT` against `module` / `app_data` / `beneficiaries` / etc. unless the path is in the learned skill's `safe_keys:` list. Tagging the keys (`pii` / `restricted` / `safe`) once unlocks all future safe-key queries.

3. **Restructure for shape, not values:**
   - **Pure aggregate?** Drop the PII columns from `SELECT`, keep them only in `WHERE` if a filter needs them. `SELECT COUNT(*) FROM policyholders WHERE date_of_birth >= '...'` — the column is referenced, the value never reaches stdout. *This still trips the firewall* (rule #26 is column-touch, not column-value); use `--to-file` for the file path + `duckdb-query.sh` over it.
   - **Need per-row data but only as identifiers for joins?** Pseudonymise:
     ```bash
     bash .agents/tools/athena-query.sh --to-file /tmp/pii.csv \
       --pii-required --reason "demographic adoption analysis" \
       "SELECT policyholder_id, email, date_of_birth FROM policyholders WHERE ..."
     bash .agents/tools/pseudonymize.sh /tmp/pii.csv --columns email,date_of_birth --output /tmp/safe.csv
     bash .agents/tools/duckdb-query.sh "SELECT email_hash, COUNT(*) FROM '/tmp/safe.csv' GROUP BY email_hash"
     ```
     The agent operates on `email_hash`; the raw email is on disk, not in context.

4. **Never `SELECT *`** from a PII table. The firewall will catch it, but listing columns explicitly is the right discipline anyway — it's how you defend the SQL in a compliance review.

5. **Row-level rare cases** — use `pii-lookup.sh` with `--reason`:
   ```bash
   bash .agents/tools/pii-lookup.sh policyholders policyholder_id=abc-123 \
     --columns first_name,email \
     --reason "drafting customer outreach for renewal campaign"
   ```
   Returns a file path only. The agent treats it as a path, not as data, unless the user explicitly asks for a value.

6. **Reply discipline (rule #28).** The agent's chat reply contains no values from sensitive columns. Use pseudonyms (`policy #1234`, "the policyholder"), counts, or `_hash` columns. If you have to talk about a specific record, name the identifier, not the person.

## When --pii-required is appropriate

The override exists for legitimate cases — don't pretend it doesn't. Reasonable reasons that pass review:
- A DSAR fulfilment ("DSAR-2026-Q2-014").
- A regulator request with a written reference ("FSCA-info-req-19").
- A specific support ticket needing a per-subject lookup ("ZD-ticket-44521").
- A one-off ad-hoc named for the operator ("nic-troubleshooting-payment-failure-2026-05-22").

Reasons that should make you reach for a different approach instead:
- "exploring the data" → use aggregate restructuring or pseudonymisation.
- "easier this way" → not a reason; the boundary exists for the next session, not just this one.
- (empty / placeholder) → `--reason` is mandatory for a reason.

## Reference

| Pattern | Tool combination |
|---|---|
| Aggregate over PII rows | `athena-query.sh --to-file` + `duckdb-query.sh` |
| Join-preserving anonymisation | `pseudonymize.sh` between the pull and the analysis |
| One legitimate per-subject lookup | `pii-lookup.sh --reason "<ref>"` |
| Many DSAR exports | `compliance-query` skill → `export-results.sh` |
| Verify the boundary held | `compliance-audit.sh --session <id>` |

→ Cross-references: `rules.md` #26, #27, #28; `references/pii-safety.md` (customer-facing policy); `references/pii-columns.json` (the metadata); `derive-jsonb-schema` (JSON column gateway).
