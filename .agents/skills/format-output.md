---
name: format-output
description: Choose the right output format and delivery channel for a named consumer of a query result. Use when the answer is leaving the chat — to a file, S3, a data pipeline, a Node/Python app, ops queue, or an exec/board pack. Do NOT use when the result stays in chat (use run-query), when the consumer is a BI dashboard (use bi-view), or when the output is compliance evidence (use compliance-query — it routes through export-results.sh).
---

# Skill: format-output

The end of the analytical loop. Format and delivery follow the consumer — never the producer's preference (rules.md #20). The matrix is `references/output-formats.md`; this skill is the workflow that uses it.

## Steps

1. **Identify the consumer.** Pick one row in `references/output-formats.md`. If the consumer doesn't fit any row, ask the user — don't pick by similarity. "Roughly like a pipeline" is not good enough; pipelines want Parquet, exec packs want PDF, and the channel diverges.
2. **Pick the format from the row.** Common shortcuts:
   - Data pipeline (Spark / dbt / Polars) → Parquet.
   - Node / Python app → JSONL for streaming, JSON for one-shot small payloads.
   - Ops / Finance opening a file → CSV today (Excel `csv-to-xlsx.sh` deferred).
   - Compliance / regulator → already handled by `compliance-query` → `export-results.sh`.
3. **Pick the delivery channel from the row.**
   - In-scope channel (stdout / local file / S3 via UNLOAD / `.agents/evidence/` / scheduled via `/dev-data-export`) → run the tool the matrix names.
   - Deferred channel → tell the user the tool isn't built yet, do the safe fallback the matrix names (e.g. `lftp` for one-off SFTP with explicit user confirmation), **and call `observe --kind tool-gap --target tools/<missing>.sh --note "<what would have helped>"`** so the deferred bucket fills with real signal.
4. **Premortem the cost.** For `athena-unload.sh` on >1 GB scans or wide date ranges, surface the `bytes_scanned` from the session log first. Get a confirmation before re-running on a wider window.
5. **Run the tool.**
   - CSV → `athena-query.sh "<sql>"` (default).
   - JSON / JSONL / TSV → `athena-query.sh --format <fmt> "<sql>"`.
   - Parquet (or ORC, JSON via UNLOAD) → `athena-unload.sh <name> "<sql>" --format parquet`.
   - Compliance evidence → `export-results.sh <name> "<sql>"`.
   - Scheduled delivery → hand off to `/dev-data-export` skill.
6. **Tell the consumer how to consume.** Not "done" — "Parquet at `s3://<bucket>/<org_id>/unloads/<name>/`, snappy-compressed, partitioned by month. Read with `pyarrow.dataset.dataset(...)`." The matrix shows consumer-side snippets for the common cases.
7. **Pin a regression golden** if the delivered output is a deterministic snapshot a downstream consumer will trust (rules.md #14). A Parquet UNLOAD against a closed historical window is a particularly clean candidate.

## Reference

**If you got here because `athena-query.sh` truncated:** that's by design (rules.md #23). The cap exists so the result doesn't burn the conversation's tokens. The right move is to pick a format and a sink from the matrix rather than reach for `--no-row-cap`.

When a consumer asks for "a file" with no other context, the safe default is **CSV to local file**. State the assumption ("delivering as CSV — say the word if you'd rather have JSONL / Parquet / etc.") so the consumer can redirect cheaply.

When a consumer says "send it to our pipeline", the safe default is **Parquet via `athena-unload.sh` to S3** — typed, columnar, picked up by anything modern. Tell them the S3 URI.

PII handling (rules.md #22): until `deliver-sftp.sh` / `deliver-http.sh` ship, ad-hoc delivery is local-file or S3 within the same org's prefix only. Don't `curl` PII anywhere without explicit per-call user confirmation.

→ Cross-references: `references/output-formats.md` (the matrix), `references/extension-shapes.md` (artefact shape sibling), `/dev-data-export` (recurring delivery), `compliance-query` (compliance evidence is its own contract), `bi-view` (BI tool consumer path).
