# data/

Two directories with related but distinct lifecycles. Both are gitignored.

## `raw/`

Landed JSONL from `fetch-api.sh`. Path convention:

```
data/raw/<source>/<entity>/<utc-timestamp>.jsonl
data/raw/<source>/<entity>/<utc-timestamp>.manifest.json
```

Each `.jsonl` is one record per line (flattened with `--jq-extract`). The sibling
`.manifest.json` records `pages`, `records`, `expected`, `complete`, `bytes`, timings.

`land-to-duckdb.sh` reads from here. **Do not delete** until you're sure the
landed snapshot isn't referenced by a regression golden — `regression-check`
re-executes against the current `main.duckdb`, but reconstructing a missing
snapshot requires re-fetching from the API.

## `db/`

DuckDB databases. The default is `main.duckdb`. `land-to-duckdb.sh` creates or
appends `raw_<source>_<entity>` tables here; `save-view.sh` creates `bi_/ops_/scratch_`
views. Everything analytical happens here, not against the API.

You can safely delete `main.duckdb` to rebuild from `data/raw/` — re-run
`land-to-duckdb.sh` for each `<source>/<entity>` you need. Views must be re-saved
(they live in the DB, not on disk as DDL files).

## Lifecycle

```
fetch-api.sh   →  data/raw/<source>/<entity>/*.jsonl
land-to-duckdb →  data/db/main.duckdb (table raw_<source>_<entity>)
save-view.sh   →  data/db/main.duckdb (views bi_*_view / ops_*_view)
duckdb-query   →  reads from main.duckdb
export-results →  evidence/<ts>-<name>/results.csv + manifest.json
```

Refresh by re-running `fetch-api.sh` + `land-to-duckdb.sh --mode replace` (or
`--mode upsert --pk <id>` if you want to merge with history).
