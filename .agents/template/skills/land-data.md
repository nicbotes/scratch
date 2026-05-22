---
name: land-data
description: Pull a fresh slice of data from the API into DuckDB and prepare it for analysis. Use when starting an analysis that needs current data, when refreshing a stale local copy, or when adding a new entity to the local DB. Do NOT use when the data was landed recently this session (re-use it) or when the question is about the API itself (use discover-api).
---

# Skill: land-data

The end-to-end pull. Outputs of this skill: a fresh `raw_<source>_<entity>` table in `data/db/main.duckdb`, a profile block in context, and (if goldens exist for the source) a green `regression-check`.

## Steps

1. **Confirm the source is documented.** `cat .agents/references/sources/<name>.md`. If missing, run `discover-api` first.

2. **Fetch.**
   ```bash
   bash .agents/tools/fetch-api.sh /repos/<owner>/<repo>/pulls \
     --query "state=closed&per_page=100" --paginate link \
     --source github --entity pulls
   # → data/raw/github/pulls/2026-05-21T14:30:00Z.jsonl
   # → data/raw/github/pulls/2026-05-21T14:30:00Z.manifest.json
   ```
   The stdout summary line shows `pages=N records=M complete=true|false`. If `complete=false`, either re-fetch (rate limit, network) or accept the partial state explicitly via `--allow-partial` later.

3. **Land into DuckDB.**
   ```bash
   bash .agents/tools/land-to-duckdb.sh pulls --source github --mode replace
   # → table=raw_github_pulls rows=487 partial=false
   ```
   Refuses if the manifest reports incomplete (F8). Pass `--allow-partial` to override, but then the table is stamped `partial=true` and goldens against it will be refused.

4. **Profile (always, per rule #8).**
   ```bash
   bash .agents/tools/profile-table.sh raw_github_pulls
   ```
   Look for: row count matches expectation; `max(updated_at)` recent; no partial flag; columns include what you expect.

5. **Regression-check** if goldens exist for the source.
   ```bash
   bash .agents/tools/regression-check.sh --all
   ```
   Red goldens are stop-the-line; investigate before any new analysis. (Rule #12.)

6. **Pre-aggregate if widening.** If the analysis needs ≥10k rows, route through `pre-aggregate` rather than reading rows into context.

## Refresh cadence

The framework is snapshot-shaped, not streaming. Re-run `fetch-api.sh` + `land-to-duckdb.sh --mode replace` to refresh. For history-preserving merges, use `--mode upsert --pk id`.

## What lives where after landing

```
data/raw/github/pulls/2026-05-21T14:30:00Z.jsonl          ← one PR per line, raw
data/raw/github/pulls/2026-05-21T14:30:00Z.manifest.json  ← pages/records/complete/bytes
data/db/main.duckdb                                       ← raw_github_pulls table
```

Re-fetches land new dated files. `--mode replace` rebuilds the table from the *latest* file. Use `--input "data/raw/github/pulls/*.jsonl"` to merge all snapshots into one table.

→ Next: `analyst-workflow` (exploratory), `bi-view` (recurring KPI), `ops-dataset` (action queue).
