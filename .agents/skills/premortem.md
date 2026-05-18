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
3. **Dry-run for cost:**
   ```bash
   bash .agents/tools/athena-query.sh --dry-run "<your sql>"
   ```
   This runs `EXPLAIN`. Pair with the `bytes_scanned` from the session log if `ROOT_AGENTS_DEBUG=1`.
4. **Decide.** If cost is acceptable and the failure modes are mitigated (date filter present, env filter present, joins keyed correctly), proceed. If not, narrow first.
5. Paste the premortem block into context. Subsequent reasoning refers back to it instead of repeating the analysis.

## Reference

Premortem block template:
```
Intent: <one sentence>
Likely failure modes:
  1. <mode> -> mitigation: <how this query avoids it>
  2. <mode> -> mitigation: <…>
  3. <mode> -> mitigation: <…>
Dry-run: <DataScannedInBytes>
Decision: <proceed | narrow first | abort>
```

→ Next: `run-query`, `bi-view`, `ops-dataset`, or `compliance-query` — whichever the intent maps to.
