# Reference: Data trust

For analysts, BI authors, and anyone publishing a number a human will act on. This page describes what the framework guarantees about the **correctness** of numbers it produces — distinct from `pii-safety.md`, which guards their handling. The two doctrines are orthogonal and stack: a `verified` number can also be `pii-redacted`.

## What the framework guarantees

Seven distinct failure modes can make a number wrong. The framework names each one (F1–F7) and the existing rule, skill, or convention that mitigates it. Mitigation is mostly discipline (a checklist a publisher walks) plus a small amount of runtime enforcement (regression goldens, profile gating, manifest evidence).

### F1 — Wrong scope or filter

Sandbox rows mixed with production. `flushed = true` (soft-deleted) rows included. The wrong snapshot. The wrong environment for the org you thought you were in.

**Mitigated by:** rule #1 (always filter by environment), rule #6 (view naming encodes intent and layer), sidecar caveats (e.g. `fact_policies_view.md` documents `flushed = true` semantics), and the `premortem` skill (forces an explicit env/filter check before any wide query).

### F2 — Stale snapshot

Data refreshes shortly after midnight in the org's region. A number quoted at 09:00 against a snapshot that didn't land yet — or that landed partially — is wrong even if every other guard passed.

**Mitigated by:** rule #4 (snapshots are daily; state freshness in every report), `profile-data` step 2 (check `max(created_at)` against expectation), and the `stale` confidence label at chat time when the max is older than ~36h.

### F3 — Cents/rand or unit mix-ups

Currency in cents but reported as rand. `sum_assured` divided by 100 inside `SUM` instead of at display. Premium aggregates mixing pro-rata billed amounts with recurring `monthly_premium`.

**Mitigated by:** rule #2 (money is cents; divide only at display time), `bi-view` step 6 (every measure named and typed — `_cents` suffix is convention), `premortem` failure-mode #3, sidecar Facts tables documenting units explicitly.

### F4 — Date-type or timezone errors

`varchar` ISO strings cast to date silently truncates. `timestamp(3)` compared to a bare string literal fails with `TYPE_MISMATCH`. `from_iso8601_timestamp` returns UTC; a SAST cohort window missing `AT TIME ZONE` lands at the wrong day boundary.

**Mitigated by:** rule #3 (date handling is type-directional), `references/athena-sql.md` (cookbook of date patterns), and `glue-describe.sh` to check column types before writing the predicate.

### F5 — Drift over time

The view's logic changes silently; the upstream table grows a column; a backfill rewrites historical rows. The number you trusted last quarter no longer matches.

**Mitigated by:** `regression-test` skill + rules #14 (check goldens before publishing) and #15 (goldens are time-bounded, aggregate-shaped, sensitive-free). Goldens pin a closed historical window and live under `regressions/<org_id_hash>/` (rule #25). A red golden is stop-the-line, not retry-the-query (#14).

### F6 — Logic / wrong-thing-counted

An off-by-one cohort definition. A many-to-many join that double-counts. A null handling bug that drops 5% of rows. The SQL runs, the golden passes (because the bug was there when the golden was pinned), the freshness is current — and the number is still wrong, because no independent path checked the answer.

**Mitigated by: reconciliation.** A reconciliation query re-derives the same measure from a different source table, a different join path, or a different aggregation. If two independent derivations agree, the logic is probably right; if they disagree, one of them is wrong and the gap is investigable.

A regression golden guards drift *over time*; a reconciliation query guards drift *across paths*. Both are defaults for any view a human acts on. The pattern was established by `ops/ops_monthly_invoice_lines_view.md` (per-line-item independent SQL) and is now required of BI sidecars via `bi-view` step 11 ("Document at least one reconciliation query").

