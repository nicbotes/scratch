# Proposal 08 — Rule: proactive evidence export for multi-query analyses

**Source feedback note (`feedback/2026-05-19.jsonl`):**
- `2026-05-19T13:15:38Z` (rule-missing) — "Any analysis with a named consumer or that produces a report should be routed through `export-results.sh` proactively — not only on user request. Stdout is hard to read and leaves no audit trail. Default posture: if you ran more than one query to produce an answer, write the evidence before presenting findings."

## Reason

Today's rule #11 says "Compliance output is evidence — always route through `export-results.sh`". The implicit corollary — *non-compliance analyses with a named consumer also deserve evidence* — is not stated, and the friction surfaced this week: an analyst-style report was produced as stdout-only and had to be re-run when the user wanted to share it with a teammate. Re-running cost ~10× the original time (re-derive intermediate aggregates, re-verify numbers match).

The right move is to make "more than one query → write evidence" the default posture, not a per-request flag. Stdout is for one-shot answers; anything assembled from multiple queries with a named consumer should leave an audit trail at the same time as the answer.

## Current state

`rules.md` #11:

```markdown
11. **Compliance output is evidence.** Always route through `export-results.sh` so every CSV has a sibling `manifest.json` (org id, env, sql, query id, sha256, row count).
```

Scoped narrowly to *compliance*. Analyst-workflow / BI-prep / multi-query reports are silent.

## Proposed change

Rather than add a separate rule 26, *broaden* rule #11 so the existing "compliance" anchor still applies but the principle covers all named-consumer outputs:

```diff
-11. **Compliance output is evidence.** Always route through `export-results.sh` so every CSV has a sibling `manifest.json` (org id, env, sql, query id, sha256, row count).
+11. **Named-consumer output is evidence.** Always route through `export-results.sh` so every CSV has a sibling `manifest.json` (org id, env, sql, query id, sha256, row count). "Named consumer" means: a report, a shared document, a human who will act on the number, a downstream pipeline, or anything the agent will reference back to itself in a later turn. Default posture: **if you ran more than one query to produce an answer, write the evidence before presenting findings.** Stdout-only is fine for one-shot lookups; for assembled analyses it loses the audit trail and forces a re-run when the result needs to be shared.
+
+    Compliance evidence is the strict case of this rule — never exempt. For analytical reports, the rule is "do this by default; exemption requires a one-line reason in the reply".
```

## Notes

- This is a behaviour-change rule, not a tooling addition. No code changes.
- The "more than one query" heuristic is deliberately concrete — easy to apply, easy to audit in retrospect.
- Compliance still gets its strict treatment (the existing rule's force). The change only *adds* to the rule's scope.

## Test

After applying, in any analyst-workflow session:

- Multi-query analysis (e.g. cohort with a setup query + a measurement query) emits both a stdout summary **and** a `.agents/evidence/<ts>-<slug>/` folder with manifest.
- If the agent doesn't write evidence, its reply should state why (e.g. "single-query lookup, no consumer named").
- Retro pass over the session log should show `export_results` invocations correlated with multi-query analyses.

Acceptance: the rule reads as the actual default posture, not a per-request flag.
