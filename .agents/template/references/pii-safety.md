# Reference: PII safety boundary

For compliance officers and security reviewers. Describes what the framework guarantees about PII handling, what you must configure, and how to audit it.

## What the framework guarantees

The framework treats five distinct PII-leakage surfaces and gates each one explicitly.

### T1 — PII row values reaching LLM (Claude) inference

**Solved by default.** When the agent runs a SQL query, the firewall enforces sensitivity at **two layers**:

1. **Pre-flight regex scan.** Before submission to DuckDB, the SQL text is scanned against `references/pii-columns.json`. Fast, free; catches obvious cases. Conservative — false positives over false negatives.
2. **Inline result-schema check (authoritative).** Before printing results to stdout, we ask DuckDB to plan and type the SQL via `DESCRIBE (<sql>)` and check the resulting column names against `pii-columns.json`. This catches aliased PII (`SELECT email AS x`) and computed PII the regex pre-flight could not detect.

When either layer flags sensitivity, the firewall refuses to print results to stdout. The agent is forced to one of:

- Route to a file (`--to-file <path>`) and operate on the file with another `duckdb-query.sh` call.
- Pseudonymise sensitive columns first with `pseudonymize.sh` (deterministic per-API hashing — joins preserved, values opaque).
- Restructure the SQL to be aggregate-shaped — touch the column in `WHERE` for filtering, drop it from `SELECT`.
- Override explicitly with `--pii-required --reason "<text>"`. The reason is mandatory and logged.

JSON / STRUCT columns flagged `json_sensitive` in `pii-columns.json` are PII-unknown by default — `json_extract_string(col, '$.path')` and DuckDB dot-notation (`col.path`) both trigger the firewall. JSON paths can only be detected from the SQL text (not from the result schema), so the regex pre-flight is the only check that catches them. The path is allowed when listed in a `safe_keys:` block of a learned skill, or with an explicit override.

### T2 — Anthropic transcripts retaining the data

**Out of framework scope.** Even with T1 controls, any data that does enter the agent's context is sent in the API request body to Anthropic. By default Anthropic may retain prompts and responses for up to 30 days for trust and safety review.

If retention is unacceptable for your compliance regime, three resolutions, all *outside* the framework:

| Option | What it gives you |
|---|---|
| Anthropic **Zero Data Retention** agreement | Anthropic processes the request but doesn't store the body. Case-by-case, sales-driven. |
| **AWS Bedrock** with Anthropic models | Inference happens inside your AWS account / region / VPC. No Anthropic-side retention by default. |
| Self-hosted open-weight model | Framework is endpoint-agnostic; point your agent runner at a local model. |

The framework's tools and skills are agnostic to which model serves inference. The conventions hold across all three.

### T3 — Sensitive values appearing in the agent's chat reply

**Solved by rule #25 + posture block.** The agent is instructed at session start (via the posture block in `AGENTS.md`, which renders based on `ROOT_AGENTS_COMPLIANCE_MODE`) to never echo values from PII or restricted columns in its reply. Pseudonyms (`policy #1234`, "the policyholder", `_hash` columns) replace raw values.

This is a *prompted* constraint, not a runtime block — the agent could in principle violate it. The compliance audit catches violations after the fact; the agent's training and the explicit instruction make compliance the strongly-preferred behaviour.

### T4 — PII committed to git

**Solved structurally.**

