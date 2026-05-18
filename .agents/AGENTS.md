# Root Data Adapter — Agentic Operating System

You are operating the Root Data Adapter via AWS CLI. This framework gives you everything you need to query an organization's Athena data, profile it, build BI / ops views, run compliance exports, and check your own work — without MCP, without a JDBC driver, just env vars and `aws`.

> Existing skill `/dev-data-adapter` covers the **BI-tool** path (Power BI / Tableau / Looker over JDBC). This framework covers the **agentic CLI** path. The two are complementary — when the final consumer is a dashboard, hand off the modelled view back to `/dev-data-adapter`.

## Prerequisites

`aws` CLI on `$PATH` (v2). Credentials and connection details come from Root Dashboard → Data Management → Data Adapter → Generate Access Key.

| Env var | Required | Purpose |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | yes | AWS auth |
| `AWS_SECRET_ACCESS_KEY` | yes | AWS auth |
| `AWS_REGION` | yes | Region the org's Athena lives in |
| `ROOT_ORG_ID` | yes | Active org — used as workgroup, database/schema, and S3 prefix |
| `ROOT_ATHENA_S3_BUCKET` | yes | Bucket where Athena results land (output = `s3://$BUCKET/$ROOT_ORG_ID/`) |
| `ROOT_ENV` | no (default `production`) | `production` or `sandbox` — used in every `WHERE` filter |
| `ROOT_ORG_IDS` | no | Comma-separated list for multi-org fan-out |
| `ROOT_AGENTS_DEBUG` | no | `1` = verbose tool output to stderr |
| `ROOT_AGENTS_SESSION_ID` | no | Namespace for session traces & feedback |
| `ROOT_API_KEY` | no (`root-api.sh` only) | Root Dashboard API key. Falls back to `.root-auth`. Used for module-schema lookups; independent of AWS |
| `ROOT_API_BASE_URL` | no | Defaults to `https://api.rootplatform.com` |

See `references/env-vars.md` for the dashboard walkthrough.

## Quickstart

```bash
bash .agents/tools/whoami.sh                 # confirm which org you're in
bash .agents/tools/athena-describe.sh        # SHOW TABLES
bash .agents/tools/profile-table.sh policies # row count, freshness, null rates
bash .agents/tools/athena-query.sh "SELECT COUNT(*) FROM policies WHERE environment='production'"
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
| "Across all our orgs…" | `multi-org-query` |
| JSONB column with unknown keys (`module`, `charges`, `data`, `settings`) | `derive-jsonb-schema` |
| "What fraction of X has feature Y?" / "Adoption of …" | `feature-adoption` |
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
- `regressions/` — committed deterministic goldens.
- `bi/`, `ops/` — per-view documentation (grain, refresh, consumers).
- `proposals/` — `retro` writes patches here for human review (never edits live files).
- `evidence/`, `sessions/`, `feedback/` — gitignored runtime artefacts.
- `FUTURE.md` — menu of unbuilt ideas (deferred tools, view pruning, pandas-first pre-aggregation, sub-agents, etc.). Pull from when a real signal emerges; don't burn through top-to-bottom.

## Cross-references

- `/dev-data-adapter` — BI-tool wiring (JDBC/ODBC) once views are stable.
- `/dev-data-export` — scheduled SFTP/S3/HTTPS delivery for ops datasets.
- `/dev-globals` — runtime env vars inside product module code (different surface area).
- `.agents/references/feedback-schema.md` — categories and shape for `observe` notes.
