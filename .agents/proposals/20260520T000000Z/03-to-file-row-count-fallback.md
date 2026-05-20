# Proposal 03 — `--to-file` row-count fallback (line-count when Athena says null)

**Source feedback note (`feedback/2026-05-19.jsonl`):**
- `2026-05-19T14:19:59Z` (tool-gap) — `athena-query.sh --to-file` reported `rows=0` on a 153-row result; `bytes=21017` was correct, file fully written, DuckDB read it fine.

**Cross-reference:** `proposals/2026-05-20-data-adapter-feature-requests.md` item #2 — the upstream fix request to the Data Adapter team. This proposal is the local workaround until that lands.

## Reason

`athena-query.sh --to-file` prints a locator line like:

```
/tmp/policyholders_sample.csv rows=0 bytes=21167 s3_uri=s3://...
```

…but the file contains 154 rows. The reported `rows=0` comes from `Statistics.OutputRows`, which Athena returns as `None` for queries whose results are downloaded directly from S3 (rather than paginated via `GetQueryResults`). `run_athena` in `_lib.sh:141` already normalises `None → 0`, so consumers see a false zero.

Row count is the one signal downstream consumers (rules.md #23 cap logic, the user, the next tool in a pipeline) use to decide whether to apply the row cap. A false zero either suppresses the cap silently or trips empty-result aborts. Both wrong.

The file is on disk locally by the time we print the locator — counting its lines is cheap and accurate.

## Current state

`tools/athena-query.sh:127-133` (the `--to-file` branch):

```bash
if [[ -n "$to_file" ]]; then
  formatted="$(format_csv "$format" "$csv")"
  printf '%s\n' "$formatted" > "$to_file"
  bytes="$(wc -c < "$to_file" | tr -d ' ')"
  echo "$to_file rows=$total_rows bytes=$bytes s3_uri=$s3_uri"
  exit 0
fi
```

`total_rows` (line 80) is `LAST_QUERY_ROWS`, populated by `run_athena` from `Statistics.OutputRows` — the lying source.

## Proposed change

Localise the fix in `athena-query.sh` (not `_lib.sh::run_athena`) so other consumers of `LAST_QUERY_ROWS` aren't surprised by a value that mixes API truth and file truth. Single source of repair, single source of comment:

```bash
if [[ -n "$to_file" ]]; then
  formatted="$(format_csv "$format" "$csv")"
  printf '%s\n' "$formatted" > "$to_file"
  bytes="$(wc -c < "$to_file" | tr -d ' ')"

  # Fallback row count: Athena's Statistics.OutputRows is null for queries
  # whose results are downloaded as CSV directly from S3 (not paginated via
  # GetQueryResults). When it's null/0, count the file locally.
  # Upstream fix tracked in proposals/2026-05-20-data-adapter-feature-requests.md
  # item #2; remove this fallback once Statistics surfaces accurate counts.
  rows="$total_rows"
  if (( rows == 0 )) && (( bytes > 0 )); then
    local file_lines
    file_lines="$(wc -l < "$to_file" | tr -d ' ')"
    # subtract 1 for the header (csv/tsv/jsonl all have one; json doesn't, but
    # --format json on --to-file produces a single-line array so line count
    # would be 1 — we leave rows at 0 for that case as least-wrong)
    if [[ "$format" != "json" ]] && (( file_lines > 0 )); then
      rows=$(( file_lines - 1 ))
    fi
  fi

  echo "$to_file rows=$rows bytes=$bytes s3_uri=$s3_uri"
  exit 0
fi
```

## Notes / non-changes

- `LAST_QUERY_ROWS` in `_lib.sh` stays as-is — it reflects what Athena told us, which other tooling may want to compare against the file count for divergence detection.
- For `--format json` the result is a single-line array; line count isn't a row count. We deliberately don't try to fix it (would require parsing JSON in bash); least-wrong is to leave `rows=0` and note this in code.
- The `bytes > 0` guard avoids running `wc -l` on a genuinely empty result (no rows = no false fallback).

## Test

```bash
# Force a result Athena returns OutputRows=None for: any --to-file query.
bash .agents/tools/athena-query.sh --to-file /tmp/x.csv \
  "SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3"
# Before:  /tmp/x.csv rows=0 bytes=15 s3_uri=...
# After:   /tmp/x.csv rows=3 bytes=15 s3_uri=...

# Empty-result regression
bash .agents/tools/athena-query.sh --to-file /tmp/empty.csv \
  "SELECT 1 WHERE 1=0"
# rows=0 (no false count from header line)
```

Acceptance: locator line accurately reflects file row count for CSV/TSV/JSONL outputs.
