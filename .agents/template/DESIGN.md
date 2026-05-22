# Design rationale (template-specific)

This template was extracted from the upstream Root Data Adapter agentic framework. The upstream tree is a multi-org, AWS Athena, insurance-domain workbench; the template is a minimal, generic, single-API, DuckDB-local analyst agent that preserves the framework's five repeatable pillars (safety, accuracy, self-learning, telemetry, feedback capture).

For the full design history (six phases of why-it-looks-like-this), read the upstream `DESIGN.md`. This file documents only the **differences** that apply to the template.

## What changed from upstream

### 1. Single SQL backend: DuckDB

Upstream wraps `aws athena` for execution; the template uses DuckDB exclusively. All data lands locally via `fetch-api.sh` + `land-to-duckdb.sh`. The PII firewall's two layers carry over: the regex pre-flight is unchanged; the inline result-schema check uses DuckDB's `DESCRIBE (<sql>)` instead of Athena's `ResultSetMetadata.ColumnInfo`.

Trade-off: DuckDB's `DESCRIBE` returns column **aliases**, not catalog names. `SELECT email AS x` shows as `x` in DESCRIBE output — the regex pre-flight catches `email` in the SQL text, so the firewall still fires, but the inline check alone wouldn't. The combination is safe; either layer alone is not.

### 2. Single API per project

Upstream supports multi-org fan-out (`ROOT_ORG_IDS`, `cross-org-pull.sh`, per-client view suffixes). The template targets one API at a time. The single-API model:

- Drops `--client` from `save-view.sh`.
- Drops `cross-org-explore`, `multi-org-query`, `scope-clarify` skills.
- Keeps `regressions/<api_base_hash>/` subfolder structure — trivially one folder at single-API scale, preserved for portability when an adopter extends to a second API.

### 3. View naming: `bi_/ops_/scratch_`

Upstream uses `fact_/dim_/ops_/scratch_` with an `rp_` framework prefix. The template flattens to `bi_/ops_/scratch_`:

- No `rp_` prefix (no team-level namespacing needed in a fresh project).
- `bi_<entity>_view` covers what upstream split between `fact_*` and `dim_*`. The `bi-view` skill still teaches Kimball discipline and recommends `bi_fact_*` / `bi_dim_*` once a star schema emerges — the namespace is just one tier coarser.

### 4. New failure mode F8: incomplete fetch

Upstream's data-trust model has seven failure modes (F1–F7). At API+DuckDB scale, a new one emerges: **pagination stopped early, table looks complete, number is structurally wrong**. F8 is captured by:

- `fetch-api.sh` writes a sibling `manifest.json` with `complete=true|false`.
- `land-to-duckdb.sh` refuses partial loads without `--allow-partial`; stamps the table comment.
- `profile-table.sh` surfaces the partial flag.
- `regression-record.sh` refuses goldens against partial tables.
- A new `partial` confidence label joins `verified|single-source|stale|sandbox`.

### 5. PII columns ship as a generic sample

Upstream's `pii-columns.json` is the team's real insurance schema. The template ships a domain-agnostic sample (`example_users`, `example_events`, `example_payments`) so the firewall is dormant until an adopter populates the real tables. The framework is upfront about this dormancy in `AGENTS.md` and `pii-safety.md` — adopting the template without populating `pii-columns.json` is a known cliff.

### 6. Skills dropped (8) and added (3)

**Dropped**: `digest-scheduled-functions`, `ops-monthly-invoice`, `ops-scheduled-function-volumes` (Root insurance specifics); `cross-org-explore`, `multi-org-query`, `scope-clarify` (multi-org); `derive-jsonb-schema`, `feature-adoption` (Athena+Presto-specific).

**Added**:
- `discover-api` — probe a new API and document it under `references/sources/<name>.md`.
- `land-data` — the end-to-end pull (fetch → land → profile → regression-check).
- `learn-skill` — when + how to capture a learned skill mid-session.

### 7. Tools dropped (10) and added (3)

**Dropped**: every `athena-*.sh`, `glue-describe.sh`, `pii-lookup.sh`, `root-api.sh`, `migrate-*.sh`, `cross-org-pull.sh`, `discover-orgs.sh`, `list-orgs.sh`, `_skill_telemetry.sh`.

**Added**:
- `fetch-api.sh` — generic HTTP client with auth/pagination/rate-limit/partial-manifest.
- `land-to-duckdb.sh` — JSONL → DuckDB with partial-fetch refusal.
- `duckdb-describe.sh` — `SHOW TABLES` / `PRAGMA table_info` against `main.duckdb`.

### 8. Telemetry properties: `api_base_hash` replaces `org_id`

Mixpanel events carry `api_base_hash` (16-hex SHA-256 prefix of `$API_BASE_URL`) instead of `org_id`. Raw URLs never leave the framework — neither in git nor in telemetry. Same deterministic per-source clustering.

### 9. The `.claude/` directory is not shipped

Upstream's PreToolUse hooks for `Skill` tool calls live at `.agents/.claude/settings.json`. The template omits this directory because:

- It binds the project to one specific host runner (Claude Code).
- The bash-side telemetry already fires the workflow events from inside the tools themselves.
- Adopters who use Claude Code can copy the upstream `.claude/settings.json` if they want extra event coverage.

## Known follow-ups

- **Factor PII firewall into a shared `_lib_pii.sh`.** The block is identical (minus the Athena vs DuckDB inline check) in upstream and template. Wait until the two trees have diverged enough to know which lines are genuinely shared before factoring.
- **Multi-source within one project.** The single-API constraint is a posture, not a hard wall. An adopter who pulls GitHub + Jira + Zendesk into one DuckDB will find the framework copes — `data/raw/github/`, `data/raw/jira/`, etc. coexist naturally. The README mentions this in the "scaling up" note.
- **Push delivery (SFTP / HTTPS / S3).** Out of v1. Rule #19 documents the safety model.
