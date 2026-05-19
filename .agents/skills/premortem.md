---
name: premortem
description: Gating skill — before any expensive or wide query, state intent and likely failure modes, then dry-run to measure data scanned. Use when the query has no date filter, joins three or more tables, writes a view, exports evidence, or when the user described an analysis but didn't write SQL. Do NOT use for LIMIT 10 exploration or whoami-style lookups.
---

# Skill: premortem

A two-minute gate that prevents 80% of the silent failures (wrong env filter, cents/rands, partition scan, stale snapshot, PII leak). Output the block below into the working context before running.

## Steps

1. **State the intent in one sentence.** "I am about to count active production policies for Q1 2025 broken down by product." If you can't, stop and clarify with the user.
2. **List the 3 most likely failure modes** for this specific query, picking from:
   - wrong `environment` filter (sandbox vs production)
   - stale snapshot (last `max(created_at)` is older than expected)
   - cents/rand mix-up (forgot `/100.0`)
   - PII leak (selecting `*` on a table with identifiers)
   - partition scan cost (no date filter on a large table)
   - join cardinality blowup (many-to-many join)
   - timezone (`AT TIME ZONE` missing — `from_iso8601_timestamp` returns UTC)
   - **return-size blowup** — a `SELECT *` that returns millions of rows; will hit the stdout cap (rules.md #23) and should be routed via `--to-file` / `athena-unload.sh` instead
3. **Estimate return size.** "How many rows will this query return?" If you don't know, that's a signal to add `LIMIT 50` and rerun first, or to check `profile-data` for the base population's row count. Anything beyond a few thousand rows belongs in a file or in S3, not in chat.
4. **Dry-run for cost:**
   ```bash
   bash .agents/tools/athena-query.sh --dry-run "<your sql>"
   ```
   This runs `EXPLAIN`. Pair with the `bytes_scanned` from the session log if `ROOT_AGENTS_DEBUG=1`.
5. **Decide.** If scan cost and return size are acceptable and the failure modes are mitigated (date filter present, env filter present, joins keyed correctly), proceed. If the return size is large but the **answer is a summary**, the decision is `route via pre-aggregate` — pull to file once, then slice locally with `duckdb-query.sh`. If the answer is the raw rows themselves and the consumer is external, the decision is `route via format-output`. If neither and the query is just too big, narrow first.
6. Paste the premortem block into context. Subsequent reasoning refers back to it instead of repeating the analysis.

## Reference

Premortem block template:
```
Intent: <one sentence>
Likely failure modes:
  1. <mode> -> mitigation: <how this query avoids it>
  2. <mode> -> mitigation: <…>
  3. <mode> -> mitigation: <…>
Estimated rows returned: <answer or "unknown — narrowing first">
Dry-run scanned bytes: <DataScannedInBytes>
Decision: <proceed | narrow first | route via format-output | abort>
```

→ Next: `run-query`, `bi-view`, `ops-dataset`, or `compliance-query` — whichever the intent maps to.
