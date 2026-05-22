# Analyst Agent Framework — Agentic Operating System

You are an analyst agent operating against a remote HTTP API and analysing landed data locally in DuckDB. This framework gives you everything you need to discover an API, land paginated data, build a typed analytical layer, pin regression goldens, run compliance exports, and check your own work — with one API key and a local terminal.

The framework's repeatable pillars:

1. **Safety** — two-layer PII firewall (pre-flight regex + DuckDB result-schema check), three compliance modes, sensitive-output routing to a separate gitignored prefix.
2. **Accuracy** — eight named failure modes (F1–F8), regression goldens against fixed historical windows, reconciliation queries, confidence labels on every published number.
3. **Self-learning** — `observe` → `retro` loop, learned skills, proposals never edit live files.
4. **Telemetry** — Mixpanel events from every tool call so you can see what earns its place.
5. **Feedback capture** — one structured JSONL note per friction event; weekly retro turns clusters into proposals.

## Prerequisites

Four binaries on `$PATH`:

- `duckdb` — local analysis. `brew install duckdb` (macOS) or `curl https://install.duckdb.org | sh`.
- `curl` — API fetches.
- `jq` — JSON extraction in `fetch-api.sh`.
- `python3` — used by the PII firewall, telemetry, and JSON-shape conversions.

### Fastest setup

```bash
cp .agents/.env.example .agents/.env
# edit: API_BASE_URL, API_TOKEN
source .agents/.env
bash .agents/tools/whoami.sh --endpoint /user   # confirm connectivity
```

`.env` is gitignored. Sourcing it once per shell beats re-exporting every session.

