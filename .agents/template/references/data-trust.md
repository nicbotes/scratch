# Reference: Data trust

For analysts, BI authors, and anyone publishing a number a human will act on. This page describes what the framework guarantees about the **correctness** of numbers it produces — distinct from `pii-safety.md`, which guards their handling. The two doctrines are orthogonal and stack: a `verified` number can also be `pii-redacted`.

## What the framework guarantees

Eight distinct failure modes can make a number wrong. The framework names each one (F1–F8) and the existing rule, skill, or convention that mitigates it. Mitigation is mostly discipline (a checklist a publisher walks) plus a small amount of runtime enforcement (regression goldens, profile gating, manifest evidence, partial-fetch refusal).

### F1 — Wrong scope or filter

Forgotten `WHERE merged_at IS NOT NULL` on a PR-cycle-time query. A status filter set to the wrong value. Soft-deleted rows included.

**Mitigated by:** rule #4 (view naming encodes intent), sidecar caveats, and the `premortem` skill (forces an explicit scope/filter check before any wide query).

### F2 — Stale snapshot

Every analysis runs against whatever was last fetched. A number quoted at 09:00 against a snapshot that was last refreshed three days ago is wrong even if every other guard passed.

**Mitigated by:** rule #2 (data is a snapshot; state freshness in every report), `profile-data` step 2 (check `max(updated_at)` / `max(created_at)`), and the `stale` confidence label when the max is older than the team's agreed cadence (no default; set per source in `references/sources/<name>.md`).

### F3 — Unit mix-ups

Currency in cents reported as the unit currency. Durations in seconds vs hours vs days. Byte sizes. Counts vs rates.

**Mitigated by:** `bi-view` step 6 (every measure named and typed — `_cents`, `_hours`, `_bytes` suffixes are convention), `premortem` failure-mode check, sidecar Facts tables documenting units explicitly.

### F4 — Date / timezone errors

JSON-landed timestamps come in as `VARCHAR`. Casting silently truncates. DuckDB's `TIMESTAMP` is timezone-naive; mixing landed strings with local-time computations needs `AT TIME ZONE 'UTC'` to be explicit.

**Mitigated by:** rule #1 (date handling is type-directional), `references/duckdb-sql.md` (cookbook of date patterns), and `duckdb-describe.sh` to check column types before writing the predicate.

### F5 — Drift over time

The view's logic changes silently; the upstream API grows a new field; a backfill rewrites historical rows. The number you trusted last quarter no longer matches.

**Mitigated by:** `regression-test` skill + rules #12 (check goldens before publishing) and #13 (goldens are time-bounded, aggregate-shaped, sensitive-free). Goldens pin a closed historical window and live under `regressions/<api_base_hash>/`. A red golden is stop-the-line, not retry-the-query.

### F6 — Logic / wrong-thing-counted

An off-by-one cohort definition. A many-to-many join that double-counts. A null-handling bug that drops 5% of rows. The SQL runs, the golden passes (because the bug was there when the golden was pinned), the freshness is current — and the number is still wrong, because no independent path checked the answer.

**Mitigated by: reconciliation.** A reconciliation query re-derives the same measure from a different table, a different join path, or a different aggregation. If two independent derivations agree, the logic is probably right; if they disagree, one of them is wrong and the gap is investigable.

