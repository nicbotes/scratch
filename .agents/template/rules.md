# Rules

Hard rules. Read once per session. If a rule trips you up because it wasn't explicit enough, call `observe` so the next agent doesn't pay the same tax.

1. **Date handling is type-directional.** JSON-landed timestamps usually arrive as `VARCHAR`. Wrap with `strptime(col, '%Y-%m-%dT%H:%M:%SZ')` or `CAST(col AS TIMESTAMP)` before arithmetic, comparison, or `AT TIME ZONE`. Once landed as `TIMESTAMP`, compare against another typed value (`TIMESTAMP '2025-01-01'`, another column), not a bare string. See `references/duckdb-sql.md`.

2. **Data is a snapshot.** Every analysis runs against whatever was last fetched via `fetch-api.sh` + `land-to-duckdb.sh`. State the as-of timestamp (from `profile-table.sh`) in every report. Never claim "real-time" — re-fetch first or call out the staleness.

3. **JSON columns use DuckDB-native access.** Landed JSON shows up as `STRUCT`, `JSON`, or `VARCHAR` depending on shape. Use:
   - dot-notation (`col.field`) for known nested keys on `STRUCT` columns
   - `json_extract_string(col, '$.path')` for dynamic paths on `JSON`/`VARCHAR` columns
   - `unnest(col)` for `LIST` columns

   See `references/duckdb-sql.md`.

4. **Views end in `_view`, encoded by intent prefix.**
   - `bi_<entity>_view` — analytical layer. Kimball discipline lives inside (`bi_fact_*`, `bi_dim_*` once a star schema emerges). See `bi-view`.
   - `ops_<action>_view` — action-oriented operational caches. See `ops-dataset`.
   - `scratch_<ns>_<body>_view` — exploratory, namespace required. The `<ns>` slug identifies the originator (analyst, branch, or example slug). Created via `save-view.sh --scratch [<ns>]`; cleaned up via `drop-view.sh`. Promote to `bi_*` / `ops_*` once shape is stable.
   - Don't mix. A view is for re-aggregation **or** for direct human action **or** still in exploration — never two at once. `save-view.sh` enforces the prefix.

5. **Never embed `API_TOKEN`, basic-auth credentials, or any secret in a query, filename, log line, or commit.** Session traces, manifests, and feedback notes never include credentials. If a tool errors with a request that contains a token, scrub the token before pasting the error anywhere.

6. **Default `LIMIT 1000` on exploratory queries.** Remove only for explicit aggregates or compliance exports.

7. **Premortem before wide queries.** Call the `premortem` skill for any DuckDB query without a date filter, with three or more joins, or with `SELECT *` against a `raw_*` table that lands ≥10k rows.

