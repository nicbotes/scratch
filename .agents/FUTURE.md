# Future ideas — for sessions after this branch ships

Notes for the next time you sit down with this framework, **after the current PR has been merged and the team has actually used it for a sprint or two.** The themes below are deliberately not built — they need real usage signal (concrete `observe` notes, a stakeholder request, a friction event) before they're worth the carrying cost.

## How to use this file

This is a **menu**, not a backlog. Pick when the framework gives a real signal — don't burn through the list top-to-bottom. When you build one of these, **delete its section from this file**. The list shrinks. That's the feature.

---

## 1. Deferred output / delivery tools

Named in `references/output-formats.md` but not built. Each has a documented safe fallback for today.

- **`csv-to-xlsx.sh`** — Excel output for ops/finance. Suggested toolchain: Python + `openpyxl` (or `pandas.DataFrame.to_excel`). Trigger: ≥3 `tool-gap` observe notes, or a concrete finance/ops request.
- **`render-report.sh`** — styled HTML / PDF analytical reports. Two viable toolchains: Jinja2 + WeasyPrint (standard in data work) or reuse `/dev-documents` (Handlebars + Root render — consistent with the rest of this repo).
- **`deliver-sftp.sh`** — ad-hoc SFTP push. Until built: `/dev-data-export` for recurring, manual `lftp` with explicit user confirmation for ad-hoc.
- **`deliver-http.sh`** — ad-hoc HTTPS POST to a Node/Python app. Safety model decided in rule #22: per-call user confirmation. Optional `OUTPUT_ALLOWED_HOSTS` allowlist layered on top.

---

## 2. View hygiene & usage analytics

Today the framework happily accumulates `fact_*`, `dim_*`, and `ops_*_view` definitions in Athena. After a few sprints, this grows into a graveyard of stale views nobody reads.