Reconciliation SQL must be aggregate-shaped and PII-clean (rules #15, #26) so it's safe to commit inline in the sidecar markdown. Tolerance language is allowed when paths legitimately differ (e.g. lag between event log and dimensional view) — state the expected tolerance and why.

### F7 — Definition mismatch

The analyst means "active policy" as "status = 'active'"; the dashboard means "in force during last month"; the BI view means "issued and not yet exited". All three are reasonable. Two of them disagree with the third by 15%.

**Mitigated by:** BI/ops sidecars are the canonical glossary — each view's Grain + Facts table defines its measures. The chat-time confidence label points at the producing view (`golden: fact_policies_active_count`) so a consumer can trace the definition back. A central `references/glossary.md` is deferred to FUTURE.md until observed ambiguity warrants it.

## The publish-time gate

Before sharing any number a human will act on, walk this checklist. The checklist maps existing rules onto a single sequence; it does not add new ones.

1. **Profile clean.** `profile-table.sh` on every contributing table; row counts and `max(created_at)` match expectation. (Rule #10.)
2. **Reconciled.** At least one independent SQL path agrees with the headline number. For BI sidecar measures, the documented reconciliation query in the sidecar. For ad-hoc work, a complementary query per `analyst-workflow` step 4 — or accept the `single-source` label below.
3. **Golden green.** `regression-check.sh --all` (or at minimum the goldens covering the same domain). (Rule #14.)
4. **Evidence written.** Multi-query analyses route through `export-results.sh` so a `manifest.json` exists alongside the CSV (org id, env, sql, query id, sha256, row count). (Rule #11.)
5. **Sensitive output handled.** If the query touches `pii` / `restricted` / `json_sensitive` columns, route per `pii-safe-analysis` (rules #26–#28).
6. **Freshness stated.** Using the confidence-label format below.

If you cannot tick every box, label the number `single-source` or `stale` explicitly — calibration depends on the consumer knowing which guards ran.

## Confidence labels

A small enum the publisher prefixes onto every number reported in chat:

| Label | Meaning |
|---|---|
| `verified` | Profile clean, reconciliation matches, golden green, manifest written. Every guard ran and agreed. |
| `single-source` | Profile + golden only. No independent cross-check ran (intentional for ad-hoc, or no second path exists yet). Trust at your own calibration. |
| `stale` | Last `max(created_at)` older than the snapshot SLA (~36h). The number reflects the last good snapshot; current state may differ. |
| `sandbox` | Environment is not production. Test data; do not act on it as if it were a customer figure. |

Labels stack with `pii-redacted` (from `pii-safety.md`) when sensitive columns were involved but pseudonymised. Example: `[verified · pii-redacted] 1,432 policyholders | …`.

**Report-time format:**

```
[verified] 1,432,907 policies | as-of 2026-05-21 04:12 UTC | golden: fact_policies_active_count | manifest: evidence/2026-05-21/active_count/manifest.json
```

For `single-source` numbers, omit the golden/manifest line if neither exists; the label by itself is the warning:

```
[single-source] 142 SMSes yesterday | as-of 2026-05-21 04:12 UTC
```

## What you must configure / what to do

There is no env var equivalent to `ROOT_AGENTS_COMPLIANCE_MODE` for data trust — accuracy isn't a gradient, and the framework's gates are either disciplines (which an env var can't enforce) or already-runtime-enforced rules (#14 regression check, #15 golden shape, #26 PII-clean goldens).

Operational habits, not configuration:

- **Run `bash .agents/tools/framework-status.sh` at session start** when something feels off. The dashboard surfaces regression goldens pass/fail, view counts by layer, and maturity flags pointing at the next step.
- **Run `regression-check.sh --all` before publishing.** Cheap; covers the current org's goldens.
- **Use the confidence-label format above** on every reported number. If you can't reach `verified`, say which label applies and why.

## Audit trail

After-the-fact inspection of trust posture:

| Surface | What it tells you |
|---|---|
| `regression-check.sh --all` | Current pass/fail state of every pinned golden in the active org. |
| `framework-status.sh` | One-screen view: regression counts, view counts, maturity flags, deps. |
| `evidence/<date>/<name>/manifest.json` | What SQL produced this exact number, against which snapshot, with sha256 of the result. (`sensitive/<date>/...` for the PII-bearing twin.) |
| `regressions/<org_id_hash>/<name>.json` | Historical baseline: the SQL + result captured when the golden was pinned, with `--re-record` git history. |
| Sidecar markdown under `bi/`, `ops/` | Per-view canonical definition, caveats, and (now) reconciliation queries. |

### What the audit cannot tell you

- Whether the agent's chat reply quoted the number with the wrong label (a posture violation). The framework doesn't log chat replies; auditing this requires the host runner's conversation log.
- Whether two analysts using the same `single-source` number for different downstream purposes have aligned on the definition. The label says "no second path agreed"; alignment between consumers is out of scope.
- Whether a reconciliation SQL is itself correct. A reconciliation is only as good as the independent path it encodes; review the SQL as you would the primary view.

(A future `trust-audit.sh` paralleling `compliance-audit.sh` is flagged in FUTURE.md but not built — the discipline must land first as policy before being mechanised.)

## Posture and trade-offs

The framework prioritises **safe-by-default at the publish boundary, frictionless in ad-hoc exploration**. The trust gate is non-trivial — profile + reconcile + golden + evidence + freshness is six steps — and that's deliberate for any number a human will act on. The cost is the publisher must stop and walk the gate; the benefit is the consumer downstream has a labelled number with traceable evidence.

Ad-hoc exploration is exempt by design. A one-shot ops question ("how many SMSes did we send yesterday?") doesn't need a reconciliation pass or a regression golden — `[single-source]` is the right label and the right amount of friction. The doctrine guards the boundary where exploration becomes publication, not exploration itself.

If a team finds itself routinely shipping `single-source` numbers a stakeholder later challenges, that's the signal to invest reconciliation queries in the responsible BI sidecars — not to weaken the labels. The `observe` + `retro` loop surfaces this pattern naturally.

## Cross-references

| Resource | Purpose |
|---|---|
| `rules.md` #1, #2, #3, #4 | The codified scope/unit/date/freshness rules. Read these in addition to this doc. |
| `rules.md` #10, #11 | Profile-before-analyse; named-consumer manifest evidence. |
| `rules.md` #14, #15 | Regression check before publishing; golden shape. |
| `rules.md` #26, #27, #28 | PII handling — orthogonal doctrine, labels stack. |
| `skills/premortem.md` | Pre-flight gating skill — failure modes + dry-run cost. |
| `skills/profile-data.md` | Pre-flight gating skill — row count, freshness, nulls, cardinality. |
| `skills/regression-test.md` | Pin and verify deterministic goldens against fixed historical windows. |
| `skills/analyst-workflow.md` | The publish-time check applies step 7 of this skill. |
| `skills/bi-view.md` | Building the analytical layer; step 11 is the reconciliation requirement. |
| `skills/ops-dataset.md` | Operational caches; `ops_monthly_invoice_lines_view.md` is the canonical reconciliation example. |
| `tools/regression-check.sh`, `regression-record.sh` | Goldens. |
| `tools/profile-table.sh` | Pre-flight profile. |
| `tools/export-results.sh` | Evidence + manifest. |
| `tools/framework-status.sh` | Maturity dashboard. |
| `references/pii-safety.md` | Sibling doctrine — handling, not correctness. Labels stack. |
| `references/per-client-analysis.md` | Per-client variant — reconciliation typically joins universal fact + `rp_dim_client_terms_view`. |
| `FUTURE.md` §3 | Envelope goldens, performance regressions — extensions to F5. |
| `FUTURE.md` §6 | Schema drift, data-quality monitors — extensions to F1/F2. |
| `FUTURE.md` §4 | `trust-audit.sh` (planned, not built). |
| `FUTURE.md` §8 | `publish-check.sh` (planned, not built). |
