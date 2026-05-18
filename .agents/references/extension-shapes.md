# Reference: Extension Shapes

Where does a new useful thing live? This is the decision the agent (and the user) should make explicitly, not by reflex. Pick the wrong shape and the framework rots: a workflow buried in `references/`, a one-off SQL ossified as a skill, a learned hypothesis treated as canonical.

## Decision matrix

| Shape | Use when | Lives at | Worked example |
|---|---|---|---|
| **Recipe / example** | Canned SQL with ≤2 parameters and no procedural steps | `references/examples.md` | "premium total by status this quarter" |
| **Skill** | Multi-step workflow with decisions and tool composition; the *process* is the asset | `skills/<name>.md` (frontmatter `name` + `description`) | `feature-adoption`, `compliance-query` |
| **Learned skill** | Discovered in-session, valuable this session, not yet curated | `skills/learned/<name>.md` (carries banner + provenance) | `jsonb-schema-policies-module-<key>` |
| **Reference** | Stable lookup or convention (schema, gotchas, idioms) | `references/<name>.md` | `athena-sql.md`, `schema.md` |
| **Analytical view** | Becomes a recurring KPI consumed by a BI tool; output is *re-aggregated* downstream | `fact_*_view` / `dim_*_view` via `bi-view` | `fact_payments_view` |
| **Operational view** | Becomes a recurring ops queue or sink feed; output is *acted on row-by-row* | `ops_*_view` via `ops-dataset` | `ops_failed_payments_to_retry_view` |
| **Regression golden** | A deterministic number that future sessions must reproduce | `regressions/<name>.json` via `regression-test` | `total_active_premium_2025q1` |
| **Sub-agent** | A persona / decision tree / context budget that differs enough that the parent's routing would be confused by holding both. **Reserved — not built in v1.** | `agents/<persona>/AGENTS.md` (own decision tree, curated skill subset) | Future: `claims-analyst`, `compliance-officer` |

## Flowchart

```
Is the asset a single SQL fragment with ≤2 params?
  └─ yes → recipe in examples.md
  └─ no  → does it have procedural steps and decisions?
              └─ yes → does it cleanly route from existing skills?
                         └─ no  → new skill in skills/
                         └─ yes → discovered in-session?
                                    └─ yes → learned skill in skills/learned/
                                    └─ no  → curated skill in skills/

              └─ no  → is it a stable lookup / convention?
                         └─ yes → reference in references/
                         └─ no  → does the consumer re-aggregate it?
                                    └─ yes → fact_/dim_ view via bi-view
                                    └─ no  → ops_*_view via ops-dataset

Does the same skill keep generating description-miss notes for different audiences?
  └─ yes → candidate for a sub-agent (route the audience first, then the skill)
```

## Worked example: "how to determine adoption of a feature"

The user's prompting question. Walked through the matrix:

1. Single SQL fragment? No — needs clarifying the feature, the base, and the grain.
2. Procedural steps? Yes (clarify → derive → profile → compute → sanity-check → persist → pin golden).
3. Routes from existing skills? No — none of the existing skills cover "fraction of base with feature signal".
4. Discovered in-session? No — it's a stable shape worth curating.
   → **`skills/feature-adoption.md`** (canonical skill).
5. The *answer for a specific feature*, however, is a separate question:
   - One-off → recipe in `examples.md`.
   - Recurring on a dashboard → `fact_feature_adoption_<feature>_view` via `bi-view`.
   - Drives ops calls to non-adopters → `ops_<feature>_non_adopters_view` via `ops-dataset`.
   - Headline number for a regulator/board → pin a regression golden for the closed period.

So one user question becomes one canonical skill (`feature-adoption`) and one or more derived artefacts (recipe / view / golden) depending on what happens next with the answer.

## When to fork a sub-agent

Don't, until:
- Several `description-miss` notes cluster around audience-shaped disagreement (analyst vs ops vs compliance want different defaults for the same skill).
- The AGENTS.md decision tree no longer fits on one screen and trimming it would lose routing fidelity.
- Context budget is the binding constraint — a particular workflow needs to load reference data that the default agent doesn't.

When that day comes, the shape is: `.agents/agents/<persona>/AGENTS.md` (its own decision tree + persona) and `.agents/agents/<persona>/skills/` (a curated subset, possibly symlinked to canonical skills). The `retro` skill will propose this when the pattern is unmistakable.

## When to delete

A learned skill that hasn't been touched in N sessions (where N is whatever the team finds appropriate; the session log makes this measurable) is a candidate for deletion. Retro proposes; a human applies. Better to remove an unused skill than to drown the routing layer in stale hypotheses.