- **`tools/view-usage.sh`** — pull workgroup query history via `aws athena list-query-executions` + `get-query-execution`, count references to each `_view` in the last N days, write to `.agents/stats/view-usage.json`. Output: a leaderboard of views by usage.
- **In-tool counter as fallback** — if Athena query history isn't available (permissions), each `athena-query.sh` invocation scans the SQL for `_view` references and increments a local counter. Less accurate (only this agent's usage, not the team's) but always available.
- **`skills/view-prune.md`** — reads the usage stats, lists views with zero reads in the last 30 days, proposes deletions under `.agents/proposals/<ts>/prune-views.md`. Never auto-deletes — proposals only (rules.md #13).
- **View documentation freshness** — each `fact_*_view` / `ops_*_view` has a sibling under `.agents/bi/` or `.agents/ops/`. A retro pass flags views whose sibling doc hasn't been touched in N months. Drift between docs and SQL is a real risk.
- **Regression golden hygiene** — a retro pass that proposes deletion of goldens whose underlying view was deleted, or whose `captured_at` is older than the team's lookback window.

---

## 3. Cost & performance baselines

- **Session scan budget.** Each session has an implicit cost: `bytes_scanned` accumulates in `.agents/sessions/<sid>.jsonl`. Retro surfaces "this session scanned 47 GB at ≈$0.24" and flags outliers. Optional hard cap: `ROOT_AGENTS_MAX_SESSION_BYTES` env var that triggers a confirmation prompt before exceeding.
- **Per-query performance baselines.** `regression-record.sh` already captures `data_scanned_bytes` and `EngineExecutionTimeInMillis`. A future `regression-check` mode could fail not just on result mismatch but on **performance degradation** — "this used to scan 200 MB and now scans 2 GB; the underlying table grew or partition pruning broke".
- **Workgroup-level guardrails.** Configure the Athena workgroup with `BytesScannedCutoffPerQuery` and `EnforceWorkGroupConfiguration` to refuse runaway queries at the platform level. A belt to the framework's suspenders.
- **Envelope goldens** — `regression-record.sh --envelope min=X max=Y` records a "result is in [min, max]" expectation rather than `==`. Useful for current-month-style queries that legitimately drift but shouldn't drift by 10×.

---

## 4. Cross-session memory & lineage

- **Promotion archive.** When `retro` promotes a learned skill to canonical, archive the original under `.agents/promoted/<ts>-<name>.md` so the team can see what discoveries became canonical and when.
- **Lineage for any output.** Given any committed artefact (`fact_*_view`, regression golden, evidence folder), an agent should be able to trace back: which session created it, which task triggered it, which input tables it depends on, which downstream consumers exist. The session log + manifests have enough information; what's missing is a `lineage.md` skill that traverses them.
- **Weekly digest.** A scheduled (or hand-run) skill that emits "what changed this week" — new views, new goldens, promoted learned skills, deleted learned skills, top-5 queried views, total scan cost. Lives in `.agents/digests/<week>.md`.
- **`tools/trust-audit.sh`** — parallel to `compliance-audit.sh`, for the data-trust doctrine in `references/data-trust.md`. Sweeps session logs for published-number events and surfaces which confidence label was applied, whether a reconciliation query agreed, whether a golden was green at publish time, and whether the manifest was written. Output: a markdown table the team can review monthly. Trigger: ≥3 retro notes of the form "we shipped a `verified` number that turned out wrong" — i.e. the discipline isn't catching enough cases and we need after-the-fact inspection.

---

## 5. Sub-agents (build only when the routing breaks)

`extension-shapes.md` already names sub-agents as a reserved shape. **Concrete trigger signals**:

- Multiple `description-miss` notes cluster around the same skill with **audience-shaped disagreement** (analyst vs ops vs compliance want different defaults for the same workflow).
- The decision tree in `AGENTS.md` has grown past one screen and trimming would lose routing fidelity.
- A workflow needs context (e.g. a domain dictionary, a regulator-specific glossary) the default agent doesn't carry.

Layout when built:

```
.agents/agents/
├── claims-analyst/
│   ├── AGENTS.md          # own decision tree + persona
│   └── skills/            # curated subset, possibly symlinks to canonical
├── compliance-officer/
│   ├── AGENTS.md
│   └── skills/
└── ...
```

The parent `AGENTS.md` becomes a thin router: identify the audience, hand off.

---

## 6. Schema & data-quality drift

`references/schema.md` drifts from reality the moment a column is added. The same is true for declared JSONB schemas the moment a product module adds a field.

- **`tools/schema-diff.sh`** — DESCRIBE each documented table, parse against the markdown reference, emit a diff.
- **`skills/schema-sync.md`** — call the diff tool, propose updates to `schema.md` via the standard `proposals/` flow.
- **JSONB drift detection** — re-run `derive-jsonb-schema` against tables tagged in `skills/learned/jsonb-schema-*.md`; if empirical sampling produces a new key absent from the declared schema, propose a re-derivation.
- **Data quality monitors** — beyond schema drift, watch values: a `fact_*_view`'s row count for "last month" shouldn't be 0 (snapshot didn't refresh) or 10× normal (duplicate join). A `dim_policyholder_view` shouldn't suddenly have 50% nulls on `email`. Envelope goldens (§4) cover most of this.

---

## 7. Onboarding

- **`skills/onboard.md`** — walks a new team member through: set env vars → `whoami` → first `run-query` → first `profile-data` → first `feature-adoption` → first regression golden. Each step ends with "you should see X; if not, check Y".

(`tools/framework-status.sh` shipped in Phase 8 — `bash .agents/tools/framework-status.sh` for the dashboard.)

---

## 8. Quality-of-life tooling

- **REPL mode.** Interactive shell wrapping `athena-query.sh` so the agent can iterate without spawning a bash subprocess per call. Tiny TUI or just a `read -p` loop.
- **Test fixtures for the framework itself.** A synthetic Athena (DuckDB pointed at a local Parquet fixture) so the framework's tools can be unit-tested without an AWS round-trip. Critical once the codebase grows past v1.
- **Pre-commit hook for view PRs.** Before merging a `fact_*_view` change, run `regression-check --all` and require all goldens pass. Goes into a `.git/hooks/pre-commit` or a GitHub Action.
- **Cost annotations in views.** When `save-view.sh` persists a view, capture the `bytes_scanned` from its first run as an annotation in the sibling `.agents/bi/<name>.md` doc. Lets the next agent see "this view scans ~500 MB per refresh" without re-running.
- **`tools/publish-check.sh`** — wraps the publish-time gate from `references/data-trust.md` into one command: runs `profile-table` on contributing tables, executes any documented reconciliation queries in the relevant sidecar, runs `regression-check --all`, confirms the manifest was written, and emits a ready-to-paste confidence label. Don't build until the discipline has landed as policy and observe notes show the steps are being skipped — premature mechanisation would freeze a doctrine that's still settling.

---

## 9. dbt for the mart layer (coexist, don't replace)

This framework is genuinely well-suited for **exploration and analysis** — ad-hoc queries, profiling, compliance pulls, one-off BI views, regression-gated artefacts. It is **not** the right tool for owning a maintained data mart. Once the `fact_*` / `dim_*` views stabilise and downstream consumers start depending on them as a contract, the mart layer wants the things dbt gives you for free: dependency graphs, incremental materialisation, model tests, docs site, lineage, versioned migrations.

The two tools coexist cleanly because they aim at different jobs:

```
.agents/  → explore, query, comply, profile, prototype views
dbt/      → build, test, and maintain the mart the team consumes
```

Both point at the same Athena workgroup, the same `prod_lake` source tables. The handoff is straightforward: when a `fact_*_view` or `dim_*_view` in this framework starts being referenced by multiple downstream consumers (BI dashboards, scheduled exports, other agents), that's the signal to **promote it into dbt** as a proper model with tests and docs.

What this session already produced is the **specification** for that dbt project. The views under `.agents/bi/` (`fact_payments_view.md`, `dim_payment_method_view.md`, `dim_product_view.md`) plus the regression goldens are essentially the contract a dbt staging/mart model would need to satisfy. Not wasted work — it's a prototype with explicit acceptance criteria.

**Trigger signals to actually build the dbt project (`framework-status.sh` flags these):**

- ≥3 **per-client** `rp_fact_<entity>_<client>_view` definitions stable and referenced by ≥2 downstream consumers each. (Phase 8 introduced the per-client layer; that's the natural precursor to dbt — when client-bespoke logic stabilises across multiple clients, dbt's tests + lineage + scheduled refresh become worth the setup cost.)
- ≥3 universal `rp_fact_*_view` / `rp_dim_*_view` definitions stable and referenced by ≥2 downstream consumers each.
- A stakeholder asks for "model documentation" or "lineage" in a way that the `.agents/bi/` markdown can't satisfy.
- The team wants scheduled refreshes with dependency-aware ordering, not ad-hoc `CREATE OR REPLACE VIEW`.
- A second team (analytics, finance) needs read-only access to the mart on a contract — they shouldn't have to learn this framework to consume it.

**`/dev-dbt` skill (the natural next addition).** Scaffolds a `dbt-athena` project alongside `.agents/`, reusing the same Athena workgroup and S3 staging bucket. Generates `sources.yml` from `references/schema.md`, and emits `staging/stg_*.sql` model files from existing `rp_fact_*_view` / `rp_dim_*_view` definitions in `.agents/bi/` (universal) and `.agents/bi/clients/<slug>/*` (per-client → dbt model with `client` as a variable). The regression goldens become dbt `tests:` blocks (row counts, sum checks, distinct-value counts). The sibling `.md` docs become `description:` fields in `schema.yml`. Effectively a one-shot migration from prototype to production model.

**Anti-pattern to avoid:** do not try to make `.agents/` *into* dbt. The two have different contracts. `.agents/` is agent-driven and proposes changes; dbt is code-reviewed and merged like any other repo. Bolting dbt's compile/run/test machinery into bash tools here would reinvent the wheel badly. Stand up a real dbt project when the signal arrives.

---

## 10. Anti-list — things explicitly **not** worth building

Worth recording so we don't reinvent these every six months.

- **An MCP server for the data adapter.** The whole framework was built explicitly without MCP. The agent's tools are bash + AWS CLI + curl. Don't add an MCP layer — it solves a problem we don't have.
- **A web UI for the framework.** Pure CLI is the contract. If team members want a UI, the answer is the BI tool path (`bi-view` → `/dev-data-adapter` → Power BI / Tableau / Looker).
- **A "smart router" that auto-picks skills.** The decision tree in `AGENTS.md` is the router. Frontmatter `description` strings are the routing fact. Don't replace them with a learned classifier.

---

## Process note

When a future session decides to build one of these:

1. Re-enter plan mode and write the plan against the existing framework.
2. Build, test, and ship the addition the same way Phases 1–4 did.
3. **Delete the corresponding section from this file** in the same PR.
4. If the build surfaced a smaller follow-up that doesn't justify its own iteration, add it back to this file as a new entry.

The carrying cost of an idea on this list is near zero. The carrying cost of an idea half-built in the framework is high. Bias toward staying on the list until a real signal pulls an item off.
