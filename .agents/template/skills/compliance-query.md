---
name: compliance-query
description: Identified-record data collection for DSARs, regulator requests, retention audits, or "show me all data we hold on subject X". Output is evidence with a manifest, not insight. Use when the question is per-subject and complete. Do NOT use for exploratory analysis, aggregates, or anything that doesn't need to be reproducible from a tamper-evident artefact.
---

# Skill: compliance-query

Compliance work is per-subject, deterministic, and exhaustive. The output is a folder under `.agents/sensitive/` (sensitive evidence is gitignored, separate prefix from `.agents/evidence/` for tighter scoping). The manifest captures the SQL, sha256 of the CSV, and the api_base_hash.

## Steps

1. **Confirm the subject identifier.** Get one unambiguous identifier from the user: a numeric/UUID id, an email, a username. Don't infer.
2. **Run `whoami`.** The evidence manifest must be unambiguous about which API the data came from.
3. **Enumerate tables that may reference the subject.** Use `explore-schema` if needed. For GitHub, typical: `raw_github_pulls`, `raw_github_issues`, `raw_github_events` (the framework can land more entities as needed).
4. **For each table, run a deterministic query** filtered by the subject identifier. No `LIMIT`. Route through `export-results.sh` so each query gets a manifest:
   ```bash
   bash .agents/tools/export-results.sh dsar-<subject>-pulls \
     --pii-required --reason "DSAR-2026-Q2-014" \
     "SELECT * FROM raw_github_pulls WHERE user.id = <subject_id>"
   ```
5. **Cross-reference.** From the first-degree results, harvest secondary identifiers (PR numbers, issue ids, comment ids) and run second-degree queries (e.g. `raw_github_issues WHERE number IN (...)`).
6. **Bundle.** Each `.agents/sensitive/<ts>-<name>/` folder is a self-contained artefact (CSV + `manifest.json` with sql, sha256, row count, api_base_hash). Hand the user the list of folder paths.

## Reference

PII handling:
- Never paste subject identifiers into chat replies or commit messages. The manifest captures them inside the sensitive folder (gitignored).
- `.agents/sensitive/` is gitignored. Do not commit.
- If the requester is a regulator, capture the regulator reference in the folder name (`dsar-<ref>-<subject>-<entity>`).

→ Cross-references: `rules.md` #9 (named-consumer output is evidence), #23 (PII never reaches stdout); `references/pii-safety.md` for the full compliance posture.
