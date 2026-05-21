---
name: ops-monthly-invoice
description: Produce the monthly per-org invoice line items (GWP in-force, SMS billbacks, BANV billbacks, embed session billbacks) by fanning out the `rp_ops_monthly_invoice_lines_view` across `ROOT_ORG_IDS` and pivoting locally in DuckDB. Use when finance needs the monthly close numbers for one or more client orgs, or asks for "invoice lines", "billbacks", or "GWP by month". Do NOT use for revenue recognition or accounting reconciliation — this is a billing input, not a ledger.
---

# Skill: ops-monthly-invoice

The monthly close numbers finance needs per client (org). One row per (org, month) with stable columns for every line item, even when the underlying surface had zero activity that month.

## What the view returns

`rp_ops_monthly_invoice_lines_view` is long-format: one row per `(year_month, line_item)`. Line items:

| `line_item` | Source table | `unit_count` | `total_amount_cents` |
|---|---|---|---|
| `gwp_inforce` | `policies` | policies in force at any point during the month | `SUM(monthly_premium)` in cents |
| `sms_billback` | `notifications WHERE channel='sms'` | sms attempts created in the month | NULL (per-org rate × units at invoice time) |
| `banv_billback` | `verification_batches` | account-name-verification batches created in the month | `SUM(provider_fee)` cents (Root pass-through) |
| `embed_session_billback` | `embed_sessions` | sales-flow sessions created in the month | NULL (per-org rate × units at invoice time) |

In-force GWP definition: a policy contributes to month M's GWP if `start_date < M+1` AND `(end_date IS NULL OR end_date >= M)` AND `(cancelled_at IS NULL OR cancelled_at >= M)`. `unit_count` is the in-force-policy count; multiply by 12 for an annual run-rate sense check.

## Monthly run

```bash
# 1. Month being invoiced (YYYY-MM)
MONTH=2025-04

# 2. Fan out across every org in ROOT_ORG_IDS into one DuckDB file
bash .agents/tools/cross-org-pull.sh \
  --sql "SELECT * FROM rp_ops_monthly_invoice_lines_view WHERE year_month = DATE '$MONTH-01'" \
  --out "/tmp/invoice_$MONTH.duckdb"

# 3. Pivot to the finance shape — one row per org, stable column set
duckdb "/tmp/invoice_$MONTH.duckdb" -box -c "
  PIVOT unified
  ON line_item IN ('gwp_inforce', 'sms_billback', 'banv_billback', 'embed_session_billback')
  USING SUM(unit_count) AS units, SUM(total_amount_cents) AS cents
  GROUP BY org_id, org_name, year_month
  ORDER BY org_name;
"
```

The explicit `IN (...)` list forces all eight columns (`<line_item>_units` and `<line_item>_cents`) to appear even when the org had zero activity for that line item — finance pastes the result into the invoice template without column-set drift between months.

Sample output (2025-04, the two orgs the credentials can see):

```
┌──────────────┬────────────┬─────────────────────┬─────────────────────┬───────────────────┬───────────────────┬────────────────────┬────────────────────┐
│   org_name   │ year_month │ banv_billback_units │ banv_billback_cents │ gwp_inforce_units │ gwp_inforce_cents │ sms_billback_units │ sms_billback_cents │
├──────────────┼────────────┼─────────────────────┼─────────────────────┼───────────────────┼───────────────────┼────────────────────┼────────────────────┤
│ Customer Org │ 2025-04-01 │ 1100                │ 428970              │ 12158             │ 347214800         │ 92072              │ NULL               │
│ Root Testing │ 2025-04-01 │ NULL                │ NULL                │ 75                │ 1035953           │ 1                  │ NULL               │
└──────────────┴────────────┴─────────────────────┴─────────────────────┴───────────────────┴───────────────────┴────────────────────┴────────────────────┘
```

NULL = no rows in that source table for that month. Read as 0 when invoicing.

## Backfill / range variant

Need a quarter's worth at once (e.g. for a backdated invoice or trend chart)? Same shape, just widen the date filter:

```bash
bash .agents/tools/cross-org-pull.sh \
  --sql "SELECT * FROM rp_ops_monthly_invoice_lines_view
         WHERE year_month >= DATE '2025-01-01' AND year_month < DATE '2025-07-01'" \
  --out /tmp/invoice_h1_2025.duckdb

duckdb /tmp/invoice_h1_2025.duckdb -box -c "
  PIVOT unified
  ON line_item IN ('gwp_inforce', 'sms_billback', 'banv_billback', 'embed_session_billback')
  USING SUM(unit_count) AS units, SUM(total_amount_cents) AS cents
  GROUP BY org_id, org_name, year_month
  ORDER BY org_name, year_month;
"
```

## First-time setup — saving the view in a new org

The view is org-agnostic but each org's Athena workgroup needs its own copy. To add a new org to the rotation:

```bash
export ROOT_ORG_ID="<new-org-uuid>"
export ROOT_ATHENA_S3_BUCKET="<that-org's-bucket>"   # or use ROOT_ATHENA_S3_BUCKET_BY_ORG
bash .agents/tools/save-view.sh ops_monthly_invoice_lines "$(cat .agents/ops/ops_monthly_invoice_lines_view.sql)"
```

The canonical DDL lives at `.agents/ops/ops_monthly_invoice_lines_view.sql` (see the sibling ops doc). `save-view.sh` uses `CREATE OR REPLACE VIEW`, so re-saving is safe.

## Reconciliation snippet

Drift between the view DDL across orgs would show as silent number changes. If the invoice numbers look off, spot-check one line item against the base table:

```bash
# Pick an org and a month
export ROOT_ORG_ID=<uuid>
export ROOT_ATHENA_S3_BUCKET=<bucket>
MONTH=2025-04

bash .agents/tools/athena-query.sh "
  SELECT COUNT(*) AS in_force, SUM(monthly_premium) AS sum_premium_cents
  FROM policies
  WHERE environment='production'
    AND start_date < DATE '$MONTH-01' + INTERVAL '1' MONTH
    AND (end_date IS NULL OR end_date >= DATE '$MONTH-01')
    AND (cancelled_at IS NULL OR cancelled_at >= DATE '$MONTH-01')
"
```

The numbers must match the `gwp_inforce` row from the view. Equivalent reconciliation queries for the other three line items are in `.agents/ops/ops_monthly_invoice_lines_view.md`.

## When to *not* use this skill

- **Revenue recognition / accounting.** This view counts what to bill, not what's been earned for IFRS purposes. Use the finance system of record.
- **Real-time dashboards.** Daily snapshot only — yesterday's data, not live.
- **Ad-hoc per-org analysis** that doesn't need the four invoice line items. Use `analyst-workflow` or `cross-org-explore`.

## Reference

- View DDL and full per-line definitions: `.agents/ops/ops_monthly_invoice_lines_view.md`
- The fan-out + DuckDB pattern: `skills/cross-org-explore.md`
- Why this is an `ops_*_view` not a `fact_*_view`: `skills/ops-dataset.md` — finance reads four numbered rows per org per month, not a star schema.

→ Cross-references: `skills/cross-org-explore.md` (the underlying fan-out pattern); `skills/ops-dataset.md` (why this is `ops_` not `fact_`); `tools/save-view.sh`, `tools/cross-org-pull.sh`.
