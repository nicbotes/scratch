# Rules

Hard rules. Read once per session. If a rule trips you up because it wasn't explicit enough, call `observe` so the next agent doesn't pay the same tax.

1. **Always filter by environment.** Every query against an org table includes `WHERE environment = '$ROOT_ENV'` (default `production`). Sandbox and prod live in the same tables.

2. **Money is cents.** `monthly_premium`, `sum_assured`, `amount`, anything currency-shaped — integer cents. Divide by 100 **only at display time**, never inside `SUM`/`AVG`/`GROUP BY`.

3. **Date handling is type-directional.** Two patterns, depending on the column type:
   - **Varchar columns** (most `*_at` historical fields, all `policies.start_date`/`end_date`) store ISO 8601 strings. Wrap with `from_iso8601_timestamp(col)` before arithmetic, comparison, or `AT TIME ZONE`. Do not `CAST` strings to dates.
   - **`timestamp(3)` columns** (most `created_at`, `updated_at`) are already typed — comparing them against a bare string literal fails with `TYPE_MISMATCH`. Either compare against another timestamp (`from_iso8601_timestamp('2025-01-01')`) or coerce to string with `date_format(col, '%Y-%m-%d') >= '2025-01-01'`. The `date_format` form is the standard pattern for string-comparable date filtering in regression goldens.

   Check the column type in `references/schema.md` or via `glue-describe.sh <table>` before writing the predicate.

4. **Snapshots are daily.** Data refreshes shortly after midnight in the org's region. State this in every report. Never claim "real-time".

5. **JSON columns need `JSON_EXTRACT_SCALAR`.** Applies to `module`, `charges`, `policy_events.data`, and anything else stored as JSON VARCHAR. See `references/athena-sql.md`.

6. **Views end in `_view` and encode intent by prefix.**
   - `fact_*_view`, `dim_*_view` — Kimball/star analytical layer (see `bi-view`).
   - `ops_*_view` — action-oriented operational caches (see `ops-dataset`).
   - `scratch_<ns>_*_view` — exploratory, namespace required. The `<ns>` slug identifies the originator (analyst, branch, or example slug) so a teammate scanning `SHOW VIEWS` can tell "Nic's poke at churn" from production. Created via `save-view.sh --scratch [<ns>]`; cleaned up via `drop-view.sh`. Promote to `fact_/dim_/ops_` via `bi-view` or `ops-dataset` once intent and shape are stable.
   - Don't mix. A view is for re-aggregation **or** for direct human action **or** still in exploration — never two at once.

7. **Never embed an `AWS_*` value in a query, filename, log line, or commit.** The session trace, manifests, and feedback notes never include credentials.

8. **Default `LIMIT 1000` on exploratory queries.** Remove only for explicit aggregates or compliance exports.

9. **Premortem before wide queries.** Run `athena-query.sh --dry-run` (or call the `premortem` skill) for any query without a date filter or with three or more joins.

10. **Profile before you analyse.** Run `profile-table.sh` on every table that contributes to a published number. The profile output is required context, not a nice-to-have.

11. **Named-consumer output is evidence.** Always route through `export-results.sh` so every CSV has a sibling `manifest.json` (org id, env, sql, query id, sha256, row count). "Named consumer" means: a report, a shared document, a human who will act on the number, a downstream pipeline, or anything the agent will reference back to itself in a later turn. Default posture: **if you ran more than one query to produce an answer, write the evidence before presenting findings.** Stdout-only is fine for one-shot lookups; for assembled analyses it loses the audit trail and forces a re-run when the result needs to be shared. Compliance evidence is the strict case — never exempt. For analytical reports the rule is "do this by default; exemption requires a one-line reason in the reply".

12. **Observe friction in real time.** If a skill description didn't match, a reference was re-read, a tool flag was missing, or a gotcha tripped you — call `feedback-note.sh` **before** moving on. One note per event.

13. **Retro never edits live files.** `retro` writes patches under `.agents/proposals/`. Live skills/tools/rules change only through normal review.

14. **Check your work against goldens.** Before publishing any analytical number — KPI, board figure, regulator-facing total — run `regression-check.sh --all` (cheap) or at minimum the goldens covering the same domain. A red golden is stop-the-line, not retry-the-query.