8. **Profile before you analyse.** Run `profile-table.sh` on every table that contributes to a published number. The profile output is required context, not a nice-to-have. Look for the **partial flag** (see rule #15).

9. **Named-consumer output is evidence.** Always route through `export-results.sh` so every CSV has a sibling `manifest.json` (api_base_hash, sql, sha256, row count). "Named consumer" means: a report, a shared document, a human who will act on the number, a downstream pipeline. Default posture: **if you ran more than one query to produce an answer, write the evidence before presenting findings.** Stdout-only is fine for one-shot lookups; for assembled analyses it loses the audit trail. Compliance evidence is the strict case — never exempt.

10. **Observe friction in real time.** Call `feedback-note.sh` **before** moving on whenever any of these happens — one note per event:
    - a tool errored, refused, or behaved unexpectedly
    - you retried or restructured a query because the first version was wrong
    - an assumption about schema, JSON key naming, or data shape turned out incorrect
    - a skill description didn't fire when it should have, or fired when it shouldn't
    - a reference was opened more than once this session
    - a discovery is genuinely reusable across sessions (`--kind success-pattern`)

    Do not batch. Do not editorialise. Do not write the fix — that is `retro`'s job at end of session.

11. **Retro never edits live files.** `retro` writes patches under `.agents/proposals/`. Live skills/tools/rules change only through normal review.

12. **Check your work against goldens.** Before publishing any analytical number — KPI, dashboard figure, regulator-facing total — run `regression-check.sh --all` (cheap) or at minimum the goldens covering the same domain. A red golden is stop-the-line, not retry-the-query.

13. **Goldens are time-bounded, aggregate-shaped, sensitive-free, and complete.** Every regression file pins a closed historical window (`>=` and `<` both present, or `BETWEEN`). Never `NOW()`, `CURRENT_DATE`, or "active today" — those drift legitimately and produce noise. Golden SQL produces aggregates (counts, sums, percentiles, group-bys) so the committed `result` field is innocuous. Row-level captures belong in `export-results.sh` evidence (`.agents/evidence/` or `.agents/sensitive/`, both gitignored), never in regressions. `regression-record.sh` refuses any SQL touching PII / restricted / json_sensitive columns AND refuses to record against tables stamped `partial=true` (see rule #15).

14. **Learned skills are advisory.** When you route through a skill in `skills/learned/`, mention it in your reply ("I'm using a learned, uncurated skill — review the inventory before publishing"). Promotion from `learned/` to canonical `skills/` happens through `retro`, never silently.

15. **Fetches that don't complete are partial.** `fetch-api.sh` writes a `manifest.json` next to every landed JSONL with `complete=true|false`. `land-to-duckdb.sh` refuses partial loads unless `--allow-partial` is passed (and stamps the table with a `partial=true` comment). `profile-table.sh` surfaces the partial flag. `regression-record.sh` refuses goldens against partial tables. The `partial` confidence label is the public-facing version. Failure mode F8 in `references/data-trust.md`.

16. **Shape your discoveries deliberately.** Before saving a useful pattern, decide if it's a recipe, skill, learned skill, reference, analytical view, operational view, regression golden, or sub-agent candidate. The decision matrix is `references/extension-shapes.md`. Picking the wrong shape rots the framework.

17. **Output format follows the consumer, not the producer's preference.** Default to CSV for humans; JSON/JSONL for programmatic consumers; Parquet for data pipelines. The matrix is `references/output-formats.md` — when in doubt, route through it explicitly rather than picking by reflex.

18. **Parquet via DuckDB `COPY ... (FORMAT PARQUET)` beats CSV-then-convert.** For >10k rows or typed downstream consumers, DuckDB's `COPY` preserves types; CSV roundtrips lose them (everything becomes string). See `references/output-formats.md`.

19. **PII never leaves via unvetted destinations.** Until ad-hoc push tools (SFTP/HTTP/S3) are deliberately added, sensitive output lands on local disk only — under `.agents/sensitive/` (gitignored). When push tools are added later, the safety model is **per-call user confirmation** for any destination — no implicit allowlist.

20. **Never read large result sets into context.** Tools that print to stdout cap output at `ROOT_AGENTS_MAX_ROWS` rows (default `1000`) and `ROOT_AGENTS_MAX_BYTES` bytes (default `200000`). When the cap fires, the tool prints the head + a loud truncation footer naming the escape valves: `--to-file <path>`, `--head N`, `--no-row-cap`. For anything beyond a few thousand rows, route through `export-results.sh` (CSV + manifest) or `duckdb-query.sh --to-file <path> --format parquet` instead. **Never disable the cap silently.** If you use `--no-row-cap`, say in your reply why the full output had to land in context — usually it shouldn't.

21. **Aggregate before reading.** If your analysis produces a summary (count, group-by, percentile, top-N, anomaly, distribution), do the aggregation in DuckDB — never read raw rows into context. The flow is: `fetch-api.sh` → `land-to-duckdb.sh` → `duckdb-query.sh "<aggregate sql>"` → small summary into context. See `skills/pre-aggregate.md`. Exceptions: compliance evidence (every row must be visible — use `compliance-query`) and ops queues (every row is an action item — use `ops-dataset`).

22. **Committed identifiers are hashed.** Regression goldens are committed to git under `.agents/regressions/<api_base_hash>/<name>.json`. The `api_base_hash` is a 16-hex SHA-256 prefix of `$API_BASE_URL` (via `hash_id` in `tools/_lib.sh`). Raw API base URLs and any tenant identifiers stay out of git plaintext. The hash subfolder also lets multiple data sources coexist without collision when an adopter later extends the framework to a second API.

23. **PII never reaches stdout.** Tools that touch sensitive columns (`pii`, `restricted`, `json_sensitive` per `references/pii-columns.json`) default-route to file. The override is `--pii-required --reason "<text>"`; the reason is logged in the session trace. In `strict` mode (default), `--pii-required` is required even when writing to a file. In `standard` mode, `--to-file` alone is acceptable for sensitive output. In `off` mode, every tool call emits a stderr warning — dev only. The firewall lives in `tools/_lib.sh::scan_sql_for_sensitivity` (pre-flight regex) and `check_executed_query_sensitivity_duckdb` (authoritative DuckDB `DESCRIBE`); the standalone `pii-scan.sh` lets you inspect a query before running. See `skills/pii-safe-analysis.md`.

24. **JSON/STRUCT columns are sensitive-unknown by default.** Columns flagged `json_sensitive` in `references/pii-columns.json` require either (a) the accessed key to be in a `safe_keys:` list of a learned skill, or (b) explicit `--pii-required --reason`. `json_extract_string(col, '$.path')` and dot-notation (`col.path`) access both trigger the rule. This makes JSON exploration the gateway for sensitive-key discovery — sample once, document the safe keys, every later query is firewalled.

25. **PII never reaches the agent's reply.** The agent's chat reply to the user must not contain values from PII or restricted columns. Reference rows with pseudonyms ("the policyholder", id prefixes, hashes from `pseudonymize.sh`) or generic identifiers. If a customer-facing copy needs a real name, generate via the application layer, not via the agent's reply. This rule extends #23 — #23 stops PII entering context; #25 stops anything that *did* enter context from leaking back out to the user's chat (and downstream chat-history retention).
