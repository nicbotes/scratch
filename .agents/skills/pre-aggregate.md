---
name: pre-aggregate
description: Pre-aggregate large result sets locally with duckdb-query.sh before any rows enter context. Use when the answer to an analytical question is a summary (count, group-by, percentile, top-N, anomaly, distribution) but the underlying data is large. Do NOT use when the consumer needs the raw rows (compliance evidence → compliance-query; ops queue → ops-dataset; machine pipeline → format-output with Parquet UNLOAD), or when the result is small enough to fit under the stdout cap.
---

# Skill: pre-aggregate

The positive counterpart to rule #23 (stdout cap). Rule #23 stops the bleeding when an agent reaches for `SELECT *`; this skill names the right move instead.

## The principle

> Context tokens are scarce. Each row of CSV in context is one fewer token available for *thinking about what the data means*. Raw data lives on disk / S3. Local processing happens **in-file**. Only the summarised result enters context for interpretation.

Athena is billed per scanned byte. DuckDB is free. Pay Athena **once** to produce a typed Parquet (or CSV) file. Iterate on that file with DuckDB as many times as the question needs, at zero marginal cost.

## Three-tier flow

```
┌────────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
│ 1. Pull, don't     │    │ 2. Process locally   │    │ 3. Reason in context │
│    print           │ -> │                      │ -> │                      │
│ athena-query       │    │ duckdb-query on the  │    │ Small summary lands  │
│   --to-file        │    │ file / s3:// URI.    │    │ in context. Agent    │
│ or athena-unload   │    │ Aggregate, group,    │    │ interprets and       │
│   --format parquet │    │ percentile, top-N.   │    │ recommends.          │
└────────────────────┘    └──────────────────────┘    └──────────────────────┘
```

## Steps

1. **Premortem the return size.** If your query's answer is a summary but the underlying scan is wide (thousands or millions of rows), you're in pre-aggregate territory. If you don't yet know, add `LIMIT 50` and run once to scope.
2. **Pull to disk or S3.** Pick by data size:
   - Up to ~100k rows / a few MB → `athena-query.sh --to-file /tmp/data.csv "<sql>"`. Fast, simple, local. The locator line goes to context; the data does not.
   - Larger or pipeline-shaped → `athena-unload.sh <name> "<sql>" --format parquet`. Typed Parquet on S3, cheap to re-read.
3. **Aggregate locally with DuckDB.** Iterate freely — no Athena scan cost:
   ```bash
   bash .agents/tools/duckdb-query.sh \
     "SELECT status, COUNT(*) AS n FROM '/tmp/data.csv' GROUP BY status ORDER BY n DESC"
   ```
   Or for S3 Parquet:
   ```bash
   bash .agents/tools/duckdb-query.sh \
     "SELECT status, COUNT(*) AS n FROM 's3://<bucket>/<org>/unloads/<name>/*.parquet' GROUP BY status"
   ```
4. **Slice the same dataset multiple ways.** The whole point of step 2 is to make iteration free. Group by month, then by region, then by cohort — each call is local and instant.
5. **Reason on the summary.** Only the small grouped result is in context now. State the source file/URI in your reply so the analysis is reproducible.
6. **Pin a regression golden** for the headline number when it's stable. The golden's SQL can be the DuckDB query — `regression-check` re-runs whatever's stored.

## Worked example — feature adoption Q1 2025

Question: *"What fraction of policies adopted plan_type=premium each month in 2025-Q1?"*

```bash
# Step 1+2: pull once, to Parquet on S3 (fast, typed, cheap to re-read)
bash .agents/tools/athena-unload.sh policies_2025q1 \
  "SELECT
     policy_id,
     status,
     module,
     from_iso8601_timestamp(created_at) AS created_ts
   FROM policies
   WHERE environment = 'production'
     AND created_at >= '2025-01-01'
     AND created_at <  '2025-04-01'" \
  --format parquet
# → unload complete: s3://<bucket>/<org>/unloads/policies_2025q1/

# Step 3: aggregate locally — Athena scan is paid for, this is free
bash .agents/tools/duckdb-query.sh \
  "SELECT
     date_trunc('month', created_ts) AS month,
     COUNT(*) AS base,
     COUNT_IF(JSON_EXTRACT_STRING(module, '\$.plan_type') = 'premium') AS adopters,
     1.0 * COUNT_IF(JSON_EXTRACT_STRING(module, '\$.plan_type') = 'premium')
         / NULLIF(COUNT(*), 0) AS rate
   FROM 's3://<bucket>/<org>/unloads/policies_2025q1/*.parquet'
   GROUP BY 1 ORDER BY 1"
# → 3 rows of summary in context. The 50k underlying policy rows never enter context.

# Step 4: slice the same dataset by status (still free, still local)
bash .agents/tools/duckdb-query.sh \
  "SELECT status, COUNT(*) FROM 's3://<bucket>/<org>/unloads/policies_2025q1/*.parquet' GROUP BY status"
```

Three slices, one Athena scan. The agent reasons on three small grouped results instead of 50k raw rows.

## When to *not* pre-aggregate

- **Compliance evidence** — every row must be visible to the auditor. Use `compliance-query` → `export-results.sh`.
- **Ops queues** — every row is an action item. Use `ops-dataset` → `save-view.sh ops_*_view`.
- **Machine pipeline consumer** — the downstream wants the raw rows. Use `format-output` → `athena-unload.sh ... --format parquet`.
- **Small results** — if the answer is already under the row cap, `athena-query.sh` is fine. Don't add ceremony.

## Reference

DuckDB speaks Presto/Trino-ish SQL — same JSON, date, aggregate idioms as Athena with a few differences (`JSON_EXTRACT_STRING` instead of `JSON_EXTRACT_SCALAR`; native `PIVOT`/`UNPIVOT`; `quantile_cont` for percentiles). See `references/athena-sql.md` for the compatibility notes.

→ Cross-references: `rules.md` #23 (stdout cap, defensive) + #24 (aggregate before reading, positive); `references/output-formats.md` (delivery channels for *machine* consumers; pre-aggregate is the loop for the *agent* as consumer); `skills/premortem.md` (return size as a routing decision); `skills/run-query.md` (when to graduate from one-shot SQL to the pre-aggregate loop); `references/examples.md` (Parquet + DuckDB recipe).