| Env var | Required | Purpose |
|---|---|---|
| `API_BASE_URL` | yes | Target API root, e.g. `https://api.github.com` |
| `API_TOKEN` | yes (most APIs) | Bearer token / personal access token |
| `ROOT_AGENTS_COMPLIANCE_MODE` | no (default `strict`) | PII firewall strictness: `strict` requires `--pii-required --reason` even with `--to-file`; `standard` lets `--to-file` alone serve; `off` is dev mode (stderr warning per call). |
| `MIXPANEL_TOKEN` | no | When set, workflow events fire to Mixpanel (EU endpoint). |
| `ROOT_AGENTS_TELEMETRY` | no (default `on`) | Set to `off` to disable telemetry even with a token set. |
| `ROOT_AGENTS_MAX_ROWS` | no (default `1000`) | Max rows tools print to stdout before truncating. |
| `ROOT_AGENTS_MAX_BYTES` | no (default `200000`) | Max bytes ditto. |
| `ROOT_AGENTS_DEBUG` | no | `1` = verbose tool output to stderr. |
| `ROOT_AGENTS_SESSION_ID` | no | Namespace for session traces & feedback (default: today's date UTC). |
| `DUCKDB_PATH` | no | Override the database location (default `.agents/data/db/main.duckdb`). |

See `references/env-vars.md` for the per-source setup walkthrough.

## Quickstart

```bash
bash .agents/tools/whoami.sh --endpoint /user
bash .agents/tools/fetch-api.sh /repos/<owner>/<repo>/pulls \
  --query "state=closed&per_page=100" --paginate link \
  --source github --entity pulls --max-pages 3
bash .agents/tools/land-to-duckdb.sh pulls --source github
bash .agents/tools/profile-table.sh raw_github_pulls
bash .agents/tools/duckdb-query.sh "SELECT count(*) FROM raw_github_pulls"
```

**First-time discovery (new API).** When the framework points at a source for the first time, run `discover-api` (see `skills/discover-api.md`) to probe auth, pagination, rate limits, and core endpoints, then write the findings to `references/sources/<name>.md`.

## Decision tree — pick a skill from intent

| User intent | Skill |
|---|---|
| "Which API / token am I using?" / session start | `whoami` |
| First contact with a new API — what's the shape? | `discover-api` |
| Pull a fresh slice of data into DuckDB | `land-data` |
| "What tables / columns are landed?" | `explore-schema` |
| One specific SQL question, schema known | `run-query` |
| Open-ended analysis — cohorts, retention, churn, distributions | `analyst-workflow` |
| "Show me all data we hold on subject X" | `compliance-query` |
| Reusable analytical layer for a BI tool / KPI dashboard | `bi-view` (Kimball discipline; `bi_*_view`) |
| "The list of things ops needs to action" / flat denormalised feed | `ops-dataset` (`ops_*_view`) |
| Working view I'm iterating on — not yet stable | `save-view.sh --scratch [<ns>]` → `scratch_<ns>_*_view` |
| Sensitive-column analysis (PII tables or json_sensitive columns) | `pii-safe-analysis` |
| JSON column with unknown keys | sample a row, document the safe keys in a learned skill |
| "What fraction of X has feature Y?" / adoption questions | `feature-adoption` |
| Analytical question on a big dataset (answer is a summary) | `pre-aggregate` |
| Result is leaving the chat (file / pipeline / app) | `format-output` |
| Pin / verify a deterministic answer against fixed history | `regression-test` |
| You hit friction — description didn't fire, ref re-read, tool gap | `observe` |
| End of session — turn feedback into proposed edits | `retro` |

**Gating skills** (call proactively, not on user request):
- `premortem` — before any wide / multi-join / view-writing query.
- `profile-data` — before any non-trivial aggregation on a table you haven't profiled this session.

**Skill loading order.** Check `.agents/skills/<name>.md` first. If absent, check `.agents/skills/learned/<name>.md` — learned skills carry a "not yet curated" banner; mention this when you route through one. Promotion to canonical happens through `retro`, never silently.

**Not sure which shape your discovery belongs in?** See `references/extension-shapes.md` for the decision matrix (recipe vs skill vs view vs reference vs learned-skill).

**Where does the output go?** Once an answer leaves the chat — to a file, pipeline, or app — route through `references/output-formats.md` (consumer → format → tool → delivery). Default: CSV for humans, JSONL for apps, Parquet via DuckDB `COPY ... (FORMAT PARQUET)` for pipelines.

**Token-friendly default.** Stdout caps at 1000 rows / 200 KB. When the cap fires, the tool tells you the escape valves (`--to-file`, `--head`, `--no-row-cap`, or route through `format-output`). Don't `--no-row-cap` silently — explain why the full output had to land in context. See rules.md #23.

**Pull, then aggregate locally. Context is for interpretation, not iteration.** Network round-trips and large rowsets both burn tokens. Fetch once with `fetch-api.sh`, land into DuckDB, iterate locally with `duckdb-query.sh`. Only the small summary enters context. See `skills/pre-aggregate.md` and rules.md #24.

**PII never reaches your context or your reply.** Default mode is `strict`. Sensitive SELECTs are blocked from stdout by two layers: a regex pre-flight against `references/pii-columns.json`, then a DuckDB `DESCRIBE` check on the actual result columns before any row is fetched. Override is `--pii-required --reason "<text>"` (logged). For analytical work that touches PII, route via `pii-safe-analysis`: pull to file → `pseudonymize.sh` → `duckdb-query.sh` over hashed values. See `references/pii-safety.md` and rules.md.

**Numbers carry a trust label.** Before publishing any figure a human will act on, run `regression-check.sh --all`, confirm any sidecar reconciliation queries agree, and prefix the number with `[verified|single-source|stale|sandbox|partial]` + as-of + evidence pointer. Labels stack with `pii-redacted` when both apply. The doctrine — eight named failure modes (F1–F8) including F8 incomplete-fetch, the publish-time gate, and the label format — lives in `references/data-trust.md`.

## Telemetry

When `MIXPANEL_TOKEN` is set in `.env`, the framework fires Title Case events to the EU Mixpanel ingestion endpoint. Events fire at workflow milestones, not per query:

- `API Discovery Started` — `whoami` or `discover-api` ran
- `Data Landed` — `fetch-api` or `land-to-duckdb` completed
- `Query Run` — `duckdb-query` executed
- `View Saved` — `save-view` created/replaced a view
- `Regression Recorded` / `Regression Checked`
- `Results Exported` — `export-results` produced an evidence artefact
- `PII Approved` / `PII Touched` — firewall override or `--to-file` route
- `Skill Learned` — `learn-skill.sh` persisted a learned skill
- `Feedback Noted` — `feedback-note.sh` fired
- `Exploration Started` — `explore-schema` / `profile-table` ran

Every event carries: `distinct_id` (git `user.email`), `session_id`, `api_base_hash` (not raw URL), `compliance_mode`, `agents_version`. Calls are backgrounded with a 2s timeout — Mixpanel never blocks a tool. Disable with `ROOT_AGENTS_TELEMETRY=off` or by leaving `MIXPANEL_TOKEN` unset.

## Feedback loop pledge

If anything in this framework felt wrong — a description that didn't fire, a reference you had to re-open, a rule you wished existed, a tool flag you needed — call `observe` immediately. One note per friction event. At end of session, run `retro` to turn those notes into proposed edits under `.agents/proposals/`. The cost of skipping is paying the same friction again next session.

## Regression pledge

Before publishing any number a human will act on, run `bash .agents/tools/regression-check.sh --all`. When you build a view or ship a headline figure, record a golden against a **fixed historical window** so future sessions can verify their answer matches yours. Goldens never use `NOW()` — they pin closed historical ranges.

## Layout

- `rules.md` — hard rules. Read once per session.
- `skills/` — workflow skills with YAML frontmatter (`name`, `description`).
- `skills/learned/` — agent-emitted skills from prior sessions. Lower-trust; carry a banner. Promoted via `retro`.
- `tools/` — bash scripts: `fetch-api.sh`, `land-to-duckdb.sh`, `duckdb-query.sh`, the PII firewall, regression and export tools.
- `references/` — env-vars walkthrough, PII safety, data trust doctrine, DuckDB SQL gotchas, output formats, feedback schema, examples.
- `references/sources/<name>.md` — per-API source docs (auth, pagination, rate limits, endpoint cookbook).
- `references/pii-columns.json` — sensitivity metadata. **Ships as a generic sample**; adopters replace the `example_*` tables with their real schema before any query touches sensitive data.
- `data/raw/` — landed JSONL (gitignored). One file per fetch with a sibling `manifest.json`.
- `data/db/main.duckdb` — local analytical database (gitignored).
- `bi/`, `ops/` — per-view documentation sidecars (grain, refresh, consumers, reconciliation). Scratch views are intentionally undocumented.
- `regressions/<api_base_hash>/` — committed deterministic goldens, per-API subfolder by hash so multiple data sources can coexist without leaking raw URLs to git. See rules.md.
- `proposals/` — `retro` writes patches here for human review (never edits live files).
- `evidence/` / `sensitive/` / `sessions/` / `feedback/` — gitignored runtime artefacts.
- `FUTURE.md` — menu of unbuilt ideas. Pull from when real signal emerges.
- `DESIGN.md` — slim design rationale for this template (points at upstream for full history).

## Adapting the template to your API

Three files need adapting before you query real data:

1. **`.env.example` → `.env`** — set `API_BASE_URL` and `API_TOKEN`.
2. **`references/pii-columns.json`** — ships with `example_*` tables. Replace with your data source's real columns and sensitivity tags. Until you do, the PII firewall will only fire on `example_*` tables (which presumably don't exist), so PII can pass through ungated.
3. **`references/sources/<your-source>.md`** — write the API operating doc (auth, pagination, rate limits, endpoints) via the `discover-api` skill. Use the bundled `references/sources/github.md` as a worked example.

The framework's skills, rules, and PII firewall apply to any structured API source — the only API-specific bits are these three files.
