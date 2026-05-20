---
name: cross-org-explore
description: Pull the same per-org analytical view from every org in ROOT_ORG_IDS, land all CSVs in a single local DuckDB file as one unified table with org_id / org_name prepended, then iterate locally for system-wide insights. Use when an analyst asks "across all our orgs", "system-wide", "company-wide", or "internal insights", AND wants to keep slicing the same dataset multiple ways (group-bys, joins, percentiles). Do NOT use for compliance (per-org evidence — rules.md #16), for a single one-shot cross-org query that doesn't need re-slicing (use multi-org-query for that), or for ops queues (per-org ops_*_view, no cross-org concept).
---

# Skill: cross-org-explore

The per-org Data Adapter is one workgroup per org — Athena can't federate across them. For internal-insights work, that constraint means the cross-org join happens **on the analyst's laptop in DuckDB**, not in Athena. This skill names the workflow.

## The principle

> Per-org `fact_*_view` / `dim_*_view` is the contract. Identical schema across orgs is the precondition. The fan-out is a shell loop; the aggregation is DuckDB. Athena pays per-org once; DuckDB iteration is free.

Sibling to `pre-aggregate` (rules #23/#24): pull once, slice many. The only difference: here the "once" is *once per org*, and the resulting CSVs are unified into a single DuckDB table before the analyst starts asking questions.

## Three-tier flow

```
┌─────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────┐
│ 1. Per-org views        │   │ 2. Fan-out + unify       │   │ 3. Iterate locally   │
│    (precondition)       │ → │                          │ → │                      │
│ Identical fact_*_view / │   │ cross-org-pull.sh loops  │   │ duckdb <file>        │
│ dim_*_view exists in    │   │ ROOT_ORG_IDS, pulls each │   │ → free, instant      │
│ every org's workgroup   │   │ org's CSV via athena-    │   │ aggregations across  │
│ with the same columns.  │   │ query.sh, loads them all │   │ all orgs.            │
│                         │   │ into one DuckDB table    │   │                      │
│                         │   │ `unified` with org_id /  │   │                      │
│                         │   │ org_name prepended.      │   │                      │
└─────────────────────────┘   └──────────────────────────┘   └──────────────────────┘
```

## Steps

1. **Confirm `ROOT_ORG_IDS` is set** to the orgs in scope. First-time setup: run `discover-orgs.sh` to probe Athena workgroups across regions and emit a ready-to-paste `.env`:
   ```bash
   AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... \
     bash .agents/tools/discover-orgs.sh > .env.suggested
   ```
   The output already includes `ROOT_ORG_IDS`, the majority `ROOT_ATHENA_S3_BUCKET`, and the `ROOT_ATHENA_S3_BUCKET_BY_ORG` override map for orgs on a different bucket. `AWS_REGION` is auto-detected from the per-org bucket via `aws s3api get-bucket-location`, so you usually don't set it manually — and `AWS_REGION_BY_ORG` is only needed in the unusual case of region-without-bucket divergence.

   If you already know which orgs are in scope, just export directly:
   ```bash
   export ROOT_ORG_IDS="<uuid-1>,<uuid-2>,..."
   export ROOT_ATHENA_S3_BUCKET="bucket-default"
   export ROOT_ATHENA_S3_BUCKET_BY_ORG="<uuid-x>:bucket-other"   # only the exceptions
   ```
   The single multi-org-scoped AWS access key handles auth across all orgs; the override map only switches destination buckets for orgs that need it.

2. **Decide on the per-org view or inline SQL.** Cross-org work requires identical schema in each org. Options:
   - A standing `fact_*_view` / `dim_*_view` that already exists in every org's workgroup (use `--view <name>`).
   - An inline `SELECT` against a base table (use `--sql "..."` or pipe via stdin). Base tables like `policies`, `payments`, `claims`, `policyholders`, `organizations` are guaranteed-present in every org.

3. **Pull and unify in one call:**
   ```bash
   bash .agents/tools/cross-org-pull.sh --view fact_policies_view \
     --out /tmp/policies.duckdb
   ```
   The tool: loops orgs, resolves each org name via `whoami.sh`, writes per-org CSVs to `.agents/cross-org/<ts>/<org_id>.csv`, and loads them all into the named DuckDB file. Orgs where the view is missing get a `skip org=<id> ... reason="query failed: ..."` line on stderr and are excluded — the run keeps going.

4. **Iterate freely in DuckDB:**
   ```bash
   duckdb /tmp/policies.duckdb \
     -c "SELECT org_name, status, COUNT(*) AS n FROM unified GROUP BY 1, 2 ORDER BY 1, n DESC"
   ```
   Or for shell-piped consumption with the framework's row cap:
   ```bash
   bash .agents/tools/duckdb-query.sh --input /tmp/policies.duckdb \
     "SELECT org_name, COUNT(*) FROM unified GROUP BY 1"
   ```

5. **Reason on the summary.** Only the small grouped result lands in context. State the source `.duckdb` path and the orgs that were included/skipped so the analysis is reproducible.

## Worked example — active policies across all orgs

Question: *"How many active policies do we have in each org, and what's the total?"*

```bash
export ROOT_ORG_IDS="<uuid-1>,<uuid-2>,<uuid-3>"
bash .agents/tools/cross-org-pull.sh \
  --sql "SELECT policy_id, status, created_at FROM policies WHERE environment = 'production' AND status = 'active'" \
  --out /tmp/active_policies.duckdb
# → /tmp/active_policies.duckdb table=unified orgs=3/3 skipped=0 rows=12847

duckdb /tmp/active_policies.duckdb \
  -c "SELECT org_name, COUNT(*) AS active FROM unified GROUP BY 1 ORDER BY active DESC"
# 3 rows of summary in context. The 12k+ underlying policy rows never enter context.

# Same dataset, different slice — no Athena cost
duckdb /tmp/active_policies.duckdb \
  -c "SELECT date_trunc('month', CAST(created_at AS TIMESTAMP)) AS month, COUNT(*)
      FROM unified GROUP BY 1 ORDER BY 1"
```

## Schema-drift caveat

`cross-org-pull.sh` ingests with `INSERT INTO unified BY NAME`. If org B's view has an extra column org A's doesn't (or vice versa), DuckDB will raise an error on that org and skip it. That's intentional — silent NULL-fill across drifted schemas hides bugs. Fixes:

- Pin the columns explicitly: use `--sql "SELECT col_a, col_b, col_c FROM <view>"` instead of `--view <name>` so every org returns the same shape.
- Promote the per-org view to a stable `fact_*_view` and keep the DDL in sync (manual today; `FUTURE.md` §2 reserves view-deploy tooling for when this becomes painful).

## When to *not* use this skill

- **Compliance evidence** — rule #16: every compliance package must be unambiguous about which org it came from. Use `compliance-query` per org.
- **One-shot cross-org query, no re-slicing** — `multi-org-query` handles the fan-out + concatenated CSV without the DuckDB layer. Use it when the analyst will look at the result once and move on.
- **Ops queues** — `ops_*_view` is per-org by design. Each org's queue is a separate action list; aggregating across them is meaningless.
- **Single-org work** — if `ROOT_ORG_IDS` would only have one entry, just run `athena-query.sh` directly.

## Reference

Per-org views must have identical column names for `INSERT BY NAME` to work cleanly. The cross-org join is "many CSVs → one DuckDB table"; there is no central Athena view spanning workgroups (Root's data adapter does not support cross-workgroup federation).

→ Cross-references: `skills/multi-org-query.md` (the lighter "loop + concat" sibling); `skills/pre-aggregate.md` (the single-org "pull once, slice many" pattern this skill extends); `rules.md` #16 (compliance is per-org-per-subject — do not fan out); `rules.md` #23/#24 (stdout cap + aggregate-before-reading apply at every DuckDB step here); `tools/cross-org-pull.sh` (the worker); `references/output-formats.md` (when the cross-org summary leaves the chat, route the *summary* through here — never the raw `unified` table).