15. **Goldens are time-bounded, aggregate-shaped, and sensitive-free.** Every regression file pins a closed historical window (`>=` and `<` both present, or `BETWEEN`). Never `NOW()`, `CURRENT_DATE`, or "active today" — those drift legitimately and produce noise. Golden SQL produces aggregates (counts, sums, percentiles, group-bys) so the committed `result` field is innocuous. **Row-level captures belong in `export-results.sh` evidence (`.agents/evidence/` or `.agents/sensitive/`, both gitignored), never in regressions.** `regression-record.sh` refuses any SQL touching PII, restricted, or unresolved JSON-sensitive columns (rule #26).

    Standard pattern for an all-history golden: `WHERE date_format(created_at, '%Y-%m-%d') >= '2010-01-01' AND date_format(created_at, '%Y-%m-%d') < '<next-year>'`. The validator in `regression-record.sh` rejects single-bound windows; this is intentional, not a bug.

16. **Compliance is per-org-per-subject.** `multi-org-query` is for analytics that aggregates across orgs. Never fan compliance queries across orgs in one go — the evidence package must be unambiguous about which org the data came from.

17. **JSONB discoveries are persisted.** When you derive the key shape of a JSONB column (`policies.module`, `policies.charges`, `claims.module`, `policy_events.data`, `product_module_definitions.settings/.billing`), call `learn-skill.sh` immediately so the next query routes to `skills/learned/jsonb-schema-<...>.md` without re-sampling. The skill that does the derivation is `derive-jsonb-schema`.

18. **Learned skills are advisory.** When you route through a skill in `skills/learned/`, mention it in your reply ("I'm using a learned, uncurated skill — review the inventory before publishing"). Promotion from `learned/` to canonical `skills/` happens through `retro`, never silently.

19. **Shape your discoveries deliberately.** Before saving a useful pattern, decide if it's a recipe, skill, learned skill, reference, analytical view, operational view, regression golden, or sub-agent candidate. The decision matrix is `references/extension-shapes.md`. Picking the wrong shape rots the framework.

20. **Output format follows the consumer, not the producer's preference.** Default to CSV for humans; JSON/JSONL for programmatic consumers; Parquet for data pipelines. The matrix is `references/output-formats.md` — when in doubt, route through it explicitly rather than picking by reflex.

21. **Parquet via Athena `UNLOAD` beats CSV-then-convert.** For >10k rows or for typed downstream consumers, use `athena-unload.sh --format parquet`. CSV roundtrips lose types (everything becomes string); Parquet preserves them and is cheaper to re-read.

22. **PII never leaves via unvetted destinations.** Until SFTP/HTTP push tools land, ad-hoc delivery is local-file or S3-within-the-same-org-prefix only. Compliance evidence stays inside `.agents/evidence/`. When push tools are added later, the safety model is **per-call user confirmation** for any destination — no implicit allowlist.

23. **Never read large result sets into context.** Tools that print to stdout cap output at `ROOT_AGENTS_MAX_ROWS` rows (default `1000`) and `ROOT_AGENTS_MAX_BYTES` bytes (default `200000`). When the cap fires, the tool prints the head + a loud truncation footer naming the escape valves: `--to-file <path>`, `--head N`, `--no-row-cap` (`athena-query.sh`, `duckdb-query.sh`); `--max-bytes N`, `--no-truncate` (`root-api.sh`). For anything beyond a few thousand rows, route through `export-results.sh` (CSV + manifest) or `athena-unload.sh` (Parquet to S3) instead. **Never disable the cap silently.** If you use `--no-row-cap` or `--no-truncate`, say in your reply why the full output had to land in context — usually it shouldn't.

24. **Aggregate before reading.** If your analysis produces a summary (count, group-by, percentile, top-N, anomaly, distribution), do the aggregation **locally on a file** with `duckdb-query.sh` — never pull the raw rows into context. The flow is: `athena-query.sh --to-file` or `athena-unload.sh` → `duckdb-query.sh` on the file → small summary into context. See `skills/pre-aggregate.md`. Exceptions: compliance evidence (every row must be visible — use `compliance-query`) and ops queues (every row is an action item — use `ops-dataset`). #23 stops the bleeding when an agent reaches for `SELECT *`; #24 names the right move instead.

25. **Committed identifiers are hashed.** Regression goldens are committed to git (so the team shares them) and stored under `.agents/regressions/<org_id_hash>/<name>.json`. The `org_id` is replaced with a 16-hex `org_id_hash` (deterministic SHA-256 prefix via `hash_id` in `tools/_lib.sh`); `query_execution_id` is omitted entirely. Raw identifiers stay in the local session log only (`.agents/sessions/*.jsonl`, gitignored). Per-org subfolders mean multiple orgs' goldens coexist without collision, and `regression-check --all` only iterates the current org's folder. `whoami.sh` prints `Org hash:` so you can map subfolders to orgs in your own head.

26. **PII never reaches stdout.** Tools that touch sensitive columns (`pii`, `restricted`, `json_sensitive` per `references/pii-columns.json`) default-route to file. The override is `--pii-required --reason "<text>"`; the reason is logged in the session trace. In `strict` mode (default), `--pii-required` is required even when writing to a file. In `standard` mode, `--to-file` alone is acceptable for sensitive output. In `off` mode, every tool call emits a stderr warning — dev only. The firewall lives in `tools/_lib.sh::scan_sql_for_sensitivity`; the standalone `pii-scan.sh` lets you inspect a query before running. See `skills/pii-safe-analysis.md`.

27. **JSON columns are sensitive-unknown by default.** `JSON_EXTRACT[_SCALAR]` against a `json_sensitive` column (e.g. `policies.module`, `applications.app_data`, `policies.beneficiaries`) requires either (a) the path to be in the `safe_keys:` list of a learned skill produced by `derive-jsonb-schema`, or (b) explicit `--pii-required --reason`. This makes `derive-jsonb-schema` the gateway for JSON column work and aligns with rule #17 (JSONB discoveries are persisted). The derivation skill tags each enumerated key as `pii` / `restricted` / `safe`.

28. **PII never reaches the agent's reply.** The agent's chat reply to the user must not contain values from PII or restricted columns. Reference rows with pseudonyms ("the policyholder", `policy_id` prefixes, hashes from `pseudonymize.sh`) or generic identifiers. If a customer-facing copy needs a real name, generate via the application layer, not via the agent's reply. This rule extends rule #26 — #26 stops PII entering context; #28 stops anything that *did* enter context from leaking back out to the user's chat (and downstream chat-history retention).
