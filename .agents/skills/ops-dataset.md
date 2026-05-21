---
name: ops-dataset
description: Build a flat, denormalised, pre-filtered, action-oriented view (ops_*_view) that ops works through directly or that feeds a downstream sink (Sheets, Zapier, CSV drop). Use when the consumer is a human queue or a non-aggregating pipeline. Do NOT use when the consumer is a BI tool that will re-aggregate (use bi-view), or when the question is exploratory (use analyst-workflow).
---

# Skill: ops-dataset

Operational caches are intentionally not Kimball. They're the opposite — one row per action, every column ops needs already present, ranked by urgency. Don't apologise for the lack of dimensional purity; document it.

## Steps

1. **Name the action, not the data.**
   - Good: `ops_failed_payments_to_retry_view`, `ops_claims_awaiting_decision_view`, `ops_policies_expiring_this_week_view`.
   - Bad: `ops_failed_payments_view` (what's the action?), `ops_claims_view` (which claims?).
   `save-view.sh` enforces the `ops_*_view` prefix.
2. **Pre-filter to the actionable rows only.** This is a queue, not an archive. `WHERE` should be aggressive — exclude already-completed, already-rejected, future-dated. If the row shouldn't be on the screen, it shouldn't be in the view.
3. **Pre-join and denormalise.** Ops opens this and acts. Everything they need (policyholder name, contact, amount, last-attempted-at, reason for failure) is on the row. No further joins required downstream.
4. **Rank by urgency** with `ORDER BY`. The order is part of the contract — oldest first, highest amount first, most overdue first, whatever ops decides. State the ordering in the sibling doc.
5. **Skip Kimball on purpose.** No surrogate keys, no conformed dimensions, no SCD type 2. State this in `.agents/ops/<view>.md` so future readers don't mistake it for sloppiness — it's intentional, and the consumer doesn't pay for what they don't use.
6. **Premortem for daily cost.** Ops datasets refresh on the daily snapshot rhythm; cost compounds but is bounded.
7. **Persist:**
   ```bash
   bash .agents/tools/save-view.sh ops_failed_payments_to_retry \
     "SELECT
        p.payment_id,
        p.policy_id,
        ph.first_name || ' ' || ph.last_name AS policyholder_name,
        ph.email AS policyholder_email,
        p.amount / 100.0 AS amount,
        p.payment_date,
        p.status
      FROM payments p
      JOIN policyholders ph ON ph.policyholder_id = p.policyholder_id
      WHERE p.environment = '$ROOT_ENV'
        AND p.status = 'failed'
      ORDER BY p.payment_date ASC"
   ```
8. **Document the downstream action.** Write `.agents/ops/<view>.md` covering:
   - **Action** ("ops retries each row by calling the payment method on file")
   - **Reader** ("collections team, 09:00 SAST")
   - **Cadence** (daily after snapshot refresh)
   - **Downstream sink** (Sheets export, Zapier hook, ops dashboard) — link to `/dev-data-export` if it feeds an external system on schedule
   - **Ordering contract** (what "first" means)
9. **Optional regression golden** — pin a historical count (e.g. "ops_failed_payments_to_retry had 142 rows on 2025-03-31") if you want drift alerts; not required.

**Promoting from a `rp_scratch_<ns>_*_view`?** Create the canonical `rp_ops_*_view` first, confirm the downstream sink (Sheets / Zapier / dashboard) is pointing at the new name, then `drop-view.sh rp_scratch_<ns>_<body>_view`. Never rename in place — the ops consumer may be polling the scratch path on a schedule.

## Per-client variant — for client-specific ops queues

When an operational queue depends on a client's **commercial model** rather than a universal platform behaviour, it lives in the per-client layer.

| Universal | Per-client |
|---|---|
| `rp_ops_failed_payments_to_retry_view` | `rp_ops_invoice_reconcile_acme_view` |
| `.agents/ops/ops_failed_payments_to_retry.md` | `.agents/ops/clients/acme/ops_invoice_reconcile.md` |
| Same retry policy for every client | ACME-specific reconciliation rules (their fee schedule, their threshold) |

Build flow is identical to the universal variant — pre-filter, pre-join, rank by urgency, document the action — with three differences:

1. **Run `scope-clarify`** first to confirm you're in per-client territory.
2. **Save with the client flag**: `bash .agents/tools/save-view.sh --client acme ops_invoice_reconcile "<sql>"` → `rp_ops_invoice_reconcile_acme_view`.
3. **Doc lives under `.agents/ops/clients/<slug>/<action>.md`** with the same shape (Action, Reader, Cadence, Downstream sink, Ordering contract) plus an extra line naming the client and the contract clause that drove the rule.

→ See `references/per-client-analysis.md` for the full convention doc.

## Reference

Examples of intent:
- `ops_failed_payments_to_retry_view` — payments to retry, ordered by age.
- `ops_claims_awaiting_decision_view` — claims sitting >7 days in `pending`.
- `ops_policies_lapsing_within_7d_view` — proactive outreach queue.
- `ops_beneficiaries_missing_id_view` — data-quality clean-up queue.

→ Cross-references: `/dev-data-export` for scheduled SFTP/S3/HTTPS delivery; `bi-view` for the opposite intent (modelled re-aggregation).
