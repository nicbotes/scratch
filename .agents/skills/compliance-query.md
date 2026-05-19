---
name: compliance-query
description: Identified-record data collection for DSARs, regulator requests, retention audits, or "show me all data we hold on person/policy/claim X". Output is evidence with a manifest, not insight. Use when the question is per-subject and complete. Do NOT use for exploratory analysis, aggregates, or anything that doesn't need to be reproducible from a tamper-evident artefact.
---

# Skill: compliance-query

Compliance work is per-subject, deterministic, and exhaustive. The output is a folder under `.agents/evidence/` with CSVs and a manifest — not a number in a chat reply.

## Steps

1. **Confirm the subject identifier.** Get one unambiguous identifier from the user: `policyholder_id`, `id_number`, `email`, `policy_id`, or `claim_id`. Don't infer.
2. **Run `whoami`.** The evidence manifest must be unambiguous about which org the data came from. Confirm `ROOT_ORG_ID` matches what the requester asked about.
3. **Enumerate tables that may reference the subject.** Use `references/schema.md` and `explore-schema` if needed. Typical set: `policies`, `policyholders`, `payments`, `policy_ledger`, `policy_events`, `claims`, `notifications`, `payment_methods`.
4. **For each table, run a deterministic `SELECT *`** filtered by the subject identifier and `environment = '$ROOT_ENV'`. No `LIMIT`. Route through `export-results.sh` so each query gets a manifest:
   ```bash
   bash .agents/tools/export-results.sh dsar-<subject>-policies \
     "SELECT * FROM policies WHERE environment='production' AND policyholder_id = '<id>'"
   ```
5. **Cross-reference.** From the first-degree results, harvest secondary identifiers (`policy_id` from `policies`, `claim_id` from `claims`) and run second-degree queries (e.g. `payments WHERE policy_id IN (...)`).
6. **Bundle.** Each `.agents/evidence/<ts>-<name>/` folder is a self-contained artefact (CSV + `manifest.json` with org id, env, sql, query id, sha256, row count). Hand the user the list of folder paths.
7. **Never fan out across orgs.** Compliance is per-org-per-subject (rules.md #16). If the subject exists in multiple orgs, run the workflow separately under each `ROOT_ORG_ID` with a fresh `whoami` between them.

## Reference

PII handling:
- Never paste subject identifiers into chat replies or commit messages. The manifest captures them inside the evidence folder (gitignored).
- The evidence folder is gitignored (`.gitignore` includes `.agents/evidence/`). Do not commit.
- If the requester is a regulator, capture the regulator reference in the folder name (`dsar-<ref>-<subject>`).

→ Cross-references: `rules.md` #11 (compliance is evidence) and #16 (per-org, never fan out).
