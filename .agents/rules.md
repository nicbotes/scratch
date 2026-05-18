# Rules

Hard rules. Read once per session. If a rule trips you up because it wasn't explicit enough, call `observe` so the next agent doesn't pay the same tax.

1. **Always filter by environment.** Every query against an org table includes `WHERE environment = '$ROOT_ENV'` (default `production`). Sandbox and prod live in the same tables.

2. **Money is cents.** `monthly_premium`, `sum_assured`, `amount`, anything currency-shaped — integer cents. Divide by 100 **only at display time**, never inside `SUM`/`AVG`/`GROUP BY`.

3. **Dates are ISO 8601 strings.** Wrap with `from_iso8601_timestamp(col)` before any arithmetic, comparison, or `AT TIME ZONE`. Do not `CAST` strings to dates.

4. **Snapshots are daily.** Data refreshes shortly after midnight in the org's region. State this in every report. Never claim "real-time".

5. **JSON columns need `JSON_EXTRACT_SCALAR`.** Applies to `module`, `charges`, `policy_events.data`, and anything else stored as JSON VARCHAR. See `references/athena-sql.md`.

6. **Views end in `_view` and encode intent by prefix.**
   - `fact_*_view`, `dim_*_view` — Kimball/star analytical layer (see `bi-view`).
   - `ops_*_view` — action-oriented operational caches (see `ops-dataset`).
   - Don't mix. A view is for re-aggregation **or** for direct human action — never both.

7. **Never embed an `AWS_*` value in a query, filename, log line, or commit.** The session trace, manifests, and feedback notes never include credentials.

8. **Default `LIMIT 1000` on exploratory queries.** Remove only for explicit aggregates or compliance exports.

9. **Premortem before wide queries.** Run `athena-query.sh --dry-run` (or call the `premortem` skill) for any query without a date filter or with three or more joins.

10. **Profile before you analyse.** Run `profile-table.sh` on every table that contributes to a published number. The profile output is required context, not a nice-to-have.

11. **Compliance output is evidence.** Always route through `export-results.sh` so every CSV has a sibling `manifest.json` (org id, env, sql, query id, sha256, row count).

12. **Observe friction in real time.** If a skill description didn't match, a reference was re-read, a tool flag was missing, or a gotcha tripped you — call `feedback-note.sh` **before** moving on. One note per event.

13. **Retro never edits live files.** `retro` writes patches under `.agents/proposals/`. Live skills/tools/rules change only through normal review.

14. **Check your work against goldens.** Before publishing any analytical number — KPI, board figure, regulator-facing total — run `regression-check.sh --all` (cheap) or at minimum the goldens covering the same domain. A red golden is stop-the-line, not retry-the-query.

15. **Goldens are time-bounded.** Every regression file pins a closed historical window (`>=` and `<` both present, or `BETWEEN`). Never `NOW()`, `CURRENT_DATE`, or "active today" — those drift legitimately and produce noise.

16. **Compliance is per-org-per-subject.** `multi-org-query` is for analytics that aggregates across orgs. Never fan compliance queries across orgs in one go — the evidence package must be unambiguous about which org the data came from.

17. **JSONB discoveries are persisted.** When you derive the key shape of a JSONB column (`policies.module`, `policies.charges`, `claims.module`, `policy_events.data`, `product_module_definitions.settings/.billing`), call `learn-skill.sh` immediately so the next query routes to `skills/learned/jsonb-schema-<...>.md` without re-sampling. The skill that does the derivation is `derive-jsonb-schema`.

18. **Learned skills are advisory.** When you route through a skill in `skills/learned/`, mention it in your reply ("I'm using a learned, uncurated skill — review the inventory before publishing"). Promotion from `learned/` to canonical `skills/` happens through `retro`, never silently.

19. **Shape your discoveries deliberately.** Before saving a useful pattern, decide if it's a recipe, skill, learned skill, reference, analytical view, operational view, regression golden, or sub-agent candidate. The decision matrix is `references/extension-shapes.md`. Picking the wrong shape rots the framework.
