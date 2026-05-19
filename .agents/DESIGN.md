# Design History — `.agents/` framework for the Root Data Adapter

> **For new developers:** this file is the design trail. Each phase records the friction or signal that drove the work, the alternatives considered, the choice taken, the files touched, and how to verify the change end-to-end. Read it like an archaeological record — Phase 1 is the foundation, then walk forward through how the framework evolved as real usage signal came in.
>
> **For the live system, start at [`AGENTS.md`](./AGENTS.md).** This file is *why*; AGENTS.md is *what's there now*.

## Phases at a glance

| Phase | Theme | What landed |
|---|---|---|
| 1 | Foundation | Entry point, rules, 11 tools, 13 skills, 5 references, gating skills (`premortem`, `profile-data`), feedback loop (`observe` / `retro`), regression testing |
| 2 | Iteration on real signal | `organizations` table fix; JSONB schema derivation + learned skills (`skills/learned/`); framework-evolution decision matrix + `feature-adoption` worked example |
| 3 | Output formats and delivery | Consumer→format→delivery matrix; `--format csv/json/jsonl/tsv` on `athena-query.sh`; new `athena-unload.sh` for typed Parquet via Athena `UNLOAD`; deferred Excel / PDF / SFTP / HTTP push to `FUTURE.md` |
| 4 | Token safety | Rule #23 + cap enforcement: row caps on `athena-query.sh`, byte caps on `root-api.sh`, diff caps on `regression-check.sh`. Escape valves: `--to-file`, `--head`, `--no-row-cap` |
| 5 | Context is for interpretation, not iteration | Rule #24 + `pre-aggregate` skill + new `duckdb-query.sh` for local SQL on CSV / Parquet / S3. Pull once, slice many — pay Athena once, iterate locally for free |
| 6 | Hashed identifiers in committed goldens | Resolves the redaction friction surfaced in `FUTURE.md` §2 with a SHA-256 truncated hash of `org_id`. Per-org subfolder; goldens become re-committable; raw IDs never reach git |

## How decisions were made

Each phase begins with **Context** explaining the friction or signal that drove the work. The framework's own conventions govern what gets built next:

