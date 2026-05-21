---
name: pre-aggregate
description: Pre-aggregate large landed datasets in DuckDB before any rows enter context. Use when the answer to an analytical question is a summary (count, group-by, percentile, top-N, anomaly, distribution) but the underlying data is large. Do NOT use when the consumer needs the raw rows (compliance evidence → compliance-query; ops queue → ops-dataset; pipeline → format-output with Parquet), or when the result is small enough to fit under the stdout cap.
---

# Skill: pre-aggregate

The positive counterpart to rule #20 (stdout cap). Rule #20 stops the bleeding when an agent reaches for `SELECT *`; this skill names the right move instead.

## The principle

> Context tokens are scarce. Each row of CSV in context is one fewer token available for *thinking about what the data means*. Raw data lives in DuckDB. Aggregation happens **in DuckDB**. Only the summarised result enters context for interpretation.

API round-trips are expensive (rate limits, latency). DuckDB queries are free and instant. Pay the API **once** to land the data, then iterate as many times as the question needs at zero marginal cost.

## Three-tier flow

```
┌────────────────────┐    ┌──────────────────────┐    ┌──────────────────────┐
│ 1. Land, don't     │    │ 2. Aggregate in      │    │ 3. Reason in context │
│    print           │ -> │    DuckDB            │ -> │                      │
│ fetch-api +        │    │ duckdb-query on the  │    │ Small summary lands  │
│ land-to-duckdb     │    │ landed table. Group, │    │ in context. Agent    │
│                    │    │ percentile, top-N.   │    │ interprets and       │
│                    │    │                      │    │ recommends.          │
└────────────────────┘    └──────────────────────┘    └──────────────────────┘
```

## Steps

1. **Premortem the return size.** If the answer is a summary but the underlying landed table is wide (thousands or millions of rows), you're in pre-aggregate territory. If you don't yet know, add `LIMIT 50` to a one-shot and run once to scope.
2. **Land once via the normal flow.** `fetch-api.sh` + `land-to-duckdb.sh`. The locator goes to context; the data lives in `raw_<source>_<entity>`. The fetch + manifest also records `complete=true|false` (F8 guard).
3. **Aggregate in DuckDB.** Iterate freely:
   ```bash
   bash .agents/tools/duckdb-query.sh \
     "SELECT state, count(*) AS n FROM raw_github_pulls GROUP BY 1 ORDER BY n DESC"
   ```
4. **Slice the same dataset multiple ways.** The whole point of step 2 is to make iteration free. Group by month, then by author, then by label — each call is local and instant.
5. **Reason on the summary.** Only the small grouped result is in context now. State the source table and `as-of` (from `profile-table.sh`) in your reply so the analysis is reproducible.
6. **Pin a regression golden** for the headline number when it's stable. The golden's SQL is the DuckDB query — `regression-check` re-runs whatever's stored.

## Worked example — PR cycle time by author

Question: *"What's the median PR cycle time per author in Q1 2025?"*

```bash
# Step 1+2: land once
bash .agents/tools/fetch-api.sh /repos/<owner>/<repo>/pulls \
  --query "state=closed&per_page=100" --paginate link \
  --source github --entity pulls
bash .agents/tools/land-to-duckdb.sh pulls --source github

# Step 3: aggregate in DuckDB
bash .agents/tools/duckdb-query.sh \
  "SELECT
     user.login AS author,
     count(*) AS merged_prs,
     CAST(quantile_cont(
       datediff('hour',
                strptime(created_at, '%Y-%m-%dT%H:%M:%SZ'),
                strptime(merged_at,  '%Y-%m-%dT%H:%M:%SZ')
       ), 0.5) AS INT) AS p50_hours
   FROM raw_github_pulls
   WHERE merged_at IS NOT NULL
     AND strptime(merged_at, '%Y-%m-%dT%H:%M:%SZ') >= TIMESTAMP '2025-01-01'
     AND strptime(merged_at, '%Y-%m-%dT%H:%M:%SZ') <  TIMESTAMP '2025-04-01'
   GROUP BY 1
   HAVING count(*) >= 5
   ORDER BY merged_prs DESC LIMIT 20"
# → 20 rows of summary in context. The 5000 underlying PR rows never enter context.

# Step 4: slice by label (still free, still local)
bash .agents/tools/duckdb-query.sh \
  "SELECT label.name, count(*) FROM (SELECT unnest(labels) AS label FROM raw_github_pulls) GROUP BY 1 ORDER BY 2 DESC LIMIT 10"
```

Two slices, one API fetch. The agent reasons on small grouped results instead of raw rows.

## When to *not* pre-aggregate

- **Compliance evidence** — every row must be visible. Use `compliance-query` → `export-results.sh`.
- **Ops queues** — every row is an action item. Use `ops-dataset` → `save-view.sh ops_*_view`.
- **Pipeline consumer** — downstream wants raw rows. Use `format-output` → DuckDB `COPY ... (FORMAT PARQUET)`.
- **Small results** — if the answer fits under the row cap, plain `duckdb-query.sh` is fine.

## Reference

DuckDB SQL differences from common SQL dialects are in `references/duckdb-sql.md`. The most-frequent gotcha at API+DuckDB scale: landed JSON timestamps come in as `VARCHAR` and need `strptime` before comparison.

→ Cross-references: `rules.md` #20 (stdout cap, defensive) + #21 (aggregate before reading, positive); `references/output-formats.md`; `skills/premortem.md` (return size as a routing decision); `skills/run-query.md` (when to graduate from one-shot SQL to the pre-aggregate loop); `references/examples.md`.
