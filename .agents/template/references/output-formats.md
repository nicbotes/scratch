# Reference: output formats

Choose format from the consumer, not the producer's preference. The matrix:

| Consumer | Format | Tool | Notes |
|---|---|---|---|
| Human reading in chat | CSV (default) | `duckdb-query.sh "<sql>"` | Honours `ROOT_AGENTS_MAX_ROWS` cap. |
| Human reading in a file (shareable) | CSV | `duckdb-query.sh ... --to-file path.csv` | Pair with `export-results.sh` for manifest-backed evidence. |
| Programmatic consumer (script, app) | JSONL | `duckdb-query.sh --format jsonl --to-file path.jsonl` | One JSON object per line; easy to stream. |
| Single-record JSON (single row) | JSON | `duckdb-query.sh --format json --to-file path.json --head 1` | Top-level array of one object. |
| Spreadsheet | CSV | `duckdb-query.sh --to-file path.csv` | Excel reads UTF-8 CSV without BOM. |
| Data pipeline (typed downstream) | **Parquet** | `duckdb-query.sh` then `COPY (...) TO '...parquet' (FORMAT PARQUET)` | Preserves types; cheaper to re-read. Rule #18. |
| BI tool (Tableau, Looker, Power BI) | Parquet, or the view itself | View in `data/db/main.duckdb`, queried directly | DuckDB has ODBC/JDBC drivers; BI tools can connect to the file. |
| Compliance evidence | CSV + manifest | `export-results.sh <name> "<sql>"` | Lands under `evidence/<ts>-<name>/` (or `sensitive/...` if PII). |

## Tab-separated (when CSV breaks)

CSV fails when a cell contains literal commas or newlines without quoting. TSV side-steps this:

```bash
bash .agents/tools/duckdb-query.sh "<sql>" --format tsv --to-file path.tsv
```

## DuckDB COPY for one-off exports

When you need a quick Parquet without the evidence framework:

```bash
bash .agents/tools/duckdb-query.sh "
  COPY (
    SELECT * FROM bi_pr_cycle_time_view WHERE merged_ts >= TIMESTAMP '2025-01-01'
  ) TO '/tmp/cycle_2025.parquet' (FORMAT PARQUET);
"
```

Stdout shows `path=/tmp/cycle_2025.parquet`. For manifest-backed exports, use `export-results.sh` instead.

## Pushed delivery (SFTP / HTTPS / S3)

Not built into the v1 template. When you need to push outputs to a destination, route through:
- `duckdb-query.sh --to-file` (or `export-results.sh`) to land the file locally.
- Your platform's own push tooling (sftp / aws s3 cp / curl).

See rule #19 — until first-class push tooling exists, per-call user confirmation is the safety model. The framework treats local-file as the default exit point.