- **`observe` notes** record in-session friction the moment it happens.
- **`retro`** clusters those notes into proposed edits under `proposals/` — never edits live files (rules.md #13).
- **`FUTURE.md`** is a menu of unbuilt ideas. Items wait there until real signal pulls them off — never burned through top-to-bottom.

The pattern across all six phases is the same: real usage produced a signal → the signal landed in `FUTURE.md` or an `observe` note → a later session pulled it off the menu when the case was clear. Phase 6 is a textbook example: the prior team noticed `regressions/` was leaking `org_id` into git, gitignored the folder as a stopgap, added the redaction concern to `FUTURE.md` §2, and the next session built the SHA-based fix.

## How to read this file alongside the code

| Reading | Pair with |
|---|---|
| Phase **Context** | The corresponding skill / tool description for the lived shape |
| Phase **Design decisions** | `rules.md` for the codified version of the rationale |
| Phase **Files** | The actual diff in git history for that phase's commit(s) |
| Phase **Verification** | The bash invocations work end-to-end against a live Athena workgroup |

---

# Phase 1 — Foundation

## Context

The existing `/dev-data-adapter` skill (`/home/user/scratch/.claude/commands/dev-data-adapter.md`) documents the Root Data Adapter for **BI tools** connecting over JDBC/ODBC. There is no agentic entry point — no way for an agent (or a developer dropping into the repo) to actually run a query from a terminal, identify which org's data they are looking at, profile a table before reasoning about it, or fan out across multiple orgs.

This plan creates a self-contained framework under `.agents/` that turns the data adapter into an "operating system" usable by an agent. Constraints:

- **No MCP.** Pure env vars + AWS CLI + Root API.
- Each org's Athena workgroup, schema/database, and S3 results prefix are all the **same `org.id` string**; the bucket name itself is separate.
- A single set of AWS credentials may have access to one org or many. Active org is selected via `ROOT_ORG_ID`; multi-org work is done by looping in shell scripts.
- `whoami` resolves the current org by querying the `organizations` table for `name` where `organization_id = $ROOT_ORG_ID`.
- **Skills are first-class:** each has YAML frontmatter (`name`, `description`) with explicit *when-to-use* and *when-not-to-use* clauses so the agent routes correctly without re-reading the body.

The skills cover the full analyst loop the user called out: **premortem → profile → analyse → compliance/BI output**.

## Directory layout

```
.agents/
├── AGENTS.md                  # Entry point — persona, env vars, skill index
├── rules.md                   # Hard rules (env filter, cents, daily snapshots, safety)
├── tools/                     # Executable bash wrappers around `aws athena` / `aws s3`
│   ├── _lib.sh                # Shared: env validation, workgroup/db/output derivation, polling
│   ├── athena-query.sh        # Run SQL, poll, fetch results as CSV/table
│   ├── athena-describe.sh     # SHOW TABLES / DESCRIBE <table>
│   ├── whoami.sh              # Resolve current org name from organizations table
│   ├── list-orgs.sh           # List all orgs the current creds can see
│   ├── profile-table.sh       # Row counts, null rates, freshness, distinct counts
│   ├── export-results.sh      # Save a query's CSV + manifest to .agents/evidence/<ts>/
│   ├── save-view.sh           # CREATE OR REPLACE VIEW <name>_view AS …
│   ├── regression-record.sh   # Snapshot a query's result as a golden under .agents/regressions/
│   ├── regression-check.sh    # Re-run a golden's query and assert the result matches
│   └── feedback-note.sh       # Append a structured note to .agents/feedback/<date>.jsonl
├── skills/                    # Frontmatter-tagged workflow skills
│   ├── whoami.md
│   ├── run-query.md
│   ├── explore-schema.md
│   ├── premortem.md
│   ├── profile-data.md
│   ├── analyst-workflow.md
│   ├── compliance-query.md
│   ├── bi-view.md             # Dimensional model (Kimball: fact_/dim_ star schema)
│   ├── ops-dataset.md         # Action-oriented denormalised cache (ops_*_view)
│   ├── multi-org-query.md
│   ├── regression-test.md     # Record / check deterministic goldens against fixed history
│   ├── observe.md             # In-session: capture a friction point as a feedback note
│   └── retro.md               # End-of-session: turn feedback into proposed edits
├── references/
│   ├── env-vars.md            # Required env vars + where to get the values
│   ├── schema.md              # Athena table catalog (incl. `organizations`)
│   ├── athena-sql.md          # Presto/Trino gotchas: JSON, dates, cents
│   ├── examples.md            # Common query recipes
│   └── feedback-schema.md     # Shape of a feedback note + categories
├── sessions/                  # (gitignored) tool traces: one JSONL per session/day
├── feedback/                  # (gitignored) agent-emitted notes: JSONL per session/day
├── proposals/                 # Human-reviewable patches written by /retro
└── regressions/               # Versioned deterministic goldens (committed)
```

## Env-var contract (single source of truth, documented in `.agents/references/env-vars.md`)

| Var | Purpose | Example |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Standard AWS auth | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | Standard AWS auth | `...` |
| `AWS_REGION` | Region the org's Athena lives in | `eu-west-1` |
| `ROOT_ORG_ID` | Active org. Used as workgroup name, Athena database, and S3 output prefix | `8f3c...` |
| `ROOT_ATHENA_S3_BUCKET` | Bucket where Athena results land. Output location = `s3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/` | `root-athena-prod-results` |
| `ROOT_ENV` | `production` or `sandbox` for the WHERE filter. Default `production` | `production` |
| `ROOT_ORG_IDS` *(optional)* | Comma-separated list for multi-org fan-out | `8f3c...,a921...` |
| `ROOT_AGENTS_DEBUG` *(optional)* | `1` enables verbose tool output (full `aws` command, scanned bytes, query id to stderr) and session tracing | `1` |
| `ROOT_AGENTS_SESSION_ID` *(optional)* | Namespaces session traces and feedback under `.agents/sessions/<id>/` | `2026-05-18-acme-dsar` |

All values are obtained once from Root Dashboard → Data Management → Data Adapter → Generate Access Key.

## Tool design

### `.agents/tools/_lib.sh`
Sourced by every tool. Provides:
- `require_env` — fail fast with a clear message if `AWS_REGION` / `ROOT_ORG_ID` / `ROOT_ATHENA_S3_BUCKET` / AWS creds are missing.
- `output_location` → echoes `s3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/`.
- `run_athena <sql>` — `aws athena start-query-execution` with `--work-group $ROOT_ORG_ID`, `--query-execution-context Database=$ROOT_ORG_ID`, `--result-configuration OutputLocation=$(output_location)`. Polls `get-query-execution` with backoff until `SUCCEEDED` / `FAILED` / `CANCELLED`. Echoes the QueryExecutionId, plus `DataScannedInBytes` and `EngineExecutionTimeInMillis` (so premortems get a real cost signal).
- `fetch_results <qid>` — `aws athena get-query-results`; for >1k rows, `aws s3 cp` the CSV instead.

### Executable scripts
- **`athena-query.sh`** — `athena-query.sh "<sql>"` or pipe SQL on stdin. Prints CSV. Includes `--dry-run` flag that runs `EXPLAIN` only (used by the premortem skill).
- **`athena-describe.sh`** — no arg → `SHOW TABLES`; arg → `DESCRIBE <table>`.
- **`whoami.sh`** — `SELECT id, name FROM organizations WHERE id = '$ROOT_ORG_ID'`. Prints org + region + env. Non-zero exit if no row.
- **`list-orgs.sh`** — `SELECT id, name FROM organizations ORDER BY name`.
- **`profile-table.sh <table>`** — emits a profile block: row count, max(created_at) for freshness, null-rate per column, distinct-count for low-cardinality columns. Output is designed to be appended verbatim to the agent's context as ground truth for subsequent decisions.
- **`export-results.sh <name> "<sql>"`** — runs the query, saves CSV under `.agents/evidence/<UTC-timestamp>-<name>/` along with a `manifest.json` (query text, org id, env, query execution id, row count, sha256 of CSV). The evidence folder is gitignored. Used by compliance and BI skills.
- **`save-view.sh <name> "<sql>"`** — wraps `CREATE OR REPLACE VIEW <name>_view AS <sql>`; rejects names that don't end with `_view`, and additionally requires one of the intent prefixes (`fact_`, `dim_`, `ops_`) so a typo can't bury an ops queue inside the analytical layer. The skill that's invoking it (`bi-view` vs `ops-dataset`) chooses the prefix.
- **`feedback-note.sh --kind <kind> --target <file> --note "<msg>"`** — appends one JSON line to `.agents/feedback/<date>.jsonl` (`{ts, session, kind, target, note, org_id, env}`). `kind` is one of the categories in `references/feedback-schema.md` (`description-miss`, `reference-thrash`, `tool-gap`, `rule-missing`, `progressive-disclosure`, `success-pattern`). Cheap to call — the agent should reach for it the moment it notices friction.
- **`regression-record.sh <name> "<sql>"`** — runs the SQL, then writes `.agents/regressions/<name>.json` containing `{name, sql, org_id, env, captured_at, captured_by, result_shape, result, query_execution_id, data_scanned_bytes, notes}`. **Refuses to record** unless the SQL contains a hard time bound (`BETWEEN`, `< 'YYYY-...'`, or `>= … AND < …`) — goldens must pin a fixed historical window, never "now". The tool also rejects names that already exist (re-recording requires `--re-record` + a note explaining the legitimate data change, so drift is never silent).
- **`regression-check.sh [<name>|--all]`** — re-runs the stored SQL and asserts equality against the recorded `result`. Exits non-zero on mismatch with a diff (`expected:` vs `actual:`, top-level numeric delta if applicable). `--all` runs every file under `.agents/regressions/` — used by the agent as a cheap "did I break anything" check after view edits, and used by humans before publishing changes.

**Verbose / debug behaviour.** Every script honours `ROOT_AGENTS_DEBUG=1`: prints the resolved `aws athena …` command, `DataScannedInBytes`, `EngineExecutionTimeInMillis`, and the query id to stderr. With or without debug, every tool invocation also writes one JSONL line to `.agents/sessions/<session>.jsonl` (`{ts, tool, args_hash, ok, ms, bytes_scanned}`) so the retro skill has ground truth without re-asking the agent. Think of `sessions/*.jsonl` as the equivalent of a verbose log and `feedback/*.jsonl` as the agent's annotations on top of it.

All tools `set -euo pipefail` and call `aws` from `$PATH` (no `--profile`; env vars take precedence).

## Skill design

Every `.md` under `.agents/skills/` opens with YAML frontmatter so the agent can route on description alone:

```yaml
---
name: <skill-name>
description: <one tight sentence: what it does>. Use when <triggers>. Do NOT use when <anti-triggers>.
---
```

Bodies follow the existing repo style (H1, `## Steps`, `## Reference`, `→` cross-links).

### Skills and their routing descriptions

1. **`whoami.md`**
   *Use when:* the agent has just started, or `ROOT_ORG_ID` may have changed, or the user asks "which org am I in?".
   *Do NOT use when:* you've already called it this session and `ROOT_ORG_ID` hasn't changed.
   Wraps `whoami.sh`.

2. **`explore-schema.md`**
   *Use when:* you need to know what tables/columns exist before writing SQL, or a query failed with "column not found".
   *Do NOT use when:* the table is already in `references/schema.md` and the question doesn't need new columns.
   Composes `athena-describe.sh` + `LIMIT 5` samples.

3. **`premortem.md`** *(new — gating skill)*
   *Use when:* about to run a query that (a) scans a large table without a date filter, (b) joins three or more tables, (c) writes a view, (d) exports evidence, or (e) the user described an analysis but didn't write SQL.
   *Do NOT use when:* the query is a `LIMIT 10` exploration or a `whoami`.
   Steps: state the intent in one sentence; list the 3 most likely failure modes (wrong env, stale snapshot, cents/rand mix-up, PII leak, partition scan cost); run `athena-query.sh --dry-run` to get `DataScannedInBytes`; only then proceed. Output is a short block the agent commits to context before running.

4. **`profile-data.md`** *(new — context-priming skill)*
   *Use when:* you've just learned a new table is relevant, or before any non-trivial aggregation, or when the user asks "is the data good enough to answer X?".
   *Do NOT use when:* the table has been profiled this session and the question hasn't changed scope.
   Steps: run `profile-table.sh <table>`; append the output to context; flag any column with >5% nulls or stale max(created_at); decide which columns are safe to aggregate on. The profile output is explicitly framed as **context for the next agent decision**.

5. **`run-query.md`**
   *Use when:* you have a specific SQL question and the schema is known.
   *Do NOT use when:* you haven't run `premortem` for a wide/expensive query, or you don't yet know the table shape (run `explore-schema` first).
   Wraps `athena-query.sh` with iteration guidance for `FAILED` queries.

6. **`analyst-workflow.md`** *(new)*
   *Use when:* the user asks an open-ended analysis question — funnels, cohorts, retention, lifetime value, churn drivers, distribution of X.
   *Do NOT use when:* the user has a specific row-level question (use `run-query`), or wants a recurring dashboard (use `bi-report`).
   Steps: clarify the question → `profile-data` the relevant tables → start narrow (single cohort, single month) → widen only after the narrow version makes sense → save a `_view` once stable. References `references/examples.md` for canonical recipes (active-policies, payment-failure, retention-by-cohort).

7. **`compliance-query.md`** *(new)*
   *Use when:* DSAR (data subject access request), regulator request, audit trail, retention check, or "show me all data we hold on person X / policy Y / claim Z".
   *Do NOT use when:* the question is exploratory or aggregated; compliance always works at the **identified-record level** and the output is evidence, not insight.
   Steps: confirm the subject identifier (policyholder_id, id_number, email) → for each table that may reference the subject, run a deterministic `SELECT * WHERE …` → call `export-results.sh` so every query is captured with its manifest under `.agents/evidence/`. Default `LIMIT` is removed (compliance must be complete). Cross-references `rules.md` on PII handling.

8. **`bi-view.md`** *(new — dimensional / analytical layer)*
   *Use when:* you are building the **reusable analytical layer** a BI tool will read repeatedly — KPIs across cohorts/time/segments, exec dashboards, anything that downstream consumers will *re-aggregate*.
   *Do NOT use when:* the deliverable is a flat list ops will work through (use `ops-dataset`), a one-off question (use `run-query`), or a compliance dump (use `compliance-query`).
   Steps:
   1. **Declare the grain** in one sentence ("one row per policy per day", "one row per payment attempt"). Refuse to proceed if the grain is fuzzy.
   2. Separate **facts** (additive measures: premiums, claim amounts, payment counts) from **dimensions** (descriptive context: policyholder, product, time, geography). One fact table, many dimension tables joined on keys.
   3. Use **conformed dimensions** — one `dim_date_view`, one `dim_policyholder_view`, one `dim_product_view` reused across fact tables. Never duplicate dimensional logic across views.
   4. Naming convention is **strict**: `fact_<event>_view` (e.g. `fact_payments_view`) and `dim_<entity>_view` (e.g. `dim_policyholder_view`). The `save-view.sh` tool requires the prefix.
   5. **SCD handling.** Snapshots are daily; default to SCD type 1 (overwrite — latest dimension wins). If type 2 (history-preserving) is genuinely required, document the chosen pattern in the view's RATIONALE file — don't fake it.
   6. No `SELECT *` in facts. Each measure is named and typed.
   7. `premortem` the view (BI queries run on every dashboard refresh — cost compounds).
   8. Persist via `save-view.sh`; write a sibling `.agents/bi/<view>.md` documenting grain, facts, dimensions, refresh cadence, and which dashboard consumes it.
   Hands off to `/dev-data-adapter` for the BI-tool wiring — this framework's job ends at the modelled view.

9. **`ops-dataset.md`** *(new — operational / action layer)*
   *Use when:* ops asked for "the list of …" they will work through (failed payments to retry, claims awaiting decision, policies expiring this week, beneficiaries missing ID). Or a downstream sink (Sheets, Zapier, a CSV drop) needs a flat denormalised feed.
   *Do NOT use when:* the consumer is a BI tool that will re-aggregate (use `bi-view`), or the question is exploratory (use `analyst-workflow`).
   Steps:
   1. **Name the action**, not the data ("policies needing payment retry", not "failed payments"). The view name encodes the action: `ops_<action>_view` (e.g. `ops_failed_payments_to_retry_view`).
   2. **Pre-filter to the actionable rows only** — this is a queue, not an archive. `WHERE` should be aggressive.
   3. **Pre-join and denormalise.** One row per action, every column ops needs already present (policyholder name, contact, amount, last-attempted-at). No further joins required downstream.
   4. **Rank by urgency** with `ORDER BY` (oldest-first, highest-amount-first, whatever ops decides). The order is part of the contract.
   5. Skip Kimball discipline on purpose — surrogate keys, conformed dimensions, and SCDs are overhead the operational consumer won't use. State this explicitly in the sibling doc so it's not mistaken for sloppiness.
   6. `premortem` for the daily cost; persist via `save-view.sh`; document the **downstream action** in `.agents/ops/<view>.md` ("feeds the retry queue at 09:00 SAST", "exported to ops Sheets nightly").
   Cross-references `/dev-data-export` for SFTP/S3/HTTPS scheduled delivery if the dataset feeds an external system.

10. **`multi-org-query.md`**
    *Use when:* the user asks "across all our orgs…" and `ROOT_ORG_IDS` is set, or `list-orgs.sh` returned >1 row.
    *Do NOT use when:* only one org is in scope, or the query is org-internal (compliance is per-subject-per-org).
    Steps: split `ROOT_ORG_IDS`; loop, re-export `ROOT_ORG_ID`; call `whoami`+`run-query` per iteration; prepend an `org_id` / `org_name` column to each result; concatenate.

11. **`regression-test.md`** *(new — deterministic check on agent work)*
    *Use when:* (a) you just built a `fact_*_view`, `dim_*_view`, or `ops_*_view` and want a future-proof check; (b) you just produced a headline number a human will act on and want a second opinion; (c) you edited an existing view and want to confirm downstream answers didn't drift; (d) before publishing any analytical result to a stakeholder.
    *Do NOT use when:* the query is inherently non-deterministic (uses `NOW()`, `CURRENT_DATE`, an unbounded `MAX(created_at)`, or unfixed sampling), or the data is sandbox/scratch (goldens belong on production).
    Steps:
    1. **Pick a fixed historical window** — e.g. `WHERE created_at >= '2025-01-01' AND created_at < '2025-04-01'`. Verify the window is closed (no open `>=` without a paired upper bound). The tool will refuse otherwise.
    2. Compute the expected value yourself first (from `analyst-workflow` or `bi-view` work). Don't record a golden you haven't reasoned about — that just freezes a possible bug.
    3. `regression-record.sh <descriptive-name> "<sql>"` — name encodes the assertion (`total_active_premium_2025q1`, `failed_payments_count_2024h2`, `dim_policyholder_row_count_2025-03-01`). Captures the result, query id, scanned bytes, and capture context.
    4. Cross-check immediately by calling `regression-check.sh <name>` once — confirms the round-trip works and the SQL is stable.
    5. **When data legitimately changes** (a backfill, a corrected source record), don't silently re-record. Use `--re-record` with a `--note` describing the change; the old value stays in git history.
    6. **Integration points:**
       - `bi-view` and `ops-dataset`: record at least one golden when the view stabilises (default name: `<view>_<historical-period>`).
       - `analyst-workflow`: when you ship a headline number, record it as a golden so the next session can reproduce it.
       - `profile-data`: optional — pin row counts and null rates for a historical window as goldens; drift on next run = upstream data changed.
       - `retro`: a `regression-check --all` failure becomes a high-priority feedback note (kind `rule-missing` or `tool-gap`) so the cause is investigated, not papered over.

12. **`observe.md`** *(feedback loop, in-session)*
    *Use when:* you just hit friction — a skill's description didn't trigger and should have, you had to re-read the same reference more than once, a tool was missing a flag, a rule would have saved you, or you discovered a recipe worth keeping. Call this **the moment** you notice; do not wait for a retro.
    *Do NOT use when:* the friction was a user typo or a transient AWS error.
    Steps: pick a `kind` from `references/feedback-schema.md`; identify the `target` file (e.g. `.agents/skills/profile-data.md`, `.agents/rules.md`); call `feedback-note.sh` with a one-sentence `note` that names the symptom *and* the suggested fix shape ("description should mention 'cohort retention'", "rule needed: timezone defaults to UTC, not org timezone"). One note per friction event — do not batch.

13. **`retro.md`** *(feedback loop, end-of-session)*
    *Use when:* the user asks for an end-of-session review, the session is wrapping, or `.agents/feedback/<today>.jsonl` has ≥10 entries.
    *Do NOT use when:* the session was a one-off compliance export with no friction (check the file is non-empty first).
    Steps: read `feedback/*.jsonl` + `sessions/*.jsonl` for the active session; group by `target` file; for each grouped cluster, draft a concrete diff (description rewrite, new rule line, new tool flag, reference promoted into AGENTS.md) and write it under `.agents/proposals/<UTC-ts>/<target-basename>.patch` with a sibling `RATIONALE.md` linking back to the feedback entries. **Never edit the live skill/tool/rule files.** Hand control back to the user with a one-screen summary: top 3 proposals, total entries reviewed, files touched. The user (or a follow-up Claude session) applies the patches with normal review.

### `.agents/AGENTS.md` — entry point
- Persona: "You are operating the Root Data Adapter via AWS CLI."
- Required env vars table (link to `references/env-vars.md`).
- Quickstart: `bash .agents/tools/whoami.sh` → `profile-data` → first analysis.
- **Decision tree** mapping user-intent shapes to skills (one-off question → `run-query`; open-ended → `analyst-workflow`; "show me everything on…" → `compliance-query`; reusable analytical layer / KPI dashboard → `bi-view`; "list of things ops needs to action" / flat denormalised feed → `ops-dataset`; "across our orgs" → `multi-org-query`). The bi-view vs ops-dataset split is called out explicitly with one example each.
- Reminder that `premortem` and `profile-data` are *gating skills* the agent should reach for proactively, not on user request.
- **Feedback loop pledge** (one short paragraph): "If anything in this framework felt wrong — a description that didn't fire, a reference you had to re-open, a rule you wished existed — call `observe` immediately. At end of session, run `retro` to turn those notes into proposed edits." This sits near the top of the file so it's read on every session start.
- **Regression pledge** (one short paragraph): "Before publishing any number a human will act on, run `regression-check --all`. When you build a view or ship a headline figure, record a golden against a fixed historical window so future sessions can verify their answer matches yours." Sits next to the feedback pledge.
- Pointer to `rules.md` and `references/feedback-schema.md`.

### `.agents/rules.md`
Distilled from `dev-data-adapter.md` + the constraints of agentic CLI usage:
1. Always include `WHERE environment = '$ROOT_ENV'` (default `production`).
2. Money columns are **cents** — divide by 100 only at display time.
3. Dates are ISO 8601 strings — wrap with `from_iso8601_timestamp()` before arithmetic.
4. Snapshots are **daily**, not real-time. State this in any report.
5. JSON columns (`module`, `charges`, `data`) need `JSON_EXTRACT_SCALAR`.
6. Custom views must end with `_view`. **View prefix encodes intent**: `fact_*_view` and `dim_*_view` for the dimensional/Kimball analytical layer (see `bi-view`); `ops_*_view` for action-oriented operational caches (see `ops-dataset`). Don't mix the two — a view is either modelled for re-aggregation or for direct human action.
7. Never embed an `AWS_*` value in a query, filename, or log line.
8. Default to `LIMIT 1000` on exploratory queries; remove only for aggregates or compliance exports.
9. **Premortem before wide queries.** Run `athena-query.sh --dry-run` for any query without a date filter or with three or more joins.
10. **Profile before you analyse.** A profile output is required context before publishing numbers, especially aggregates.
11. **Compliance output is evidence.** Always route compliance work through `export-results.sh` so the manifest captures org id, env, sql, and CSV hash.
12. **Observe friction in real time.** If a skill's description didn't match, a reference was re-read, a tool flag was missing, or a gotcha tripped you up, call `feedback-note.sh` *before* moving on. Cheap and silent — the cost of skipping it is paying the same friction again next session.
13. **Retro never edits live files.** `retro` writes patches under `.agents/proposals/`. Live skills/tools/rules change only through normal review.
14. **Check your work against goldens.** Before publishing any analytical number — a KPI, a board-pack figure, a regulator-facing total — run `regression-check.sh --all` (cheap) or at minimum the golden(s) covering the same domain. A red golden is a stop-the-line event, not a thing to retry.
15. **Goldens are time-bounded.** Every regression file pins a closed historical window. Never record a golden against `NOW()`, current-month, or "active right now" — those drift legitimately and will produce meaningless failures.

## Feedback loop — how the framework improves itself

The framework treats every session as an opportunity to optimise itself. Two analogies the user named:

- **Verbose flag** → `ROOT_AGENTS_DEBUG=1` plus the always-on `.agents/sessions/*.jsonl` trace. Tools narrate what they did; the agent doesn't have to remember.
- **Debug mode** → the agent is encouraged to *interrupt itself* and drop a `feedback-note.sh` entry the moment something felt off. Notes are categorised so they cluster cleanly at retro time.

Categories (defined in `references/feedback-schema.md`, also embedded as `--kind` values in `feedback-note.sh`):

| Kind | Meaning | Typical target |
|---|---|---|
| `description-miss` | A skill's description didn't trigger when it should have, or triggered wrongly | `skills/<name>.md` frontmatter |
| `reference-thrash` | A reference was opened more than once in the same session | `references/<name>.md` → consider promoting into `AGENTS.md` |
| `tool-gap` | A tool needed a flag/feature it didn't have | `tools/<name>.sh` |
| `rule-missing` | A gotcha hit that wasn't in `rules.md` | `rules.md` |
| `progressive-disclosure` | A skill body was needed because the description was too thin, or a body fact would have been better in the description | `skills/<name>.md` |
| `success-pattern` | A useful recipe worth capturing for next time | `references/examples.md` |

Cadence:

- **In-session** (`observe` skill): write notes as friction occurs. One note per event, not batched.
- **End-of-session** (`retro` skill): cluster notes by target file, draft patches under `.agents/proposals/<ts>/`, hand back to the user.
- **Cross-session** (optional, manual): the user (or a fresh Claude session) reviews `.agents/proposals/`, applies the ones that hold up, deletes the rest. Applied patches become the next session's defaults.

Guardrails:

- `retro` is **read-only against the live framework** — patches live in `proposals/` so a bad note cannot silently corrupt a skill description.
- `sessions/` and `feedback/` are gitignored; `proposals/` is checked in so review history is preserved.
- The `description-miss` and `progressive-disclosure` kinds intentionally make the skill-description quality measurable session-over-session: a skill that keeps generating misses is a skill that needs rewriting, not a skill the agent should keep working around.

## Hand-off from existing repo

- `CLAUDE.md` (root) gets a single new row in the catalog: `| `.agents/AGENTS.md` | Agentic data-adapter operations via AWS CLI (no MCP) |`. No other edits to existing skills — the framework is additive.
- `.agents/AGENTS.md` cross-links back to `/dev-data-adapter` for the BI-tool/dashboard path so the two stay complementary.
- `.gitignore` gets `.agents/evidence/` so compliance exports never end up in git.

## Critical files to create

- `/home/user/scratch/.agents/AGENTS.md`
- `/home/user/scratch/.agents/rules.md`
- `/home/user/scratch/.agents/tools/_lib.sh`
- `/home/user/scratch/.agents/tools/athena-query.sh`
- `/home/user/scratch/.agents/tools/athena-describe.sh`
- `/home/user/scratch/.agents/tools/whoami.sh`
- `/home/user/scratch/.agents/tools/list-orgs.sh`
- `/home/user/scratch/.agents/tools/profile-table.sh`
- `/home/user/scratch/.agents/tools/export-results.sh`
- `/home/user/scratch/.agents/tools/save-view.sh`
- `/home/user/scratch/.agents/tools/feedback-note.sh`
- `/home/user/scratch/.agents/tools/regression-record.sh`
- `/home/user/scratch/.agents/tools/regression-check.sh`
- `/home/user/scratch/.agents/skills/{whoami,explore-schema,premortem,profile-data,run-query,analyst-workflow,compliance-query,bi-view,ops-dataset,multi-org-query,regression-test,observe,retro}.md`
- `/home/user/scratch/.agents/regressions/.gitkeep`
- `/home/user/scratch/.agents/bi/.gitkeep` and `/home/user/scratch/.agents/ops/.gitkeep` (per-view documentation lands here)
- `/home/user/scratch/.agents/references/{env-vars,schema,athena-sql,examples,feedback-schema}.md`
- `/home/user/scratch/.agents/proposals/.gitkeep` (so the dir is tracked while empty)

## Files to edit

- `/home/user/scratch/CLAUDE.md` — append one row to the skill catalog pointing at `.agents/AGENTS.md`.
- `/home/user/scratch/.gitignore` *(create if absent)* — add `.agents/evidence/`, `.agents/sessions/`, `.agents/feedback/` (keep `.agents/proposals/` tracked).

## Reuse from existing repo

- Table catalog, JSON/date/cents idioms, common query patterns: lifted from `/home/user/scratch/.claude/commands/dev-data-adapter.md` into `.agents/references/`. Existing skill stays as the BI-tool reference.
- Skill markdown style (H1, `## Steps`, `## Reference: …`, `→` cross-link arrow): mirror the convention used by `dev-quote-hook.md`, `rp-test.md`, etc., *with* the addition of YAML frontmatter (new convention scoped to `.agents/` so existing skills aren't disturbed).

## Verification

1. **Static checks**
   - `bash -n .agents/tools/*.sh`; `shellcheck` if available.
   - Every skill file starts with `---\nname:\ndescription: …\n---` (grep check).
2. **Env wiring**
   - With env exported, `bash .agents/tools/whoami.sh` prints the org name in <10s.
   - Unset `ROOT_ORG_ID` → friendly error from `require_env`.
3. **Query + profile + premortem path**
   - `athena-query.sh "SELECT COUNT(*) FROM policies WHERE environment = 'production'"` returns an integer.
   - `profile-table.sh policies` emits a populated profile block (rows, freshness, null rates).
   - `athena-query.sh --dry-run "SELECT * FROM policies JOIN payments USING (policy_id) JOIN claims USING (policy_id)"` reports `DataScannedInBytes` without running the full query.
4. **Compliance path**
   - `export-results.sh dsar-policy-123 "SELECT * FROM policies WHERE policy_id = '...'"` creates `.agents/evidence/<ts>-dsar-policy-123/{results.csv,manifest.json}`; manifest contains org id, env, query, sha256.
5. **BI path (dimensional)**
   - `save-view.sh fact_payments "SELECT … WHERE environment='production'"` succeeds; `save-view.sh active_policies "…"` is **rejected** (missing intent prefix).
   - The sibling `.agents/bi/fact_payments.md` exists with declared grain, facts, dimensions, and refresh cadence.
6. **Ops path (action-oriented)**
   - `save-view.sh ops_failed_payments_to_retry "SELECT … WHERE status='failed' AND attempts < 3 ORDER BY created_at"` succeeds.
   - The sibling `.agents/ops/ops_failed_payments_to_retry.md` documents the downstream action (who reads it, when, what they do with it).
   - Running `ops-dataset` for a query that re-aggregates (no `ORDER BY`, group-by-heavy) prompts the agent to switch to `bi-view`.
7. **Multi-org fan-out**
   - `ROOT_ORG_IDS="<id1>,<id2>"`; the `multi-org-query` skill produces one consolidated CSV with an `org_id` / `org_name` column.
8. **Doc sanity / cold-read**
   - Open `.agents/AGENTS.md` cold and confirm a fresh reader can reach "first query returned" by following only the linked references.
   - Confirm the decision tree in `AGENTS.md` lands the agent on `premortem` → `profile-data` for any aggregate-shaped question, on `compliance-query` for "show me all data on…", and on `bi-report` for "recurring KPI".
9. **Regression testing**
   - `regression-record.sh total_active_premium_2025q1 "SELECT SUM(monthly_premium) FROM policies WHERE environment='production' AND created_at >= '2025-01-01' AND created_at < '2025-04-01'"` writes `.agents/regressions/total_active_premium_2025q1.json` with the captured result.
   - Recording a SQL without a closed time bound (e.g. `WHERE created_at >= '2025-01-01'` with no upper bound, or any `NOW()`) is **rejected** by the tool.
   - Recording the same name twice without `--re-record` is **rejected**.
   - `regression-check.sh total_active_premium_2025q1` exits 0 and prints `OK` when the answer matches; if you intentionally edit the SQL to a wrong shape, it exits non-zero and prints a `expected: … / actual: …` diff.
   - `regression-check.sh --all` runs the whole folder and reports pass/fail counts.
10. **Feedback loop**
   - With `ROOT_AGENTS_DEBUG=1`, run a query and confirm verbose output + a JSONL line in `.agents/sessions/<id>.jsonl`.
   - `feedback-note.sh --kind tool-gap --target tools/athena-query.sh --note "needs --format json"` appends a well-formed JSON line to `.agents/feedback/<date>.jsonl`.
   - Seed 3+ feedback entries across different `kind`s; run `retro`; confirm `.agents/proposals/<ts>/` contains one patch per `target` plus a `RATIONALE.md`, and that **no live skill/tool/rule file changed**.

---

# Phase 2 additions

The v1 framework is shipped. This phase layers three changes on top, driven by what surfaced once the framework was in hand:

1. **Naming fix.** The Athena table is `organizations` (not `organisations`), and the primary key is `organization_id` (not `id`). Mechanical sweep across the framework.
2. **JSONB schema derivation + learned skills.** Many columns (`policies.module`, `policies.charges`, `claims.module`, `policy_events.data`, `product_module_definitions.settings/.billing`) are JSON varchars whose key shape is defined by the product module — not in Athena. The agent needs a workflow to derive that shape on demand, and a way to crystallise the result into a reusable skill **in-session** without waiting for retro.
3. **Framework-evolution decision matrix + a worked example.** As recurring questions surface (the user's example: "how to determine adoption of a feature"), the agent needs a clear rule for whether to capture the pattern as a recipe, a skill, a view, a reference, or a sub-agent. We add a decision-matrix reference and one fully-worked example skill (`feature-adoption`).

## Change 1 — naming fix (`organizations` / `organization_id`)

Mechanical sweep. Wherever the old names appear, swap in the new ones. The Athena query inside `whoami.sh` becomes:

```sql
SELECT organization_id, name FROM organizations WHERE organization_id = '$ROOT_ORG_ID' LIMIT 1
```

Files to edit:
- `.agents/tools/whoami.sh` (SQL + result-parse — the column name in the CSV)
- `.agents/tools/list-orgs.sh` (SQL — `SELECT organization_id, name FROM organizations ORDER BY name`)
- `.agents/references/schema.md` (table heading, column row, body prose)
- `.agents/skills/whoami.md` (reference to the query inside `## Reference`)
- `.agents/skills/compliance-query.md` (any mention of the table)
- `.agents/AGENTS.md` (env-var table comment about workgroup=schema=S3 prefix; check for any spelt-out reference)

No rule additions — the schema reference is the right home for the column.

## Change 2 — JSONB schema derivation + learned skills

### Background

Module schemas are **not** stored in Athena. They live in product-module source files (`quote-schema.json`, `application-schema.json`) and can be fetched via the Root API. `product_module_definitions.settings` / `.billing` carry runtime config snapshots, not the field schema. So the agent has three sources for "what keys live in this JSONB column?":

| Source | Confidence | Where it lives |
|---|---|---|
| Empirical sampling | medium — observed keys may be optional / version-skewed | Athena (`SELECT … LIMIT 50`) |
| Declared in product-module source | high — authoritative for the version that wrote the row | Local checkout of the product module, or the Root API |
| Declared via Root API | high — same source, fetched live | `GET /product-module-definitions/<id>` |

### New tool — `.agents/tools/root-api.sh`

Wraps `curl` against the Root API so skills can fetch module metadata without leaving the framework.

- Usage: `root-api.sh <METHOD> <path> [--data '<json>']`
- Reads `ROOT_API_KEY` from env, falling back to a line matching `ROOT_API_KEY=` in `.root-auth` (matches the existing `/rp-setup` convention).
- Reads `ROOT_API_BASE_URL` from env, default `https://api.rootplatform.com/v1` (the agent confirms the exact base URL with the user on first call).
- Sets `Authorization: Bearer $ROOT_API_KEY`, `--fail`, `-s`.
- Writes one session-log line per call (`tool=root-api`, no key material).
- Independent of AWS env vars — fails fast with a friendly message if the key is missing, without complaining about `AWS_*`.

### New tool — `.agents/tools/learn-skill.sh`

In-session skill creator. Lets the agent persist a discovered workflow so it (or a sibling session) can route to it later in the same session.

- Usage: `learn-skill.sh <name> --description "<frontmatter description, including use-when / do-NOT-use-when>" --body-file <path>` (or `--body "<inline>"`).
- Writes `.agents/skills/learned/<name>.md` with frontmatter that includes provenance:
  ```yaml
  ---
  name: <name>
  description: <one tight sentence with use-when / do-NOT-use-when>
  learned: true
  learned_at: 2026-05-18T19:30:00Z
  learned_in_session: <session id>
  learned_from_task: <one-line task description provided by --from-task>
  ---
  ```
- Inserts a banner at the top of the body:
  > ⚠️ **Learned skill** — written by the agent in-session, not yet curated. Treat the steps as a hypothesis. Retro will propose promotion to canonical `.agents/skills/` after review.
- **Refuses** if `<name>` collides with a canonical `.agents/skills/<name>.md` — that case calls for an `observe` note proposing an edit to the canonical skill, not a shadow.
- Touch-tracks: any time a tool runs and the active skill is in `learned/`, the session log notes `learned_skill_hit` so retro can score usage.

### New folder — `.agents/skills/learned/`

Tracked in git (a `.gitkeep` placeholder). Conventionally lower-trust than canonical `skills/`. Cleared by a curator decision only — never auto-deleted.

### Agent routing change (in `AGENTS.md`)

> **Skill loading order:** when a skill name appears in the decision tree, check `.agents/skills/<name>.md` first. If it doesn't exist, check `.agents/skills/learned/<name>.md`. When a learned skill is used, **mention the banner to the user** — "I'm using a learned, uncurated skill; results may need extra review."

### New skill — `.agents/skills/derive-jsonb-schema.md`

*Use when:* you need to query a JSONB column (`policies.module`, `policies.charges`, `claims.module`, `policy_events.data`, `product_module_definitions.settings/.billing`) and don't yet know the keys, or the keys vary by product module on the row.

*Do NOT use when:* the keys you need are already in `references/schema.md`, the relevant module schema has been derived earlier this session (check `skills/learned/jsonb-schema-<table>-<column>-<module-key>.md`), or you're doing exploratory sampling with `LIMIT 5` for human eyes.

Steps:
1. **Sample empirically** — pull 50 rows of the JSONB column from Athena. Reference the SQL pattern in `references/athena-sql.md` ("JSON-keys enumeration").
2. **Enumerate keys** using one of two patterns: (a) Presto `map_keys(CAST(col AS map<varchar,json>))` + `UNNEST`, or (b) pipe sampled JSON values through `jq -r 'keys[]' | sort -u`. Both produce a flat list of top-level keys with frequencies.
3. **Identify the product module** for the rows. The `policies` row's link to the product module is undocumented in this repo (per Phase 1 exploration). Probe in order: (a) a `product_module_id` / `module_key` column on `policies`, (b) a key inside the JSON itself (`module.product_module_key` or similar), (c) ask the user. Capture what you find in the learned skill so the next session skips the probe.
4. **Fetch the declared schema** if available:
   - Local: if `/rp-clone` has placed the product module in the working tree, read `quote-schema.json` / `application-schema.json` directly.
   - Remote: `bash .agents/tools/root-api.sh GET /product-module-definitions/<id>` (confirm exact endpoint with the user the first time; capture it in the learned skill).
5. **Reconcile** the empirical and declared sets. Output a key inventory with: `key`, `type` (string / number / object / array), `confidence` (declared / sampled / both), `null_rate`, `example_value`.
6. **Persist as a learned skill** the moment the inventory is useful:
   ```bash
   bash .agents/tools/learn-skill.sh jsonb-schema-policies-module-<module-key> \
     --description "Key inventory for the policies.module JSONB column on product module <key>. Use when querying policies for this module. Do NOT use for other modules — schemas diverge by module." \
     --body-file <inventory>.md \
     --from-task "<one-line description>"
   ```
   Next session: route to `skills/learned/jsonb-schema-policies-module-<module-key>.md` directly. No re-sampling.

### Supporting reference updates

- `.agents/references/athena-sql.md` — add "JSON-keys enumeration" recipe (the `map_keys` + `UNNEST` pattern and the `jq` fallback).
- `.agents/references/env-vars.md` — add `ROOT_API_KEY` (sourced from env or `.root-auth`) and `ROOT_API_BASE_URL` (default URL TBD; confirm with user on first run).

### Retro extension

`retro.md` gets a new clustering pass over `.agents/skills/learned/`:
- Cluster by name prefix (e.g. all `jsonb-schema-*` learned skills).
- For high-usage learned skills (multiple `learned_skill_hit` entries in the session log), draft a promotion patch under `proposals/<ts>/promote-learned-<name>.md` — moves the file to canonical `skills/`, strips the banner, tightens the description.
- For low-usage learned skills, propose deletion with a one-line rationale.
- **Still never edits live files** (rules.md #13 unchanged).

### Rule additions

- New rule: **JSONB discoveries are persisted.** When you derive a JSONB schema you'll reuse this session, call `learn-skill.sh` immediately. The next query routes to the learned skill instead of re-sampling.
- New rule: **Learned skills are advisory.** When the active skill resolves through `skills/learned/`, mention it in the reply ("using a learned skill; review the inventory before publishing").

## Change 3 — framework-evolution decision matrix + worked example

### New reference — `.agents/references/extension-shapes.md`

A one-page decision matrix for "this is a useful thing — where does it live?":

| Shape | Use when | Lives at | Worked example |
|---|---|---|---|
| **Recipe / example** | Canned SQL with ≤2 parameters and no procedural steps | `references/examples.md` | "premium total by status this quarter" |
| **Skill** | Multi-step workflow with decisions and tool composition; the *process* is the asset | `skills/<name>.md` | `feature-adoption` |
| **Learned skill** | Discovered in-session, valuable this session, not yet curated | `skills/learned/<name>.md` | `jsonb-schema-policies-module-<key>` |
| **Reference** | Stable lookup or convention (schema, gotchas, idioms) | `references/<name>.md` | `athena-sql.md` |
| **Analytical view** | Becomes a recurring KPI consumed by BI; output is re-aggregated downstream | `fact_*_view` / `dim_*_view` via `bi-view` | `fact_payments_view` |
| **Operational view** | Becomes a recurring ops queue or sink feed; output is acted on row-by-row | `ops_*_view` via `ops-dataset` | `ops_failed_payments_to_retry_view` |
| **Regression golden** | A deterministic number that future sessions must reproduce | `regressions/<name>.json` via `regression-test` | `total_active_premium_2025q1` |
| **Sub-agent** | A persona / decision-tree / context-budget that differs enough from the default agent that the routing would diverge. **Reserved — not built in v1.** | `agents/<persona>/AGENTS.md` (folder + own decision tree) | Future: "claims analyst", "compliance officer" |

The matrix includes a short flowchart at the bottom: "Single SQL fragment? → example. Steps and decisions? → skill. Re-aggregated by a tool? → analytical view. Acted on row-by-row? → operational view. Discovered ad-hoc? → learned skill. Persona changes? → sub-agent."

### New skill — `.agents/skills/feature-adoption.md` (the worked example)

*Use when:* the user wants to measure adoption of a product feature — e.g. "how many policies are on plan_type=`premium`?", "what fraction of policies opted into the optional rider?", "how is take-up of the new benefit trending month-over-month?".

*Do NOT use when:* the question is about absolute counts (`run-query`), engagement rate per user (`analyst-workflow`), or a recurring dashboard KPI that just needs a view (`bi-view`).

Steps:
1. **Clarify the feature signal.** Get one unambiguous predicate from the user: a column equality, a JSONB key presence, a value at a JSONB path. Write it as one expression.
2. **Clarify the base population.** All policies, active policies, policies started in 2025 — get one filter and write it down.
3. **Clarify the grain.** Default to: snapshot today + monthly trend back 6 months. Ask if the user wants a different window.
4. **Derive the JSONB schema** via `derive-jsonb-schema` if the signal lives in a JSON column and the keys aren't yet known.
5. **Profile the base population** (`profile-data`) — adoption rates against a stale or null-heavy base are noise.
6. **Compute:** `count(adopters) / count(base)` for the snapshot; `… GROUP BY date_trunc('month', from_iso8601_timestamp(created_at))` for the trend.
7. **Sanity check:** adopters + non-adopters = base. If they don't, find the missing rows before publishing.
8. **Persist by cadence:**
   - One-off → leave the SQL in chat + add a parameterised "feature adoption template" to `references/examples.md`.
   - Recurring → save as `fact_feature_adoption_<feature>_view` via `bi-view`.
   - Triggers ops action ("contact non-adopters") → save as `ops_<feature>_non_adopters_view` via `ops-dataset`.
9. **Pin a regression golden** for the snapshot at a closed historical date (e.g. `feature_adoption_<feature>_2025-04-30`) so the next session can verify.

The skill body includes one fully worked template SQL block to seed the agent's first run.

### Update — `examples.md`

Append a parameterised "feature adoption" template:

```sql
WITH base AS (
  SELECT policy_id, module
  FROM policies
  WHERE environment = 'production'
    AND status = 'active'                  -- <base population>
),
adopters AS (
  SELECT policy_id
  FROM base
  WHERE JSON_EXTRACT_SCALAR(module, '$.<feature_path>') = '<feature_value>'  -- <feature signal>
)
SELECT
  (SELECT COUNT(*) FROM adopters) AS adopters,
  (SELECT COUNT(*) FROM base) AS base,
  1.0 * (SELECT COUNT(*) FROM adopters) / NULLIF((SELECT COUNT(*) FROM base), 0) AS adoption_rate
```

### Update — `AGENTS.md` decision tree

Add two rows:
- "Schema unknown for a JSONB column" → `derive-jsonb-schema`.
- "What fraction of X has feature Y?" → `feature-adoption`.

And a footnote near the decision tree: "Not sure which shape your discovery belongs in? See `references/extension-shapes.md`."

### Sub-agents — placeholder, not built

The decision matrix names `agents/<persona>/AGENTS.md` as the sub-agent shape. We **do not build any sub-agents in v1.** The reasons (recorded in `extension-shapes.md`):
- The current single-agent decision tree (13 + 2 new skills = 15) is still inside one screen.
- A sub-agent is only justified when the persona, decision tree, or context budget diverges enough that the parent's routing would be confused by holding both.
- When that day comes, the shape is: `.agents/agents/<persona>/AGENTS.md` (own decision tree) + `.agents/agents/<persona>/skills/` (curated subset, possibly symlinked to canonical skills).
- A `retro` proposal will surface "sub-agent candidate" when several `description-miss` notes cluster around audience-shaped disagreement (e.g. analyst vs ops vs compliance all needing different defaults for the same skill).

## Files changed in Phase 2

**Edit:**
- `.agents/AGENTS.md` — env vars (+ `ROOT_API_KEY`, `ROOT_API_BASE_URL`), decision tree (+ jsonb-schema, feature-adoption), skill loading order (learned/ second), pointer to `extension-shapes.md`.
- `.agents/rules.md` — add two rules (persist JSONB discoveries; learned skills are advisory).
- `.agents/references/schema.md` — `organizations` table, `organization_id` column.
- `.agents/references/env-vars.md` — `ROOT_API_KEY`, `ROOT_API_BASE_URL`.
- `.agents/references/examples.md` — feature-adoption template.
- `.agents/references/athena-sql.md` — JSON-keys enumeration recipe.
- `.agents/skills/whoami.md` — query reference (table/column).
- `.agents/skills/compliance-query.md` — table reference.
- `.agents/skills/retro.md` — learned-skills clustering pass.
- `.agents/skills/observe.md` — note that JSONB-schema discoveries are a typical learn-skill target (cross-link, not a new kind).
- `.agents/tools/whoami.sh` — SQL.
- `.agents/tools/list-orgs.sh` — SQL.

**Create:**
- `.agents/tools/root-api.sh`
- `.agents/tools/learn-skill.sh`
- `.agents/skills/derive-jsonb-schema.md`
- `.agents/skills/feature-adoption.md`
- `.agents/skills/learned/.gitkeep`
- `.agents/references/extension-shapes.md`

## Phase 2 verification

1. **Naming sweep**
   - `grep -rn organisations .agents/ CLAUDE.md` returns nothing.
   - `bash .agents/tools/whoami.sh` runs the new query against `organizations`.
2. **Root API tool**
   - `bash .agents/tools/root-api.sh GET /v1/users/me` (or equivalent) returns a 200 + JSON body.
   - Run with `ROOT_API_KEY` unset → friendly error pointing at `references/env-vars.md`.
3. **Learn-skill tool**
   - `bash .agents/tools/learn-skill.sh test-learned --description "trial" --body "## hello" --from-task "verify"` creates `.agents/skills/learned/test-learned.md` with the provenance frontmatter and banner.
   - Same call with a name that exists in canonical `skills/` is **rejected**.
4. **JSONB schema derivation end-to-end**
   - Sample `policies.module`, enumerate keys, produce a reconciled inventory.
   - Persist as `jsonb-schema-policies-module-<key>.md` under `skills/learned/`.
   - Re-running the same query routes through the learned skill (the session log shows `learned_skill_hit`).
5. **Feature-adoption skill**
   - Walk through the worked example end-to-end on `plan_type` (or whichever JSONB key is real in the test org).
   - Save as `fact_feature_adoption_plan_premium_view`.
   - Pin a regression golden against a closed historical date.
6. **Decision-matrix doc**
   - Cold-read `references/extension-shapes.md`. Each row has a worked example pointing to a real file in the framework.
7. **Retro learned-skills pass**
   - Seed `.agents/skills/learned/foo.md` + several `learned_skill_hit` entries in the session log.
   - Run `retro`; confirm `.agents/proposals/<ts>/promote-learned-foo.md` appears with a curated description and a "strip the banner" diff.
   - **No live skill/tool/rule file changed.**

---

# Phase 3 additions — output formats and delivery (the "last mile")

## Context

End-to-end agentic data work has a last-mile problem: once you have the answer, how does it reach its consumer? The framework currently emits CSV to stdout (`athena-query.sh`) and CSV with a manifest for compliance (`export-results.sh`). Real consumers want:

- **JSON / JSONL** when a Node or Python app is reading the output
- **Parquet** when a data-engineering pipeline is consuming it (typed, columnar, cheap to re-read)
- **Excel** when ops or finance opens the file directly
- **Styled HTML / PDF** when the destination is an exec/board pack
- **SFTP / HTTPS push** when delivery is to a third party

Plus the existing channels (local file, S3, BI tool via view, `/dev-data-export` for scheduled delivery, `.agents/evidence/` for compliance).

This iteration ships the **core** of the format/delivery layer and a **decision matrix** that names the deferred bits explicitly so the next iteration knows what to build and why.

## Scope (per user decision)

**In scope, build now:**
- Decision matrix reference (`references/output-formats.md`).
- CSV (existing default), JSON, JSONL, TSV via `athena-query.sh --format`.
- Parquet (and ORC/JSON) via a new `athena-unload.sh` wrapping Athena `UNLOAD`.
- Local file + S3 + existing `/dev-data-export` and `.agents/evidence/` delivery.
- New skill `format-output.md` that uses the matrix to route consumer → format → delivery.

**Deferred (named in the matrix, not built):**
- Excel (xlsx) — toolchain TBD; matrix tells the user to run a one-off Python script or wait.
- Styled HTML/PDF reports — defer to a future iteration; matrix points at `/dev-documents` (Handlebars + Root render) as the in-codebase precedent or Python (Jinja2 + WeasyPrint) as an alternative.
- Ad-hoc SFTP push — matrix points at `/dev-data-export` for scheduled, and "run `lftp`/`sftp` manually with explicit user confirmation" for ad-hoc until a tool lands.
- HTTPS push to a Node/Python app — same posture: `curl` with **per-call user confirmation** (chosen safety model), allowlist tooling deferred.

Each deferred row says explicitly: "tool not built; do X instead; revisit when N usage signals accumulate."

## Decision matrix (the heart of `references/output-formats.md`)

| Consumer | Format | Tool | Delivery |
|---|---|---|---|
| Human, ad-hoc in chat | CSV | `athena-query.sh` (default) | stdout |
| Human, ad-hoc as a file | CSV | `athena-query.sh > file.csv` | local file |
| Ops queue, working through the list | CSV | `ops-dataset` view → `athena-query.sh` | local file / Sheets paste |
| Ops queue, recurring delivery | CSV | `ops-dataset` view | `/dev-data-export` (SFTP/S3/HTTPS scheduled) |
| Data pipeline (Spark/dbt/etc.) | **Parquet** | **`athena-unload.sh ... --format parquet`** | S3 (`s3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/unloads/<name>/`); pipeline pulls |
| Node / Python app, batch pull | JSON or JSONL | `athena-query.sh --format jsonl > file.jsonl` then `aws s3 cp` | S3; app pulls |
| Node / Python app, batch via UNLOAD | JSON | `athena-unload.sh ... --format json` | S3; app pulls |
| Node / Python app, push (TBD) | JSON | *deferred* — `curl` with explicit user confirmation per call | HTTPS POST |
| Exec / board pack | Styled HTML or PDF | *deferred* — use Jinja2 + WeasyPrint as one-off, or `/dev-documents` if the policy-document pattern fits | local file / email link |
| Spreadsheet user (Excel) | xlsx | *deferred* — one-off Python `pandas` + `openpyxl` script | local file |
| BI tool (Power BI / Tableau / Looker) | SQL view | `bi-view` → `save-view.sh fact_*/dim_*` | JDBC/ODBC via `/dev-data-adapter` |
| Compliance / regulator | CSV + manifest | `export-results.sh` | `.agents/evidence/<ts>-<name>/` (gitignored, hash-sealed) |

The matrix sits next to `references/extension-shapes.md` — that one decides **what artefact** the discovery becomes; this one decides **what format and channel** the artefact's *output* takes. Cross-link both ways.

## New tool — `.agents/tools/athena-unload.sh`

Wraps Athena's `UNLOAD` statement. Designed for the Parquet path but also supports ORC and JSON.

```bash
bash .agents/tools/athena-unload.sh <name> "<sql>" \
  [--format parquet|orc|json]      # default parquet
  [--compression snappy|gzip|none] # default snappy for parquet
  [--partition-by col1,col2]       # optional partition keys
```

Behavior:
- Translates to `UNLOAD (SELECT ...) TO 's3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/unloads/<name>/' WITH (format='PARQUET', compression='SNAPPY')`.
- Rejects SQL containing DDL keywords (`CREATE`, `DROP`, `ALTER`, `INSERT`, `DELETE`, `UPDATE`) — UNLOAD wraps only `SELECT` queries.
- Refuses if `<name>` already exists under the unload prefix and `--re-unload` isn't passed (mirrors the regression-record safety pattern — never silently overwrite a published artefact).
- Echoes the S3 URI on success so downstream pipelines/scripts can pick it up.
- Reuses `_lib.sh`'s session logging — one line per call with `bytes_scanned`.

## Extend `.agents/tools/athena-query.sh`

Add `--format <csv|json|jsonl|tsv>`:
- Default: CSV (current behavior).
- `json`: emit a single JSON array of row objects (header row → keys).
- `jsonl`: emit one JSON object per line — the format Node/Python apps prefer.
- `tsv`: tab-separated for paste-into-spreadsheet.

Implementation:
- CSV is already the engine output. The format layer runs on the CSV the script already has.
- Use `python3` (already a soft dep in `_lib.sh`'s JSON escape helper) for `json`/`jsonl` conversion. Fall back to `awk` for `tsv`. Fail with a clear error if `python3` is missing for JSON formats.

## New skill — `.agents/skills/format-output.md`

*Use when:* you have a query result and need to deliver it to a named consumer (data pipeline, Node/Python app, ops queue, exec, etc.) — i.e., the result is leaving the chat.

*Do NOT use when:* the result stays in chat (`run-query` covers it), the consumer is a BI dashboard (`bi-view`), or the output is compliance evidence (`compliance-query` already routes through `export-results.sh`).

Steps:
1. **Identify the consumer.** One row in the `references/output-formats.md` matrix. If the consumer doesn't fit any row, ask the user; don't pick by similarity.
2. **Pick the format** from the row. State the choice in the reply ("Parquet, snappy-compressed, partitioned by month") so the consumer knows what they're getting.
3. **Pick the delivery**:
   - In-scope channel → run the tool the matrix names.
   - Deferred channel → tell the user the tool isn't built yet, do the safe fallback the matrix names, and call `observe --kind tool-gap --target tools/<missing>.sh --note "<what would have helped>"` so the deferred bucket fills with real signal.
4. **Confirm size & cost before pushing.** For Parquet UNLOAD on >1 GB scans, mention the `bytes_scanned` from the session log and ask the user to confirm before re-running on a wider date range.
5. **Tell the consumer how to consume.** "Parquet at `s3://bucket/org_id/unloads/<name>/`, schema-on-read, snappy" — not just "done".
6. **Pin a regression golden** if the delivered output is a deterministic snapshot that future runs should match (rules.md #14).

## New rules (in `rules.md`)

20. **Output format follows the consumer, not the producer's preference.** Default to CSV for humans; JSON/JSONL for programmatic consumers; Parquet for data pipelines. The matrix is `references/output-formats.md` — when in doubt, route through it explicitly rather than picking by reflex.
21. **Parquet via Athena UNLOAD beats CSV-then-convert.** For >10k rows or for typed downstream consumers, use `athena-unload.sh --format parquet`. CSV roundtrips lose types (everything becomes string), Parquet preserves them.
22. **PII never leaves via unvetted destinations.** Until SFTP/HTTP push tools land, ad-hoc delivery is local-file or S3 only (and S3 within the same org's prefix). Compliance evidence stays inside `.agents/evidence/`. When the push tools land, the safety model is **per-call user confirmation** for every destination outside the allowlist (decision recorded here so the future implementation honours it).

## Updates to existing files

**`AGENTS.md`**:
- Decision-tree row: "Result is leaving the chat (file / S3 / pipeline / app)" → `format-output`.
- Cross-link: "Where does this output go? See `references/output-formats.md` for the format × delivery matrix."
- No new env vars for in-scope tools. Deferred future vars (`SFTP_*`, `OUTPUT_ALLOWED_HOSTS`) named in a "deferred" note so they don't surprise the next iteration.

**`references/extension-shapes.md`**:
- Add a one-line cross-link to `output-formats.md`: "Once you know the artefact shape (this matrix), the format-and-delivery matrix is in `output-formats.md`."

**`references/examples.md`**:
- New recipe: **Parquet unload for a data pipeline** — full `athena-unload.sh` invocation with partition-by and the S3 URI it produces.
- New recipe: **JSONL feed for a Node/Python app** — `athena-query.sh --format jsonl > file.jsonl` followed by `aws s3 cp file.jsonl s3://...` and a one-line Python snippet showing the consumer side.

## Files

**Create:**
- `.agents/references/output-formats.md`
- `.agents/tools/athena-unload.sh`
- `.agents/skills/format-output.md`

**Edit:**
- `.agents/tools/athena-query.sh` — add `--format` flag.
- `.agents/AGENTS.md` — decision-tree row + cross-link.
- `.agents/rules.md` — rules 20, 21, 22.
- `.agents/references/extension-shapes.md` — cross-link to output-formats.md.
- `.agents/references/examples.md` — two new recipes.

## Phase 3 verification

1. **CSV default** — `athena-query.sh "SELECT 1 AS n"` returns CSV (header + row).
2. **JSON format** — `athena-query.sh --format json "SELECT 1 AS n"` returns valid JSON parseable by `jq -e .`.
3. **JSONL format** — `athena-query.sh --format jsonl "SELECT 1 AS n UNION ALL SELECT 2"` returns two lines, each parseable by `jq -e .`.
4. **TSV format** — `athena-query.sh --format tsv` returns tab-separated output.
5. **Invalid format flag** — `--format xml` is rejected with a clear list of accepted values.
6. **Parquet UNLOAD** — `athena-unload.sh sample_parquet "SELECT COUNT(*) FROM policies WHERE environment='production'" --format parquet` writes to `s3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/unloads/sample_parquet/`; the S3 URI is echoed; `aws s3 ls` shows `.parquet` files.
7. **DDL guard** — `athena-unload.sh bad "DROP TABLE policies"` is rejected with a clear error before hitting AWS.
8. **Re-unload guard** — re-running the same `<name>` without `--re-unload` is rejected.
9. **Matrix cold-read** — `references/output-formats.md`: every in-scope row points at a real tool; every deferred row says explicitly that the tool isn't built and what to do instead.
10. **Cross-link** — `extension-shapes.md` ↔ `output-formats.md` both point at each other; AGENTS.md decision tree points at `format-output` and `format-output.md` points back at the matrix.

---

# Phase 4 additions — context-size safety (the "don't burn my tokens" rule)

## Context

Yes — this should be a rule, and the rule needs **tool-level enforcement** to actually bite. Without it, a single `bash .agents/tools/athena-query.sh "SELECT * FROM payments"` on a million-row table dumps ~200 MB of CSV into the agent's stdout and into the conversation. Athena will gladly oblige; the framework currently won't stop it.

What we already have:
- Rule #8 — "default `LIMIT 1000` on exploratory queries". A *convention*, not enforced.
- The output-formats matrix — *implies* big results should go to files / S3, but the agent has to choose; nothing stops them from choosing stdout.

What's missing: a hard, default-on cap on rows / bytes printed to stdout, plus loud escape valves so the agent can deliberately route around it when needed.

## Change — rule + enforcement

### New rule (`rules.md` #23): Never read large result sets into context.

> Tools that print to stdout cap output at `ROOT_AGENTS_MAX_ROWS` rows (default 1000) and `ROOT_AGENTS_MAX_BYTES` bytes (default 200 KB). When the cap fires, the tool prints the head + a loud truncation footer naming the escape valves: `--to-file <path>`, `--head N`, `--no-row-cap`, or route through `export-results.sh` / `athena-unload.sh` for typed output. Never disable the cap silently — if you use `--no-row-cap`, say in the reply why the full output had to land in context.

### Tool enforcement

**`tools/athena-query.sh`** (extend):
- After the query completes, read `Statistics.OutputRows` and `Statistics.DataScannedInBytes` from `aws athena get-query-execution`. Cheap — already paid for as part of polling.
- New flags:
  - `--to-file <path>` — write full result (in the chosen format) to the file. Stdout receives only `<path> rows=<N> bytes=<B> s3_uri=<athena results s3 uri>` so the agent knows where the data is without ingesting it.
  - `--head N` — stream header + first N data rows (default behavior when the cap fires; this flag lets the agent set N explicitly).
  - `--no-row-cap` — explicit override; print the full result. The tool still prints a one-line **stderr** warning naming the row count and the byte estimate so the override is impossible to use accidentally.
- Default behavior:
  - `OutputRows <= ROOT_AGENTS_MAX_ROWS` → print everything (current behavior, no footer).
  - `OutputRows > ROOT_AGENTS_MAX_ROWS` → print the head (= `ROOT_AGENTS_MAX_ROWS` rows) + footer:
    ```
    ... truncated at 1000 of <N> rows.
    Full result: s3://<athena-results-uri> (typed in your chosen format)
    Re-run with --to-file <path>, --head <N>, --no-row-cap,
    or route via export-results.sh / athena-unload.sh.
    ```
  - Exit 0 in both cases (truncation is helpful, not an error).

**`tools/root-api.sh`** (extend):
- `--max-bytes N` (default `ROOT_AGENTS_MAX_BYTES`, 200 KB): if the response body exceeds the cap, print head + truncation footer. `--no-truncate` to override.
- Why: a `GET /v1/policies/<id>` returns a known small object, but a list endpoint with pagination disabled can be huge.

**`tools/regression-check.sh`** (extend):
- On mismatch, cap printed `expected:` and `actual:` blocks at 50 lines each with a `... truncated (N more lines, full file at <path>)` footer.
- The full mismatch detail is always available by reading the regression JSON file.

### Env vars

- `ROOT_AGENTS_MAX_ROWS` — default `1000`. Cap for stdout rows.
- `ROOT_AGENTS_MAX_BYTES` — default `200000` (200 KB). Cap for `root-api.sh` and any future byte-based printer.

Documented in `references/env-vars.md` alongside the existing knobs.

### Skill / reference updates

- `skills/premortem.md` — add **return size** as a third dimension to consider, alongside scan cost and failure modes. The premortem template gets one new line: `Estimated rows returned: <answer>`. If the agent doesn't know, that's a signal to add `LIMIT 50` to the query and rerun before going wide.
- `skills/run-query.md` — mention the cap and the three escape valves (`--to-file`, `--head`, `--no-row-cap`) so the agent can route around it deliberately when the use case warrants.
- `skills/format-output.md` — cross-link: "If you're hitting the row cap on `athena-query.sh`, that's the framework telling you the output should be formatted-and-delivered, not pasted in chat. Route via this skill."
- `AGENTS.md` — one short line in the rules/pledges section: *"Token-friendly default: stdout caps at 1000 rows / 200 KB. Big results land in files or S3."*

### Session log

When the cap fires, `_lib.sh` (or the tool itself) writes one line to the session log:

```json
{"ts":"...","session":"...","tool":"athena-query","ok":true,"row_cap_hit":true,"rows":<N>,"capped_at":1000}
```

`retro` reads these — a high rate of `row_cap_hit` is a signal that the agent is doing analytical work in chat and would benefit from saving a view (`bi-view`) or routing through `format-output`. The retro proposal in that case suggests a `description-miss` patch on `run-query` ("description should steer >1000-row work to format-output").

## Files

**Edit:**
- `.agents/tools/athena-query.sh` — `--to-file`, `--head`, `--no-row-cap`, default truncation logic, OutputRows fetch.
- `.agents/tools/root-api.sh` — `--max-bytes`, `--no-truncate`.
- `.agents/tools/regression-check.sh` — cap mismatched diff output.
- `.agents/rules.md` — rule #23.
- `.agents/AGENTS.md` — short pledge line.
- `.agents/references/env-vars.md` — `ROOT_AGENTS_MAX_ROWS`, `ROOT_AGENTS_MAX_BYTES`.
- `.agents/skills/premortem.md` — return-size dimension.
- `.agents/skills/run-query.md` — cap + escape valves.
- `.agents/skills/format-output.md` — cross-link to the cap rule.

**Create:** nothing new. Discipline layer on existing tools.

## Phase 4 verification

1. **Small result (<1000 rows)** — `athena-query.sh "SELECT 1 AS n"` prints `n\n1`, no footer, no warning.
2. **Auto-truncation** — synthesize a query returning >1000 rows (`SELECT n FROM UNNEST(SEQUENCE(1,2000)) t(n)`). Default invocation prints 1000 rows + the footer naming the S3 URI and the escape valves.
3. **`--head 50`** — header + 50 rows, footer states `... truncated at 50 of <total> rows`.
4. **`--to-file /tmp/out.csv`** — file written, stdout reads `/tmp/out.csv rows=<N> bytes=<B> s3_uri=s3://...`, **no data in stdout**.
5. **`--no-row-cap`** — full result prints; stderr carries `warning: --no-row-cap on <N>-row result (~<B> bytes); explain in reply why this had to land in context`. Session log still records `row_cap_hit=true`.
6. **`root-api.sh --max-bytes 1024`** on a >1 KB response — head + truncation footer; `--no-truncate` overrides.
7. **`regression-check.sh`** on a mismatched golden with a >50-line result — `expected:` and `actual:` blocks each capped at 50 lines with a footer pointing at the regression JSON file.
8. **Cold-read rule #23** — tells the agent what to do without re-reading the surrounding chapter; names every escape valve and which tool implements them.
9. **Retro signal** — seed 5 `row_cap_hit=true` lines in the session log; run retro; confirm `.agents/proposals/<ts>/` contains a `description-miss` proposal against `skills/run-query.md` recommending the steer-to-format-output rewrite.

---

# Phase 5 additions — local pre-aggregation (the "context is for interpretation, not iteration" principle)

## Context

`FUTURE.md` §2 is being promoted out of the menu and into the framework. The user calls this "non-negotiable" because Athena queries are easily large: a single `SELECT * FROM payments` is enough to torch a session's tokens. Rule #23 (Phase 4) caps stdout *defensively*; this phase adds the **positive** counterpart — what the agent should do *instead* when an analytical question needs many rows but the answer is a small table.

The principle:

> Context tokens are scarce. Each row of CSV in context is one fewer token available for *thinking about what the data means*. Raw data lives on disk / S3. Local processing happens **in-file**. Only the summarised result enters context for interpretation.

Three-tier flow this phase formalises:

1. **Pull, don't print.** `athena-query.sh --to-file out.csv "<sql>"` or `athena-unload.sh <name> "<sql>" --format parquet`. The agent never sees the raw rows.
2. **Process locally.** `duckdb-query.sh "<sql>" --input out.csv` (or an `s3://...` URI). Aggregate, group, percentile, top-N, anomaly detect. Output is a small table.
3. **Reason in context.** The agent sees only the summary and interprets it: what does it mean, what's anomalous, what's next.

The asymmetry between Athena (cloud, billed per scanned byte) and DuckDB (local, free) does the heavy lifting. Pay Athena once to produce a typed Parquet file. Iterate on that file with DuckDB for free, as many times as the question needs.

## Engine choice — DuckDB as primary, not pandas

The user said "pandas etc." — but the right primary engine is **DuckDB**, not pandas. Rationale:

| Property | DuckDB | pandas |
|---|---|---|
| SQL dialect | Presto-/Trino-ish (close to Athena) | none (DataFrame API) |
| Mental model the agent already has | identical to `athena-query.sh` | new |
| Reads Parquet from S3 | yes, natively via `httpfs` | needs `pyarrow` + manual setup |
| Reads CSV / JSON | yes, natively | yes |
| Dependency footprint | single binary | Python + pandas + (often) pyarrow |
| Fast on aggregates | columnar engine | DataFrame iteration |

pandas is mentioned as a deferred fallback in §2 of FUTURE.md. We keep that placeholder; we don't build it now. DuckDB covers ~all the use cases the user described, with zero new SQL dialect for the agent to learn. If a real friction signal emerges (an analytical pattern that's awkward in SQL but trivial in DataFrame-land — pivot tables, rolling stats, time-series resampling), a small `pandas-aggregate.sh` can be added later via the normal observe → retro flow.

## New tool — `.agents/tools/duckdb-query.sh`

The workhorse for tier 2 (process locally). Same shape as `athena-query.sh`, same row cap, just a different engine.

```bash
duckdb-query.sh "<sql>" [--input <file-or-s3-uri>] [--format csv|json|jsonl|tsv]
                        [--head N] [--to-file <path>] [--no-row-cap]
```

Behavior:
- **Local input** (CSV, Parquet, JSON file): pass the path; reference inside the SQL as `'path'`. DuckDB reads it natively. `--input` may be omitted entirely when the agent's SQL references the file path directly (`SELECT … FROM 'out.csv'`).
- **S3 input** (`s3://...`): the tool detects the scheme, prepends `INSTALL httpfs; LOAD httpfs;` + `SET s3_region='$AWS_REGION';` and exposes the AWS env credentials via `SET s3_access_key_id`/`s3_secret_access_key`. Reuses the same env vars the rest of the framework already validates.
- **Honors the row cap** from rule #23 — `ROOT_AGENTS_MAX_ROWS` truncation, `--to-file`, `--head`, `--no-row-cap`. Same footer style; same `row_cap_hit` session-log signal so retro sees the same metric uniformly across `athena-query` and `duckdb-query`.
- **Format conversion** (csv/json/jsonl/tsv) — DuckDB has native flags for these (`-csv`, `-json`, `-jsonl`), so the tool dispatches directly instead of post-processing.
- **Dependency check** — `command -v duckdb` first. Friendly install hint if missing: `brew install duckdb` / `curl https://install.duckdb.org | sh` / `pip install duckdb` (CLI variant).
- **No caching for v1** — DuckDB re-fetches S3 on each call. Simpler. Caching only justified when retro shows repeated re-reads against the same prefix.

## New skill — `.agents/skills/pre-aggregate.md`

Names the principle and routes accordingly.

*Use when:* the answer to the user's question is a **summary** (count, group-by, percentile, top-N, distribution, anomaly) but the underlying data is large. Any analytical question where the agent would otherwise be tempted to `--no-row-cap` belongs here.

*Do NOT use when:* the consumer needs the raw rows (compliance evidence → `compliance-query`, row-level ops queue → `ops-dataset`, machine pipeline → `format-output` for Parquet UNLOAD), or the data is small enough to fit under the stdout cap.

Steps:
1. **Premortem the return size** (existing premortem skill, rule #9 + Phase 4 update). If the answer is "thousands or millions of rows reduced to a small table", you're in pre-aggregate territory.
2. **Pull to disk or S3:**
   - For one-off, small enough to fit locally: `athena-query.sh --to-file out.csv "<sql>"` (the locator line goes to context; the data does not).
   - For larger or pipeline-shaped: `athena-unload.sh <name> "<sql>" --format parquet` (Parquet to S3; cheap to re-read).
3. **Aggregate locally:** `duckdb-query.sh "<sql>" --input <path-or-uri>`. Iterate freely; DuckDB doesn't bill per byte.
4. **Reason on the summary.** Only the small result enters context. State the source (file or S3 URI) so the reasoning is reproducible.
5. **Pin a regression golden** if the summary is a headline number a human will trust. The golden's SQL can be the DuckDB one — `regression-check` just re-runs and compares.

Worked example walked end-to-end inside the skill: "what fraction of policies adopted plan_type=premium, by month, for Q1 2025?". Pulled once to Parquet, then sliced three ways in DuckDB — by month, by region, by cohort — without re-billing Athena.

## New rule (`rules.md` #24)

**24. Aggregate before reading.** If your analysis produces a summary (count, group-by, percentile, top-N, anomaly), do the aggregation **locally on a file** with `duckdb-query.sh` — never pull the raw rows into context. The flow is: `athena-query.sh --to-file` or `athena-unload.sh` → `duckdb-query.sh` on the file → small summary into context. Exceptions: compliance evidence (every row must be visible) and ops queues (every row is an action item).

This rule is paired with #23 (the defensive cap). #23 stops the bleeding; #24 names the right move instead.

## Updates to existing files

- **`AGENTS.md`** — new decision-tree row: "Analytical question on a big dataset (summary as the answer, not the rows)" → `pre-aggregate`. Short pledge near the existing pledges: *"Pull, then aggregate locally. Context is for interpretation, not iteration."*
- **`references/athena-sql.md`** — short "DuckDB compatibility note" section: same JSON / date / aggregate idioms work; a few small differences (DuckDB has `quantile_cont`, native `PIVOT`/`UNPIVOT`, looser type coercion). Cross-link to `duckdb-query.sh` usage.
- **`references/output-formats.md`** — add a "pre-aggregate first" callout above the matrix: if the consumer is the agent itself (the answer needs interpretation, not just delivery), the flow ends at `duckdb-query.sh`, not at the delivery channels. The matrix is for *machine* consumers; `pre-aggregate` is for the *agent* as consumer.
- **`references/examples.md`** — one new recipe: "Pre-aggregate on Parquet" — full Athena UNLOAD → DuckDB three-way slice walkthrough.
- **`skills/run-query.md`** — cross-link to `pre-aggregate` when the agent finds itself wanting to slice the same dataset multiple ways or running into the row cap.
- **`skills/format-output.md`** — distinguish from `pre-aggregate` in one sentence: format-output is for *external* consumers, pre-aggregate is for *the agent's own interpretation*.
- **`skills/premortem.md`** — when the "return size" line is in the thousands-to-millions range and the answer is a summary, the premortem decision should be `route via pre-aggregate`.
- **`FUTURE.md`** — delete §2 (built in this PR) and renumber §§3–10 → §§2–9. Per the process note in FUTURE.md: "**Delete the corresponding section from this file** in the same PR. The list shrinks. That's the feature."

## Files

**Create:**
- `.agents/tools/duckdb-query.sh`
- `.agents/skills/pre-aggregate.md`

**Edit:**
- `.agents/rules.md` — add #24.
- `.agents/AGENTS.md` — decision-tree row + short pledge.
- `.agents/references/athena-sql.md` — DuckDB compatibility note.
- `.agents/references/output-formats.md` — pre-aggregate-first callout.
- `.agents/references/examples.md` — Parquet + DuckDB recipe.
- `.agents/skills/run-query.md` — cross-link to pre-aggregate.
- `.agents/skills/format-output.md` — distinguish from pre-aggregate.
- `.agents/skills/premortem.md` — pre-aggregate as a routing decision.
- `.agents/FUTURE.md` — delete §2; renumber 3–10 → 2–9.

## Phase 5 verification

1. **Dependency check** — with `duckdb` missing from `$PATH`, `duckdb-query.sh "SELECT 1"` exits non-zero with a friendly install hint naming `brew`/`curl`/`pip` options.
2. **Trivial local query** — `echo 'a,b\n1,foo\n2,bar' > /tmp/t.csv && duckdb-query.sh "SELECT COUNT(*) FROM '/tmp/t.csv'"` returns `2`.
3. **Local CSV aggregation** — synthesise a 5000-row CSV; `duckdb-query.sh "SELECT col, COUNT(*) FROM '/tmp/big.csv' GROUP BY col"` returns ≤ROOT_AGENTS_MAX_ROWS rows of summary without hitting the cap (the *summary* is small, even though the input is large).
4. **Row-cap fires on raw select** — `duckdb-query.sh "SELECT * FROM '/tmp/big.csv'"` truncates at 1000 with the same footer style as `athena-query.sh`, including the `row_cap_hit=true` session-log line.
5. **S3 input** — `duckdb-query.sh "SELECT COUNT(*) FROM 's3://$ROOT_ATHENA_S3_BUCKET/$ROOT_ORG_ID/unloads/sample_parquet/*.parquet'"` returns the row count without going through Athena. Requires the Phase 3 unload to have run first.
6. **End-to-end pre-aggregate flow** — `athena-query.sh --to-file /tmp/policies.csv "SELECT … LIMIT 10000"` (or `athena-unload.sh sample "..." --format parquet`) → `duckdb-query.sh "SELECT status, COUNT(*) FROM '/tmp/policies.csv' GROUP BY status"` → small grouped result in context.
7. **Format flags** — `duckdb-query.sh --format jsonl …` returns one JSON object per line; `--format json` returns a single array. Same shape contract as `athena-query.sh`.
8. **Escape valves** — `--head 50`, `--to-file /tmp/out.csv`, `--no-row-cap` behave identically to `athena-query.sh`'s equivalents (same footers, same stderr warnings).
9. **Rule #24 cold-read** — actionable in isolation; names the right alternative (pre-aggregate) and the exceptions (compliance, ops queues).
10. **FUTURE.md** — §2 is gone; §§3–10 renumbered; no orphaned references in other docs. `grep -rn '§2\|section 2\|FUTURE.md#2' .agents/` returns nothing.

---

# Phase 6 additions — hash-based identifier obfuscation for committed goldens

## Context

The merged framework was used in production-shaped sessions. Real signal accumulated. Two things show up on `git pull`:

1. `.gitignore` was extended to exclude `.agents/regressions/`. Someone (correctly) refused to commit golden files because they embed raw `org_id` and `query_execution_id` — fine for local debugging, not fine for a shared / public repo.
2. `FUTURE.md` §2 grew a new bullet: *"Redaction in committed artefacts — `regression-record.sh` and the feedback JSONL writer should strip or blank internal identifiers (org_id, query execution IDs) before writing."*

The gitignore patch solves the leakage problem but **breaks the original design** where the team shares goldens via git. Goldens that never leave the laptop they were recorded on aren't really regression tests — they're personal notes.

The user's refinement on the FUTURE.md bullet: **SHA the identifiers, don't strip them.** Hashing is lossless within the trust boundary: same org → same hash, so per-org goldens stay separable; different orgs → different hashes, so multi-org goldens coexist in one repo without colliding. The hash is non-reversible enough for casual readers but lets the framework re-verify goldens against the current org by hashing on demand.

Outcome: re-enable committing goldens; goldens are org-scoped via subfolder hash; `regression-check --all` only runs goldens for the active org; no raw `org_id` or `query_execution_id` ever lands in git.

## Design decisions

| Decision | Choice | Rationale |
|---|---|---|
| Hash algorithm | **SHA-256** | Standard, available everywhere (`shasum -a 256`). |
| Salt | **None** | Org IDs are UUIDv4 (~122 bits entropy); no practical rainbow table. A salt would break cross-machine determinism without meaningful security gain. |
| Output length | **16 hex chars** (64 bits) | Plenty for collision resistance within a single team's golden set; short enough for readable paths. |
| File layout | **Per-org subfolder**: `.agents/regressions/<org_hash>/<name>.json` | Cross-org goldens don't collide; PR review sees compartmentalised hashes; `--all` iterates only one folder. |
| Fields obfuscated | `org_id` → `org_id_hash`; `query_execution_id` → **omitted entirely** | QEID is per-query unique and only useful for re-fetching from S3 within minutes of the run; no audit value once recorded. Omitting is simpler than hashing. |
| Scope | **Regressions only** | Sessions/feedback stay gitignored — they're local runtime, no use case for committing them. If a future iteration commits them, the same `hash_id` helper applies. |
| Backwards compat | **None needed** | `.agents/regressions/` is empty locally; no old goldens to migrate. |

## Files

**Edit:**

- `.agents/tools/_lib.sh` — add `hash_id <value>` helper (`printf '%s' "$1" | shasum -a 256 | cut -c1-16`).
- `.agents/tools/regression-record.sh`:
  - Compute `org_hash="$(hash_id "$ROOT_ORG_ID")"`.
  - Write file to `$AGENTS_ROOT/regressions/$org_hash/<name>.json` (create parent dir).
  - Re-record collision check operates on the new path.
  - JSON shape changes: drop `org_id`, drop `query_execution_id`, add `org_id_hash`.
- `.agents/tools/regression-check.sh`:
  - Compute the current org's hash; only scan `regressions/<org_hash>/` for `--all`.
  - For named lookup: `regressions/<org_hash>/<name>.json`.
  - On `regressions/<other_hash>/*` (cross-org files): ignore silently — they belong to a different org.
- `.agents/tools/whoami.sh` — add a fifth output line `Org hash: <16-char hex>` so the user can map subfolder names to orgs in their own head.
- `.gitignore` — remove the `.agents/regressions/` line. Add a comment above explaining: goldens are committed; identifiers are hashed (see `skills/regression-test.md`).
- `.agents/skills/regression-test.md` — update path examples to `<org_hash>/`; note the per-org compartmentalisation; mention that goldens are now committed and shared via git.
- `.agents/rules.md`:
  - Extend rule #15: "...Golden SQL is **aggregate-shaped** (counts, sums, percentiles) so the committed `result` field is innocuous — row-level captures belong in `export-results.sh` evidence, not in regressions."
  - New rule #25: "**Committed identifiers are hashed.** `regression-record.sh` writes `org_id_hash` (not `org_id`) and omits `query_execution_id`. Goldens live under `regressions/<org_hash>/`. The raw values stay in the local session log only. See `tools/_lib.sh` `hash_id`."
- `.agents/AGENTS.md` — update the Layout section: "`regressions/` — committed deterministic goldens, **per-org subfolder by hash**."
- `.agents/FUTURE.md` — delete only the **"Redaction in committed artefacts"** bullet from §2 (the rest of §2 — view-usage tooling, prune skill, doc freshness, golden hygiene — remains unbuilt). Per the process note: when an item ships, delete it.

**Do not edit:** `feedback-note.sh`, `_session_log` / `_session_log_extra` (the sessions/ and feedback/ files stay gitignored; no need to hash anything in them — but the `hash_id` helper is general-purpose if they ever need it).

## Verification

1. **Helper determinism** — `hash_id foo` twice in the same shell returns the same 16-char hex. Across shells, same.
2. **`whoami.sh`** — prints `Org hash: <16-char hex>` as the fifth line.
3. **Record path** — `regression-record.sh test "SELECT 1 AS n WHERE 1=0 AND created_at >= '2025-01-01' AND created_at < '2025-04-01'"` writes to `regressions/<org_hash>/test.json`, not to the flat directory. (Note: this test SQL won't actually execute against any table; the dry-validation of the time-bound regex passes, but `run_athena` will error. The path-construction step happens after validation but before execution — we can validate it with a mock or by inspecting the script logic.)
4. **JSON shape** — the recorded file contains `org_id_hash` (not `org_id`); does not contain `query_execution_id`.
5. **Check finds the file** — `regression-check.sh test` reads from `regressions/<org_hash>/test.json`.
6. **Cross-org isolation** — manually create a `regressions/aaaaaaaaaaaaaaaa/other.json`. With current `ROOT_ORG_ID`, `regression-check.sh --all` does **not** try to run it. `regression-check.sh other` returns "no such golden" with the right path (`regressions/<current_org_hash>/other.json`).
7. **No leaked plaintext** — `grep -r "$ROOT_ORG_ID" .agents/regressions/` returns nothing. `grep -rE '[a-f0-9-]{36}' .agents/regressions/` (UUID pattern) returns nothing.
8. **`.gitignore` update** — `git check-ignore .agents/regressions/whatever.json` returns nothing (no longer ignored).
9. **Rule #25 cold-read** — actionable; names the path, the helper, and the not-leaked-fields.
10. **FUTURE.md** — only the "Redaction in committed artefacts" bullet is gone from §2; the rest of §2 untouched; the rest of FUTURE.md untouched.
