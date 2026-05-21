# Root Data Adapter — Agentic Operating System

You are operating the Root Data Adapter via AWS CLI. This framework gives you everything you need to query an organization's Athena data, profile it, build BI / ops views, run compliance exports, and check your own work — without MCP, without a JDBC driver, just env vars and `aws`.

> Existing skill `/dev-data-adapter` covers the **BI-tool** path (Power BI / Tableau / Looker over JDBC). This framework covers the **agentic CLI** path. The two are complementary — when the final consumer is a dashboard, hand off the modelled view back to `/dev-data-adapter`.

## Prerequisites

Two binaries on `$PATH`:

- `aws` CLI v2 — Athena queries (`brew install awscli`)
- `duckdb` — local pre-aggregation (`brew install duckdb`); required by `tools/duckdb-query.sh` and rules.md #24

Credentials and connection details come from Root Dashboard → Data Management → Data Adapter → Generate Access Key.

### Fastest setup

```bash
cp .agents/.env.example .agents/.env   # template is committed
# edit .agents/.env with the four values from the Generate Access Key modal
source .agents/.env
bash .agents/tools/whoami.sh           # confirms the org you're now in
```

`.env` is gitignored alongside `.root-auth`. Sourcing it once per shell beats re-exporting every session.

| Env var | Required | Purpose |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | yes | AWS auth |
| `AWS_SECRET_ACCESS_KEY` | yes | AWS auth |
| `AWS_REGION` | no (auto-detected) | Region the org's Athena lives in. Inferred from `ROOT_ATHENA_S3_BUCKET` via `aws s3api get-bucket-location`. Export only to override. |
| `ROOT_ORG_ID` | yes | Active org — used as workgroup, database/schema, and S3 prefix |
| `ROOT_ATHENA_S3_BUCKET` | yes | Bucket where Athena results land (output = `s3://$BUCKET/$ROOT_ORG_ID/`) |
| `ROOT_ENV` | no (default `production`) | `production` or `sandbox` — used in every `WHERE` filter |
| `ROOT_ORG_IDS` | no | Comma-separated list for multi-org fan-out |
| `ROOT_ATHENA_S3_BUCKET_BY_ORG` | no | `uuid:bucket,uuid:bucket` overrides for orgs whose S3 output bucket differs from the default. Consulted by `cross-org-pull.sh` per iteration |
| `AWS_REGION_BY_ORG` | no | `uuid:region,uuid:region` overrides — rarely needed since AWS_REGION auto-detects from the per-org bucket. Only set when an org's region differs without a corresponding bucket override |
| `ROOT_AGENTS_DEBUG` | no | `1` = verbose tool output to stderr |
| `ROOT_AGENTS_SESSION_ID` | no | Namespace for session traces & feedback |
| `ROOT_API_KEY` | no (`root-api.sh` only) | Root Dashboard API key. Falls back to `.root-auth`. Used for module-schema lookups; independent of AWS |
| `ROOT_API_BASE_URL` | no | Defaults to `https://api.rootplatform.com` |
| `ROOT_AGENTS_COMPLIANCE_MODE` | no (default `strict`) | PII safety strictness: `strict` (require `--pii-required --reason` even with `--to-file`), `standard` (--to-file alone is fine), `off` (dev only — warning per call). See `references/pii-safety.md` and rules.md #26–#28 |
| `MIXPANEL_TOKEN` | no | EU Mixpanel project token. When set, eleven workflow-level events fire (see "Telemetry" below). |
| `ROOT_AGENTS_TELEMETRY` | no (default `on`) | Set to `off` to disable Mixpanel even when `MIXPANEL_TOKEN` is set. |

See `references/env-vars.md` for the dashboard walkthrough.

## Quickstart

```bash
bash .agents/tools/whoami.sh                 # confirm which org you're in
bash .agents/tools/athena-describe.sh        # SHOW TABLES
bash .agents/tools/profile-table.sh policies # row count, freshness, null rates
bash .agents/tools/athena-query.sh "SELECT COUNT(*) FROM policies WHERE environment='production'"
```

**First-time / new credentials.** If you've just been issued a multi-org-scoped AWS key and don't yet know which orgs it can reach, run `discover-orgs.sh` to probe Athena workgroups across regions and emit a ready-to-paste `.env` block:

```bash
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... \
  bash .agents/tools/discover-orgs.sh > .env.suggested
diff -u .agents/.env .env.suggested   # review before swapping
```

## Decision tree — pick a skill from intent

