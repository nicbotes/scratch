# Reference: PII safety boundary

For customer compliance officers and security reviewers. This page describes what the framework guarantees about PII handling, what you must configure, and how to audit it.

## What the framework guarantees

The framework treats five distinct PII-leakage surfaces and gates each one explicitly. Threat IDs use the convention from the framework's design notes.

### T1 — PII row values reaching LLM (Claude) inference

**Solved by default.** When the agent runs a SQL query, the firewall enforces sensitivity at **two layers**:

1. **Pre-flight regex scan.** Before submission to Athena, the SQL text is scanned against `references/pii-columns.json`. Fast, free; catches obvious cases without paying for the query. Conservative — false positives over false negatives.
2. **Inline result-schema check (authoritative).** After Athena executes the query but before we fetch the CSV, we read the actual `ResultSetMetadata.ColumnInfo` Athena reports and check each result column name against `pii-columns.json`. Both Athena's catalog `Name` and the SQL `Label` (alias) are checked. This catches aliased PII (`SELECT first_name AS x`) and computed PII the regex couldn't detect.

When either layer flags sensitivity, the firewall refuses to print results to stdout. The agent is forced to one of:

- Route to a file (`--to-file <path>`) and operate on the file with `duckdb-query.sh` (rule #24, pre-aggregate locally).
- Pseudonymise sensitive columns first with `pseudonymize.sh` (deterministic per-org hashing — joins preserved, values opaque).
- Restructure the SQL to be aggregate-shaped — touch the column in `WHERE` for filtering, drop it from `SELECT`.
- Override explicitly with `--pii-required --reason "<text>"`. The reason is mandatory and logged.

JSON columns (`policies.module`, `applications.app_data`, `policies.beneficiaries`, `policies.covered_people`, etc.) are treated as PII-unknown by default — `JSON_EXTRACT` against them requires either a path that's been tagged as `safe` by `derive-jsonb-schema`, or an explicit override. (JSON paths can't be detected from the result schema alone, so the regex pre-flight is the only check that catches them.)

### T2 — Anthropic transcripts retaining the data

**Out of framework scope.** Even with T1 controls, any data that does enter the agent's context is sent in the API request body to Anthropic. By default Anthropic may retain prompts and responses for up to 30 days for trust and safety review.

If retention is unacceptable for your compliance regime, three resolutions, all *outside* the framework:

| Option | What it gives you |
|---|---|
| Anthropic **Zero Data Retention** agreement | Anthropic processes the request but doesn't store the body. Case-by-case, sales-driven. |
| **AWS Bedrock** with Anthropic models | Inference happens inside your AWS account / region / VPC. No Anthropic-side retention by default. |
| Self-hosted open-weight model | Framework is endpoint-agnostic; point Claude Code (or your agent runner) at a local model. |

The framework's tools and skills are agnostic to which model serves inference. The conventions hold across all three.

### T3 — Sensitive values appearing in the agent's chat reply

**Solved by rule #28 + posture block.** The agent is instructed at session start (via the posture block in `AGENTS.md`, which renders based on `ROOT_AGENTS_COMPLIANCE_MODE`) to never echo values from PII or restricted columns in its reply. Pseudonyms (`policy #1234`, "the policyholder", `_hash` columns) replace raw values.

This is a *prompted* constraint, not a runtime block — the agent could in principle violate it. The compliance audit catches violations after the fact; the agent's training and the explicit instruction make compliance the strongly-preferred behaviour.

### T4 — PII committed to git

**Solved structurally.**