A regression golden guards drift *over time*; a reconciliation query guards drift *across paths*. Both are defaults for any view a human acts on. Reconciliation SQL must be aggregate-shaped and PII-clean (rules #13, #23) so it's safe to commit inline in the view sidecar.

Tolerance language is allowed when paths legitimately differ (e.g. lag between event log and fact view) — state the expected tolerance and why.

### F7 — Definition mismatch

The analyst means "active user" as `last_seen_at >= 30d ago`; the dashboard means "currently has a paid plan"; the BI view means "ever made an API call". All three are reasonable. Two disagree with the third by 15%.

**Mitigated by:** BI/ops sidecars are the canonical glossary — each view's Grain + Facts table defines its measures. The chat-time confidence label points at the producing view (`golden: bi_active_users_count`) so a consumer can trace the definition back.

### F8 — Incomplete fetch (new at API+DuckDB scale)

`fetch-api.sh` paginated and stopped early — rate-limit hit, `--max-pages` cap, network error mid-stream, silent server-side cursor reset. The landed `raw_<entity>` table looks normal — every row is well-formed — but a slice is missing. The number you computed against it is **structurally wrong**, not noisy.

**Mitigated by:**
- `fetch-api.sh` writes a `manifest.json` with `complete=true|false`, `pages`, `records`, `expected`.
- `land-to-duckdb.sh` refuses to load when `complete=false` without `--allow-partial`, and stamps loaded tables with `partial=true` in the DuckDB table comment.
- `profile-table.sh` reports the partial flag prominently.
- `regression-record.sh` refuses to record goldens against tables flagged partial.
- The `partial` confidence label joins `verified|single-source|stale|sandbox` for chat-time disclosure.

## The publish-time gate

Before sharing any number a human will act on, walk this checklist. The checklist maps existing rules onto a single sequence; it does not add new ones.

1. **Profile clean.** `profile-table.sh` on every contributing table; row counts and `max(*)` match expectation; **no partial flag**. (Rules #8, #15.)
2. **Reconciled.** At least one independent SQL path agrees with the headline number. For BI sidecar measures, the documented reconciliation query. For ad-hoc work, a complementary query — or accept the `single-source` label.
3. **Golden green.** `regression-check.sh --all` (or at minimum the goldens covering the same domain). (Rule #12.)
4. **Evidence written.** Multi-query analyses route through `export-results.sh` so a `manifest.json` exists alongside the CSV. (Rule #9.)
5. **Sensitive output handled.** If the query touches `pii` / `restricted` / `json_sensitive` columns, route per `pii-safe-analysis`.
6. **Freshness stated.** Using the confidence-label format below.

If you cannot tick every box, label the number `single-source`, `stale`, or `partial` explicitly — calibration depends on the consumer knowing which guards ran.

## Confidence labels

A small enum the publisher prefixes onto every number reported in chat:

| Label | Meaning |
|---|---|
| `verified` | Profile clean, reconciliation matches, golden green, manifest written. Every guard ran and agreed. |
| `single-source` | Profile + golden only. No independent cross-check ran. Trust at your own calibration. |
| `stale` | Last `max(*)` older than the source's agreed cadence. The number reflects the last good snapshot; current state may differ. |
| `partial` | The contributing table was loaded from an incomplete fetch (F8). The number is structurally incomplete, not just noisy. Re-fetch before publishing. |
| `sandbox` | Environment is a test source. Don't act on as customer figure. |

Labels stack with `pii-redacted` (from `pii-safety.md`) when sensitive columns were involved but pseudonymised. Example: `[verified · pii-redacted] 1,432 users | …`.

**Report-time format:**

```
[verified] 1,432 merged PRs in Q1 2025 | as-of 2026-05-21 04:12 UTC | golden: pr_cycle_time_2025_q1 | manifest: evidence/2026-05-21/pr_count/manifest.json
```

For `single-source` numbers, omit the golden/manifest line if neither exists; the label by itself is the warning:

```
[single-source] 142 issues opened yesterday | as-of 2026-05-21 04:12 UTC
```

## What to do (operational habits)

There is no env var equivalent to `ROOT_AGENTS_COMPLIANCE_MODE` for data trust — accuracy isn't a gradient, and the framework's gates are disciplines or already-runtime-enforced rules.

- **Run `framework-status.sh` at session start** when something feels off. Surfaces regression goldens, view counts, telemetry/feedback health.
- **Run `regression-check.sh --all` before publishing.** Cheap; covers the current API's goldens.
- **Use the confidence-label format above** on every reported number. If you can't reach `verified`, say which label applies and why.
- **Re-fetch before publishing if a table is stamped partial.** Don't pass `--allow-partial` to get past the check unless you've documented why a structurally-incomplete number is the right thing to publish.

## Audit trail

After-the-fact inspection of trust posture:

| Surface | What it tells you |
|---|---|
| `regression-check.sh --all` | Current pass/fail state of every pinned golden for this API. |
| `framework-status.sh` | One-screen view: golden count, view counts, partial-table count, telemetry/feedback activity. |
| `evidence/<date>/<name>/manifest.json` | What SQL produced this exact number, with sha256 of the result. (`sensitive/<date>/...` for the PII-bearing twin.) |
| `regressions/<api_base_hash>/<name>.json` | Historical baseline: SQL + result captured when the golden was pinned, with `--re-record` git history. |
| Sidecar markdown under `bi/`, `ops/` | Per-view canonical definition, caveats, reconciliation queries. |
| `data/raw/<source>/<entity>/*.manifest.json` | Fetch-time evidence: pages, records, complete flag, started/finished. |

## Posture and trade-offs

The framework prioritises **safe-by-default at the publish boundary, frictionless in ad-hoc exploration**. The trust gate is non-trivial — profile + reconcile + golden + evidence + freshness is five steps — and that's deliberate for any number a human will act on. The cost is the publisher must stop and walk the gate; the benefit is the consumer downstream has a labelled number with traceable evidence.

Ad-hoc exploration is exempt by design. A one-shot question ("how many issues were opened yesterday?") doesn't need reconciliation or a regression golden — `[single-source]` is the right label and the right amount of friction. The doctrine guards the boundary where exploration becomes publication, not exploration itself.

If a team finds itself routinely shipping `single-source` numbers that a stakeholder later challenges, that's the signal to invest reconciliation queries in the responsible BI sidecars — not to weaken the labels. The `observe` + `retro` loop surfaces this pattern naturally.

## Cross-references

| Resource | Purpose |
|---|---|
| `rules.md` #1–#4 | Codified date/snapshot/JSON/view-naming rules. |
| `rules.md` #8, #9 | Profile-before-analyse; named-consumer manifest evidence. |
| `rules.md` #12, #13 | Regression check before publishing; golden shape. |
| `rules.md` #15 | Partial-fetch refusal (F8). |
| `rules.md` #23–#25 | PII handling — orthogonal doctrine, labels stack. |
| `skills/premortem.md` | Pre-flight gating skill — failure modes. |
| `skills/profile-data.md` | Pre-flight gating skill — row count, freshness, nulls. |
| `skills/regression-test.md` | Pin / verify deterministic goldens. |
| `skills/bi-view.md` | Building the analytical layer; the reconciliation requirement lives here. |
| `tools/regression-check.sh`, `regression-record.sh` | Goldens. |
| `tools/profile-table.sh` | Pre-flight profile (surfaces partial flag). |
| `tools/export-results.sh` | Evidence + manifest. |
| `tools/framework-status.sh` | Maturity dashboard. |
| `references/pii-safety.md` | Sibling doctrine — handling, not correctness. Labels stack. |