| User intent | Skill |
|---|---|
| "Which org am I in?" / session start | `whoami` |
| "What tables / columns are there?" | `explore-schema` |
| One specific SQL question, schema known | `run-query` |
| Open-ended analysis — cohorts, retention, churn, distributions | `analyst-workflow` |
| "Show me all data we hold on policy X / person Y" | `compliance-query` |
| Reusable analytical layer for a BI tool / KPI dashboard | `bi-view` (Kimball: `fact_*`, `dim_*`) |
| "The list of things ops needs to action" / flat denormalised feed | `ops-dataset` (`ops_*_view`) |
| Working view I'm iterating on — not yet stable enough to promote | `save-view.sh --scratch [<ns>]` → `rp_scratch_<ns>_*_view` |
| Question names a specific client / commercial model (invoice, Bordereau, ceded split, profit share) | `scope-clarify` → routes to per-client `bi-view`/`ops-dataset` variant |
| Sensitive-column analysis (PII tables or json_sensitive columns) | `pii-safe-analysis` |
| "Across all our orgs…" — one-shot, concatenated CSV | `multi-org-query` |
| "System-wide / internal insights" — iterate the cross-org dataset locally | `cross-org-explore` |
| "Where should we attack next?" — weekly scheduled-function hotspot digest for the in-house dev tightening targeting | `digest-scheduled-functions` |
| JSONB column with unknown keys (`module`, `charges`, `data`, `settings`) | `derive-jsonb-schema` |
| "What fraction of X has feature Y?" / "Adoption of …" | `feature-adoption` |
| Analytical question on a big dataset (answer is a summary, not the rows) | `pre-aggregate` |
| Result is leaving the chat (file / S3 / pipeline / app) | `format-output` |
| Pin / verify a deterministic answer against fixed history | `regression-test` |
| You hit friction — description didn't fire, ref re-read, tool gap | `observe` |
| End of session — turn feedback into proposed edits | `retro` |

**Gating skills** (call proactively, not on user request):
- `premortem` — before any wide / multi-join / view-writing / evidence-exporting query.
- `profile-data` — before any non-trivial aggregation on a table you haven't profiled this session.

**Skill loading order.** When the decision tree names a skill, check `.agents/skills/<name>.md` first. If it isn't there, check `.agents/skills/learned/<name>.md`. A learned skill carries a "not yet curated" banner — mention this in your reply when you route through one, so the user knows the steps came from a prior agent session, not a reviewed body of work. Promotion from `learned/` to canonical happens through `retro`, never silently.

**Not sure which shape your discovery belongs in?** See `references/extension-shapes.md` for the decision matrix (recipe vs skill vs view vs reference vs learned-skill vs sub-agent).

**Where does the output go?** Once an answer leaves the chat — to a file, S3, a data pipeline, a Node/Python app — route through `references/output-formats.md` (consumer → format → tool → delivery). Default to CSV for humans, JSONL for apps, Parquet via `athena-unload.sh` for pipelines.

**Token-friendly default.** Stdout caps at 1000 rows / 200 KB. When the cap fires, the tool tells you the escape valves (`--to-file`, `--head`, `--no-row-cap`, or route through `format-output`). Don't `--no-row-cap` silently — explain in your reply why the full output had to land in context. See rules.md #23.

**Pull, then aggregate locally. Context is for interpretation, not iteration.** When an analytical question's answer is a *summary* (count / group-by / percentile / top-N / anomaly) but the underlying data is large, route through `pre-aggregate`: pay Athena once to produce a file, iterate on it with `duckdb-query.sh` for free, only the small summary enters context. See rules.md #24.

**PII never reaches your context or your reply.** Default mode is `strict`. Sensitive SELECTs are blocked from stdout by an inline schema check at execution time — `athena-query.sh` reads the actual result columns Athena returns and refuses if any are tagged `pii` / `restricted` / `json_sensitive` in `references/pii-columns.json`. Override is `--pii-required --reason "<text>"` (logged). For analytical work that needs to touch PII, route via `pii-safe-analysis`: pull to file → `pseudonymize.sh` → `duckdb-query.sh` over hashed values. See rules.md #26–#28 and `references/pii-safety.md`.

**Numbers carry a trust label.** Before publishing any figure a human will act on, run `regression-check.sh --all`, confirm any sidecar reconciliation queries agree, and prefix the number with `[verified|single-source|stale|sandbox]` + as-of + evidence pointer. Labels stack with `pii-redacted` when both apply. The doctrine — seven named failure modes (F1–F7), the publish-time gate, and the label format — lives in `references/data-trust.md`. See also rules.md #4, #10, #11, #14.