- `regression-record.sh` **refuses** any SQL touching PII, restricted, or unresolved JSON-sensitive columns. Goldens must be aggregate-shaped (rule #15).
- Sensitive exports from `export-results.sh` land under `.agents/sensitive/` (gitignored), not `.agents/evidence/`. Both prefixes are gitignored; the split is for tighter S3 / disk-policy scoping downstream.
- `pii-lookup.sh` writes to `.agents/sensitive/` only — never anywhere that could end up in git.
- The session log (`.agents/sessions/*.jsonl`, gitignored) records metadata + reasons, never values.

### T5 — PII literals in SQL tool-call parameters

**Mitigated via pseudonymisation + indirection.** When the agent needs to query "the policy belonging to Jane Smith", the safer pattern is:

1. The user (or upstream system) supplies the *identifier* (`policyholder_id=abc-123`), not the value.
2. The agent's SQL contains the identifier, which is a UUID — not PII.
3. If the agent needs the values for the *result*, route to a file via `pii-lookup.sh`.

The pattern to avoid is `WHERE email = 'jane@example.com'` — that puts the email in the SQL string, which is sent to Anthropic as a tool call. The framework's skills steer the agent away from this; the firewall doesn't catch it directly (the literal isn't a column reference) but `compliance-audit.sh` surfaces queries containing email-shaped literals on demand.

## What you must configure

### `ROOT_AGENTS_COMPLIANCE_MODE`

Sets the strictness of the firewall.

| Mode | When to use | Behaviour |
|---|---|---|
| `strict` (default) | Distribution to customers; clients under PII regulation; any unclear case | `--pii-required --reason` required for sensitive output even when writing to a file. Goldens refused outright. Posture block at full strength. |
| `standard` | Trusted internal dev who needs ergonomic per-file access | `--to-file` alone is enough for sensitive output without `--pii-required`. Reply discipline still applies. |
| `off` | Local dev only, against sandbox data | No gating. Every tool invocation emits a `[PII SAFETY OFF — DEV MODE]` stderr warning. |

Set in `.env`:
```bash
export ROOT_AGENTS_COMPLIANCE_MODE=strict
```

`.env.example` ships with strict. The in-house team explicitly opts down.

### Anthropic ZDR / Bedrock / self-host (for T2)

Configured outside the framework. If you're using the Anthropic API directly with default retention, the framework can't fix that — but it documents the options. The framework runs identically against any of the three.

### Network egress (optional, defence in depth)

For the strictest compliance regimes, restrict the AWS / Anthropic API endpoints the framework reaches. The bash tools call `aws athena`, `aws s3`, and (for `root-api.sh`) `https://api.rootplatform.com`. The Claude Code or agent runner makes outbound calls to Anthropic / Bedrock per your model choice. Egress controls on the host machine cover both surfaces.

## Audit trail

### Per-session inspection

```bash
bash .agents/tools/compliance-audit.sh --session <session-id>
```

Produces a markdown table of every sensitive-touching tool invocation:
- Timestamp (UTC).
- Tool (which `.agents/tools/*.sh` was called).
- Override (none / `--to-file` / `--pii-required`).
- Reason text (mandatory for `--pii-required`).
- Table + identifier column + row count (for `pii-lookup`).

No values. The report can be safely shared with a compliance officer.

### Date-ranged audit

```bash
bash .agents/tools/compliance-audit.sh --since 2026-05-01 --output ./audit-2026-05.md
```

Sweeps every session log from the given date forward. Suitable for monthly / quarterly reviews.

### What the audit cannot tell you

- Whether the agent's chat replies leaked values (T3 violations). The framework doesn't log chat replies. Auditing this requires the host (Claude Code, your agent runner) to log the conversation — typically already the case.
- Whether the user manually opened a sensitive file written by `--to-file` / `pii-lookup`. By design — once the file is on disk, it's the operator's responsibility.

## Posture and trade-offs

The framework prioritises **safe-by-default** over **frictionless**. In strict mode, every sensitive operation is a deliberate decision logged with a reason. The friction is the feature: it ensures every PII-touching workflow has an audit-trail-of-one explaining why. The cost is the operator must stop, articulate, and override — that's the boundary working.

If a team finds itself overriding constantly with thin reasons, that's the signal to restructure the workflow (pseudonymise → aggregate locally → context-safe summary), not to weaken the rules. The framework's `observe` + `retro` loop surfaces this pattern naturally.

## Cross-references

| Resource | Purpose |
|---|---|
| `rules.md` #26, #27, #28 | The codified rules. Read these in addition to this doc. |
| `skills/pii-safe-analysis.md` | The workflow for sensitive analytical work. |
| `references/pii-columns.json` | Machine-readable metadata the firewall reads. |
| `tools/pii-scan.sh` | Inspect a SQL statement before running it. |
| `tools/pseudonymize.sh` | Deterministic per-org column hashing. |
| `tools/pii-lookup.sh` | Logged single-record fetch to disk. |
| `tools/compliance-audit.sh` | After-the-fact session audit. |
