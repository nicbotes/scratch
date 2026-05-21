# ops_monthly_invoice_lines_view

Athena view name: `rp_ops_monthly_invoice_lines_view` (the `rp_` framework prefix is auto-prepended by `save-view.sh`). Long-format invoice lines per org per month. Sibling DDL in `ops_monthly_invoice_lines_view.sql`. Driven by `/ops-monthly-invoice`.

## Action

Finance issues a monthly invoice to each client (org). This view is the input — four canonical line items per (org, month), pivoted into the invoice template.

## Reader

Finance ops, on the monthly close cadence. The agent runs `/ops-monthly-invoice` from this skill; the human reads the pivot output and pastes it into the invoice template.

## Cadence

Monthly. Run after the first full daily snapshot of M+1 lands — typically 1–2 days into the new month. The view will return partial-month numbers if queried mid-month; that's a feature for previews, but not an invoice.

## Downstream sink

Today: pivoted CSV pasted into the invoice template by finance.
Future: scheduled `/dev-data-export` SFTP drop straight to the finance system once the line-item set stabilises.

## Ordering contract

`year_month DESC, line_item ASC` after pivoting back to long format. The pivot itself orders by `org_name`. Line-item order in the wide-format invoice columns is:

1. `gwp_inforce` — biggest number, headline.
2. `sms_billback` — high volume.
3. `banv_billback` — Root pass-through, small.
4. `embed_session_billback` — volume-priced.

## Kimball-skipping rationale

Intentional. This is an `ops_*_view` not a `fact_*_view` because:
- One row per **action** (one invoice line) not one row per **event**.
- No surrogate keys, no SCD type 2 — the daily snapshot is the source of truth and finance reads the latest.
- No conformed dimensions needed — the four line items are a fixed enum, not a growing taxonomy.

See `skills/ops-dataset.md` for the contract.

## Line items

### `gwp_inforce` — Gross Written Premium (in-force basis)

For each month M, every policy that was in force at any point during M contributes its `monthly_premium` to the total. "In force during M" =

```
start_date         < M + 1 month                AND
(end_date          IS NULL OR end_date     >= M) AND
(cancelled_at      IS NULL OR cancelled_at >= M)
```

`unit_count` is the count of in-force policy-months for M (i.e. number of distinct policies in force during M). `total_amount_cents` is the sum of their `monthly_premium` values.

A policy that started on the 28th of a 30-day month still contributes one full `monthly_premium` to that month — the accrual is binary (in-force / not), not pro-rated. This matches how `policies.monthly_premium` is set: the recurring billing amount the policy will incur in any month it is active. Pro-rated accruals would need a different view backed by `policy_ledger`.

### `sms_billback` — Per-SMS billback

`COUNT(*)` of rows in `notifications` with `channel='sms'` whose `created_at` falls in M, regardless of delivery status. Telco bills per-attempt, so failed / unknown_error / opened all count.

`total_amount_cents` is NULL — Root's per-SMS rate to each client is a commercial term applied at the invoice template, not in the view.

### `banv_billback` — Bank Account Name Verification pass-through

`COUNT(*)` of `verification_batches` created in M, with `total_amount_cents = SUM(provider_fee)`. The `provider_fee` is Root's pass-through cost from the verification provider (currently ~395 cents per batch) and bills back to the client at cost.

Status filter intentionally absent — Root pays the provider for submitted batches regardless of `successful`/`failed`/`submitted` outcome, so all rows count.

### `embed_session_billback` — Per-embed-session billback

`COUNT(*)` of rows in `embed_sessions` whose `created_at` falls in M. One row per quote-flow session start. `total_amount_cents` is NULL — per-session rate is a commercial term.

## Reconciliation queries (per line item)

Run inside the org being checked (`ROOT_ORG_ID` + `ROOT_ATHENA_S3_BUCKET` set). Replace `2025-04-01` with the month being checked.

```sql
-- gwp_inforce
SELECT COUNT(*) AS in_force, SUM(monthly_premium) AS sum_premium_cents
FROM policies
WHERE environment='production'
  AND start_date < DATE '2025-05-01'
  AND (end_date IS NULL OR end_date >= DATE '2025-04-01')
  AND (cancelled_at IS NULL OR cancelled_at >= DATE '2025-04-01');

-- sms_billback
SELECT COUNT(*) AS sms_n
FROM notifications
WHERE environment='production' AND channel='sms'
  AND created_at >= TIMESTAMP '2025-04-01 00:00:00'
  AND created_at <  TIMESTAMP '2025-05-01 00:00:00';

-- banv_billback
SELECT COUNT(*) AS banv_n, SUM(provider_fee) AS fee_cents
FROM verification_batches
WHERE environment='production'
  AND created_at >= TIMESTAMP '2025-04-01 00:00:00'
  AND created_at <  TIMESTAMP '2025-05-01 00:00:00';

-- embed_session_billback
SELECT COUNT(*) AS sessions
FROM embed_sessions
WHERE environment='production'
  AND created_at >= TIMESTAMP '2025-04-01 00:00:00'
  AND created_at <  TIMESTAMP '2025-05-01 00:00:00';
```

Each must match the corresponding `unit_count` / `total_amount_cents` in the view for that org / month.

## Known caveats

- **Environment baked in.** The view filters `environment='production'`. To invoice a sandbox or staging environment, re-save with that string substituted.
- **Currency assumed ZAR.** The view emits `'ZAR'` as a literal. For multi-currency orgs the view needs to read `policies.currency` (and equivalents) instead.
- **Source-table absence = missing row, not zero row.** A month with no SMS at all returns zero rows for `sms_billback`, not one with `unit_count = 0`. The DuckDB pivot in `/ops-monthly-invoice` fills missing columns with NULL — read as 0 at invoice time.
- **Daily snapshot lag.** The view reflects the latest Root Platform daily snapshot, not real-time. For month-end close, wait for the M+1 day-1 snapshot.

## Persistence

The view exists in each org's Athena workgroup as `rp_ops_monthly_invoice_lines_view`. Re-save with `save-view.sh ops_monthly_invoice_lines "$(cat .agents/ops/ops_monthly_invoice_lines_view.sql)"` — `save-view.sh` auto-prepends `rp_` and uses CREATE OR REPLACE. When adding a new org to `ROOT_ORG_IDS`, also save the view into that org's workgroup — `cross-org-pull.sh` will otherwise log `skip org=<id> reason="query failed: ..."` and exclude it.
