# FUTURE — menu of unbuilt ideas

Not a backlog. Not a roadmap. A menu the framework pulls from when real signal emerges. If you've hit friction worth addressing, find the closest section here, or call `observe --kind tool-gap` to add a new one. **Don't burn through this top-to-bottom** — each item is a contingent next step, not a commitment.

## 1. Push delivery (SFTP / HTTPS / S3)

When sensitive output needs to leave local disk under audit, the framework needs a `delivery-push.sh` tool with per-call user confirmation (rule #19). Today the boundary is "land local, push manually". Build this when you have at least three concrete recurring delivery targets — until then the manual route is faster than the abstraction.

## 2. OAuth refresh + Basic auth in `fetch-api.sh`

v1 supports bearer, header, and none. OAuth refresh (Google APIs, Slack newer endpoints) and Basic auth (some older REST APIs, Stripe webhooks) are deferred. Build when a target API actually needs them — the YAGNI risk is high.

## 3. Multi-source in one project (formal support)

The framework already copes with `data/raw/github/`, `data/raw/jira/`, `data/raw/zendesk/` coexisting in one DuckDB. Formal multi-source support would mean: per-source `.env` switching, multiple `references/sources/*.md` files (already supported), maybe a `bi_dev_lifecycle_view` template that demonstrates cross-source joins. Build when an adopter asks for the recipe.

## 4. `trust-audit.sh` (parallel to compliance-audit.sh)

Today `compliance-audit.sh` summarises PII-touching invocations. The data-trust equivalent — "which numbers were published with which labels, against which goldens, at which freshness" — is the next logical sibling. Build after the discipline (confidence labels, publish-time gate) lands as habit; mechanising before the habit lands is premature.

## 5. View pruning + scratch hygiene

Stale `scratch_*_view`s accumulate. The framework already has `list-views.sh --tier scratch` and `drop-view.sh`; what's missing is a "drop scratch views older than N days, owned by current namespace" helper. Build when a project's `main.duckdb` shows >20 scratch views.

## 6. Schema drift / data-quality monitors

An extension of F1 (wrong scope) and F2 (stale snapshot): a daily check that the latest fetch matches the previous fetch in row-count-order-of-magnitude, column shape, and key cardinality. The diff is the signal — and the manifest already records `records`, `pages`, `bytes` per fetch, so the building blocks exist. Build when drift has bitten at least once.

## 7. Cross-session memory / lineage

Today, a learned skill is the only artefact that survives a session. Lineage — "which fetch landed which table, which view depends on which table, which golden depends on which view" — would let `bi_pr_cycle_time_view`'s sidecar say "depends on `raw_github_pulls` last refreshed 2026-05-18 12:30 UTC". The DuckDB `duckdb_views()`/`duckdb_tables()` catalogue + the fetch manifests have enough to derive this; what's missing is the renderer.

## 8. `publish-check.sh`

The publish-time gate (data-trust.md) is six steps. A `publish-check.sh <number-label>` that walks the gate semi-automatically — runs `regression-check.sh --all`, looks up the relevant sidecar's reconciliation query, runs it, prints the freshness label — would shorten the loop. Build when the gate is being walked routinely; the friction is the feature today.

## 9. dbt promotion

When `bi_*` views stabilise across consumers and the team wants a CI/CD-managed pipeline, the natural promotion is dbt. The framework's `bi/` sidecars (grain, facts, dims, reconciliation) map cleanly onto dbt model docs. Promote a single view at a time; the framework's regression goldens carry over as dbt tests.

## 10. Embeddings / semantic search over learned skills

Once `skills/learned/` has 30+ entries, `routing-by-description` starts missing on synonyms. A semantic index (DuckDB has a vector-similarity extension) would let the agent ask "any learned skills that fired on cycle-time analyses?". Build at scale, not before.