- `regression-record.sh` **refuses** any SQL touching PII, restricted, or unresolved JSON-sensitive columns. Goldens must be aggregate-shaped (rule #13).
- Sensitive exports from `export-results.sh` land under `.agents/sensitive/` (gitignored), not `.agents/evidence/`. Both prefixes are gitignored; the split is for tighter disk / policy scoping downstream.
- The session log (`.agents/sessions/*.jsonl`, gitignored) records metadata + reasons, never values.

### T5 — PII literals in tool-call parameters (SQL **and** API URLs)

**Mitigated via indirection.** Two surfaces matter at API+DuckDB scale:

1. **SQL parameters.** When the agent needs to query "the policy belonging to Jane Smith", the safer pattern is:
   1. The user (or upstream system) supplies the *identifier* (`policyholder_id=abc-123`), not the value.
   2. The agent's SQL contains the identifier (a UUID), not PII.
   3. If the result needs to contain the values, route to a file via `export-results.sh --pii-required`.

   The anti-pattern: `WHERE email = 'jane@example.com'` puts the email in the SQL string, which is sent to Anthropic as a tool call.

2. **`fetch-api.sh` query strings.** `fetch-api.sh /search?email=jane@example.com` puts the same PII in the tool call. The firewall can't enforce this at runtime for arbitrary URLs — the indirection is on the agent, not the tool. `pii-safe-analysis` surfaces the pattern: prefer ID-based lookups, never email/phone/name literals in the URL.

## What you must configure

### `ROOT_AGENTS_COMPLIANCE_MODE`

Sets the strictness of the firewall.

| Mode | When to use | Behaviour |
|---|---|---|
| `strict` (default) | Distribution to customers; clients under PII regulation; any unclear case | `--pii-required --reason` required for sensitive output even when writing to a file. Goldens refused outright. Posture block at full strength. |
| `standard` | Trusted internal dev who needs ergonomic per-file access | `--to-file` alone is enough for sensitive output without `--pii-required`. Reply discipline still applies. |
| `off` | Local dev only, against test data | No gating. Every tool invocation emits a `[PII SAFETY OFF — DEV MODE]` stderr warning. |

Set in `.env`:
```bash
export ROOT_AGENTS_COMPLIANCE_MODE=strict
```

`.env.example` ships with strict. Adopters explicitly opt down.

### `references/pii-columns.json`

**The metadata file the firewall reads.** Ships as a generic sample (`example_users`, `example_events`, `example_payments`) — replace these with your data source's real tables and columns before any query touches sensitive data. Until you do, the firewall only fires on the example tables (which don't exist), so PII passes through ungated.

Sensitivity values:
- `pii` — directly identifies a person (names, emails, IDs, phone, address, DOB).
- `restricted` — sensitive non-identifying (account numbers, medical, behavioural, financial).
- `json_sensitive` — JSON-bearing column whose contents may contain PII. Requires safe-key discovery before bulk extraction.

### Anthropic ZDR / Bedrock / self-host (for T2)

Configured outside the framework.

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
- Touched columns (no values).

The report can be safely shared with a compliance officer.

### Date-ranged audit

```bash
bash .agents/tools/compliance-audit.sh --since 2026-05-01 --output ./audit-2026-05.md
```

Sweeps every session log from the given date forward.

### What the audit cannot tell you

- Whether the agent's chat replies leaked values (T3 violations). The framework doesn't log chat replies. Auditing this requires the host (Claude Code, your agent runner) to log the conversation.
- Whether the user manually opened a sensitive file written by `--to-file`. By design — once the file is on disk, it's the operator's responsibility.

## Posture and trade-offs

The framework prioritises **safe-by-default** over **frictionless**. In strict mode, every sensitive operation is a deliberate decision logged with a reason. The friction is the feature: it ensures every PII-touching workflow has an audit-trail-of-one explaining why. The cost is the operator must stop, articulate, and override — that's the boundary working.

If a team finds itself overriding constantly with thin reasons, that's the signal to restructure the workflow (pseudonymise → aggregate locally → context-safe summary), not to weaken the rules. The `observe` + `retro` loop surfaces this pattern naturally.

## Cross-references

| Resource | Purpose |
|---|---|
| `rules.md` #23, #24, #25 | Codified rules. |
| `skills/pii-safe-analysis.md` | Workflow for sensitive analytical work. |
| `references/pii-columns.json` | Machine-readable metadata the firewall reads. |
| `tools/pii-scan.sh` | Inspect a SQL statement before running it. |
| `tools/pseudonymize.sh` | Deterministic per-API column hashing. |
| `tools/compliance-audit.sh` | After-the-fact session audit. |
