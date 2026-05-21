---
name: bi-view
description: Build the dimensional/Kimball analytical layer (fact_*_view, dim_*_view) that BI tools will read repeatedly and re-aggregate. Use when the deliverable is a reusable layer for KPIs across cohorts/time/segments. Do NOT use for a flat list ops works through (use ops-dataset), a one-off question (run-query), or a compliance dump (compliance-query).
---

# Skill: bi-view

You are building the analytical layer. Discipline matters here — these views get joined, sliced, and trusted for years. Get them wrong and every dashboard downstream inherits the bug.

## Steps

1. **Declare the grain in one sentence.** "One row per policy per day", "one row per payment attempt", "one row per claim event". If the grain is fuzzy, stop and clarify with the user — fuzzy grain is the root cause of most fact-table bugs.
2. **Separate facts from dimensions.**
   - **Facts** = additive measures: premiums (cents), claim amounts, payment counts, durations.
   - **Dimensions** = descriptive context: policyholder, product, time, geography, status.
   One fact view, many dimension views joined on keys.
3. **Conformed dimensions.** One `dim_date_view`, one `dim_policyholder_view`, one `dim_product_view` reused across fact views. Don't duplicate dimensional logic — when policyholder name resolution diverges across fact views, your dashboards will disagree.
4. **Naming is strict** — `save-view.sh` enforces it:
   - `fact_<event>_view` (e.g. `fact_payments_view`, `fact_policy_daily_view`)
   - `dim_<entity>_view` (e.g. `dim_policyholder_view`, `dim_product_view`)
5. **SCD handling.** Snapshots are daily; default to **SCD type 1** (overwrite — latest dimension wins). If you need history-preserving SCD type 2, document the pattern in the sibling doc — don't fake it inside a view that pretends to be type 1.
6. **No `SELECT *` in facts.** Each measure is named and typed (`CAST(SUM(amount) AS BIGINT) AS gross_premium_cents`). Re-stating types prevents downstream confusion.
7. **Premortem the view.** A BI view runs every dashboard refresh — cost compounds. Run `athena-query.sh --dry-run` and check `DataScannedInBytes`.
8. **Persist:**
   ```bash
   bash .agents/tools/save-view.sh fact_payments \
     "SELECT
        from_iso8601_timestamp(payment_date) AS payment_ts,
        policy_id,
        CAST(amount AS BIGINT) AS amount_cents,
        status,
        payment_type
      FROM payments
      WHERE environment = '$ROOT_ENV'"
   ```
9. **Document the view.** Write `.agents/bi/<view>.md` covering:
   - **Grain** (one sentence)
   - **Facts** (column → meaning, units)
   - **Dimensions** (column → join key)
   - **Refresh cadence** (daily, in line with snapshots)
   - **Consumers** (which dashboards / tools read it)
   - **SCD type** chosen
10. **Pin a regression golden.** When the view is stable, record at least one deterministic golden against a fixed historical window (see `regression-test`) — typically the row count or a key aggregate for a single closed quarter.
11. Hand off to `/dev-data-adapter` for the BI-tool wiring (JDBC/ODBC). The agent framework's job ends at the modelled view.

**Promoting from a `rp_scratch_<ns>_*_view`?** Create the canonical `rp_fact_/rp_dim_*_view` first (running both for one snapshot is fine), confirm any consumers have switched, then `drop-view.sh rp_scratch_<ns>_<body>_view`. Never rename in place — shared consumers may already be referencing the scratch path, and Athena view DDL isn't transactional.

## Per-client variant — for commercial-model facts

When the fact is **commercial-model-specific** (invoicing, Bordereau, ceded premium, profit share) it lives in the per-client layer, not the universal one. Same Kimball discipline (declared grain, conformed dimensions, named typed measures, regression golden) — scoped to one client.

| Universal | Per-client |
|---|---|
| `rp_fact_payments_view` | `rp_fact_invoice_acme_view` |
| `.agents/bi/fact_payments_view.md` | `.agents/bi/clients/acme/fact_invoice.md` |
| Same for every client; reads platform tables | Reads from universal views + client-specific terms; ACME's contract shapes the output |

Build flow:
1. **Run `scope-clarify`** first if you got here from a "client X's invoice/Bordereau" question — confirms you're in per-client territory and the slug is registered.
2. **Steps 1–10 above** still apply (grain, facts, dimensions, conformed-dim discipline, no `SELECT *`, premortem, regression golden).
3. **Save with the client flag**: `bash .agents/tools/save-view.sh --client acme fact_invoice "<sql>"` → `rp_fact_invoice_acme_view`.
4. **Doc lives under `.agents/bi/clients/<slug>/<entity>.md`** — the filename encodes the entity, the path encodes the client.
5. **When ≥3 clients have stable bespoke views with ≥2 downstream consumers each**, `framework-status.sh` flags the dbt promotion path (FUTURE.md §9). Don't pre-emptively build dbt; wait for the signal.

Worth doing once: a conformed `rp_dim_client_terms_view` (or per-client `rp_dim_client_terms_<client>_view` if the shape differs) that holds the parameters (cession %, commission, fee schedule) so every `rp_fact_invoice_<client>_view` joins to it instead of hard-coding numbers. Cession % differing by client doesn't justify three full fact views — it justifies one terms dim and three thin per-client facts.

→ See `references/per-client-analysis.md` for the full convention doc and graduation path.

## Reference

Common conformed dimensions to build first:
- `dim_date_view` — one row per calendar day, with day/week/month/quarter/year columns, ISO week, fiscal-year markers. Cheap and used by every cohort/trend dashboard.
- `dim_policyholder_view` — latest known attributes per policyholder (SCD1).
- `dim_product_view` — product module key → product name, line of business.

→ Cross-references: `/dev-data-adapter` for BI tool wiring; `ops-dataset` for the opposite intent (action queues, not analytics).
