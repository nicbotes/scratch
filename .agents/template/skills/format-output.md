---
name: format-output
description: Choose the right output format and delivery channel for a named consumer of a query result. Use when the answer is leaving the chat — to a file, a data pipeline, a Node/Python app, an ops queue, or an exec pack. Do NOT use when the result stays in chat (use run-query), when the consumer is a BI dashboard reading the DuckDB directly (use bi-view), or when the output is compliance evidence (use compliance-query — it routes through export-results.sh).
---

# Skill: format-output

The end of the analytical loop. Format and delivery follow the consumer — never the producer's preference (rules.md #17). The matrix is `references/output-formats.md`; this skill is the workflow that uses it.

## Steps

1. **Identify the consumer.** Pick one row in `references/output-formats.md`. If the consumer doesn't fit any row, ask the user — don't pick by similarity. "Roughly like a pipeline" is not good enough; pipelines want Parquet, exec packs want PDF, and the channel diverges.
2. **Pick the format from the row.** Common shortcuts:
   - Data pipeline (Spark / dbt / Polars) → Parquet via DuckDB `COPY ... (FORMAT PARQUET)`.
   - Node / Python app → JSONL for streaming, JSON for one-shot small payloads.
   - Ops / Finance opening a file → CSV.
   - Compliance / regulator → already handled by `compliance-query` → `export-results.sh`.
3. **Pick the delivery channel from the row.**
   - In-scope channel (stdout / local file / `.agents/evidence/` via `export-results.sh`) → run the tool the matrix names.
   - Pushed delivery (SFTP / HTTPS / S3) not built into the v1 template — land local, push out-of-band, and call `observe --kind tool-gap --target tools/<missing>.sh --note "..."` so the deferred bucket fills with real signal.
4. **Run the tool.**
   - CSV → `duckdb-query.sh "<sql>" --to-file path.csv`.
   - JSON / JSONL / TSV → `duckdb-query.sh "<sql>" --format <fmt> --to-file path.<fmt>`.
   - Parquet → `duckdb-query.sh "COPY (<sql>) TO 'path.parquet' (FORMAT PARQUET);"`.
   - Compliance evidence → `export-results.sh <name> "<sql>"`.
5. **Tell the consumer how to consume.** Not "done" — "Parquet at `/tmp/cycle_2025.parquet`, snappy-compressed. Read with `pyarrow.parquet.read_table('/tmp/cycle_2025.parquet')` or `duckdb.read_parquet('/tmp/cycle_2025.parquet')`."
6. **Pin a regression golden** if the delivered output is a deterministic snapshot a downstream consumer will trust (rules.md #12). A Parquet of a closed historical window is a clean candidate.

## Reference

**If you got here because `duckdb-query.sh` truncated:** that's by design (rules.md #20). The cap exists so the result doesn't burn the conversation's tokens. The right move is to pick a format and sink from the matrix, not reach for `--no-row-cap`.

**format-output vs pre-aggregate.** Both involve writing to a file instead of stdout. The difference is the **consumer**:

- This skill (`format-output`) — the consumer is a *machine* (data pipeline, Node/Python app, ops worker, BI tool). The output ships as Parquet / JSON / CSV.
- `pre-aggregate` — the consumer is the *agent itself*. DuckDB is the file; you query against the landed table to extract a small summary that lands in context for interpretation.

Pick `pre-aggregate` when the next step is "I need to think about this data". Pick `format-output` when the next step is "ship it to ___".

When a consumer asks for "a file" with no other context, the safe default is **CSV to local file**. State the assumption ("delivering as CSV — say the word if you'd rather have JSONL / Parquet / etc.") so the consumer can redirect cheaply.

When a consumer says "send it to our pipeline", the safe default is **Parquet via DuckDB COPY** — typed, columnar, picked up by anything modern. Tell them the local path; out-of-band push handles delivery.

PII handling (rules.md #19): until first-class push tooling exists, sensitive output lands on local disk only — under `.agents/sensitive/`. Per-call user confirmation for any other destination.

→ Cross-references: `references/output-formats.md` (the matrix), `references/extension-shapes.md` (artefact shape sibling), `compliance-query` (compliance evidence is its own contract), `bi-view` (BI tool consumer path).