## Telemetry

When `MIXPANEL_TOKEN` is set in `.env`, the framework fires eleven Title Case events to the EU Mixpanel ingestion endpoint. Events are at the **decision-tree level**, not per-Athena-call:

- **Workflow intent** (fired from the `Skill` PreToolUse hook in `.claude/settings.json`): `Exploration Started`, `BI Work Started`, `Ops Work Started`, `Scope Clarified`.
- **Bash milestones** (fired from `tools/_telemetry.sh` via `_mixpanel_track`): `View Saved`, `Local Processing Started`, `PII Approved`, `PII Touched`, `Evidence Captured`, `Feedback Noted`, `Skill Learned`.

Every event carries: `distinct_id` (git `user.email`), `session_id`, `env`, `org_id`, `compliance_mode`, `agents_version` (git short SHA). Calls are backgrounded with a 2s timeout — Mixpanel never blocks a tool. Disable with `ROOT_AGENTS_TELEMETRY=off` or by clearing `MIXPANEL_TOKEN`. Set `ROOT_AGENTS_DEBUG=1` to see the JSON body before it ships.

## Feedback loop pledge

If anything in this framework felt wrong — a description that didn't fire, a reference you had to re-open, a rule you wished existed, a tool flag you needed — call `observe` immediately. One note per friction event. At end of session, run `retro` to turn those notes into proposed edits under `.agents/proposals/`. The cost of skipping is paying the same friction again next session.

## Regression pledge

Before publishing any number a human will act on, run `bash .agents/tools/regression-check.sh --all`. When you build a view or ship a headline figure, record a golden against a **fixed historical window** so future sessions can verify their answer matches yours. Goldens never use `NOW()` — they pin closed historical ranges.

## Layout

- `rules.md` — hard rules. Read once per session.
- `skills/` — workflow skills with YAML frontmatter (`name`, `description`, `when-to-use`, `when-not-to-use`).
- `skills/learned/` — agent-emitted skills from prior sessions. Lower-trust; carry a banner. Promoted to canonical via `retro`.
- `tools/` — bash scripts wrapping `aws athena` / `aws s3`. Composable.
- `references/` — schema catalog, Athena SQL gotchas, env-var setup, feedback schema, example queries.
- `regressions/<org_id_hash>/` — committed deterministic goldens, **per-org subfolder by hash** so multiple orgs coexist without leaking raw IDs to git. See rules.md #25.
- `bi/clients/<slug>/`, `ops/clients/<slug>/` — per-client commercial-model views (invoicing, Bordereau, etc.). Lives alongside the universal `bi/`/`ops/`. See `references/per-client-analysis.md` and `skills/scope-clarify.md`.
- `references/clients.txt` — registry of known client slugs. `save-view.sh --client <slug>` warns when the slug isn't here.
- `tools/framework-status.sh` — one-screen maturity dashboard (deps, skill/tool counts, views by layer, regression goldens, maturity flags pointing at the next step). Run at session start when something feels off.
- `sensitive/` — gitignored prefix for PII-bearing exports (`export-results.sh` when SQL touches sensitive columns; `pii-lookup.sh` results). Separate from `evidence/` for tighter access control downstream.
- `bi/`, `ops/` — per-view documentation (grain, refresh, consumers). Scratch views are intentionally undocumented — they're ephemeral; if it earns a doc page, it's ready to be promoted.
- `proposals/` — `retro` writes patches here for human review (never edits live files).
- `evidence/`, `sessions/`, `feedback/` — gitignored runtime artefacts.
- `FUTURE.md` — menu of unbuilt ideas (deferred output tools, view pruning, cost baselines, sub-agents, etc.). Pull from when a real signal emerges; don't burn through top-to-bottom.
- `DESIGN.md` — design history. Six phases of why-it-looks-like-this for new developers. Read this when you want the rationale behind a skill, rule, or tool; read `AGENTS.md` (this file) when you want the current shape.

## Cross-references

- `/dev-data-adapter` — BI-tool wiring (JDBC/ODBC) once views are stable.
- `/dev-data-export` — scheduled SFTP/S3/HTTPS delivery for ops datasets.
- `/dev-globals` — runtime env vars inside product module code (different surface area).
- `.agents/references/feedback-schema.md` — categories and shape for `observe` notes.
