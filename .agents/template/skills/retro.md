---
name: retro
description: End-of-session feedback synthesis — cluster the day's observe notes by target file and write concrete patches under .agents/proposals/ for human review. Use when the user asks for a session review, the session is wrapping, or feedback/<today>.jsonl has 10+ entries. Do NOT use when the feedback log is empty or the session was a one-off lookup with no friction.
---

# Skill: retro

The retro converts raw friction notes into concrete edit proposals. It **never edits the live framework** — patches land under `.agents/proposals/<utc-ts>/` for the user (or a follow-up session) to review and apply.

## Steps

1. **Check the inputs:**
   ```bash
   sid="${ROOT_AGENTS_SESSION_ID:-$(date -u +%Y-%m-%d)}"
   wc -l .agents/feedback/$sid.jsonl .agents/sessions/$sid.jsonl 2>/dev/null
   ```
   If the feedback file is empty or missing, skip the retro and tell the user there's nothing to review.
2. **Cluster notes by `target`.** Use the session-local feedback log and the session trace together — the trace tells you which tools ran; the feedback tells you which moments hurt.
3. **For each target cluster, draft a concrete edit:**
   - `description-miss` / `progressive-disclosure` → propose a rewritten description string (the YAML frontmatter `description:` line). Include the trigger phrases the agent missed on.
   - `reference-thrash` → propose promoting a paragraph from the reference into `AGENTS.md`, or splitting the reference.
   - `tool-gap` → propose a flag signature and a one-paragraph rationale.
   - `rule-missing` → propose a new numbered rule for `rules.md`, with a one-line worked example.
   - `success-pattern` → propose an addition to `references/examples.md`.
4. **Write each proposal under `.agents/proposals/<utc-ts>/`:**
   - `.agents/proposals/20260518T191500Z/skills__analyst-workflow.md.patch` — a unified diff (or a clearly-marked "before / after" block if the change is too structural for a diff).
   - `.agents/proposals/20260518T191500Z/RATIONALE.md` — one paragraph per proposal, linking back to feedback entries by `ts` and `note`.
5. **Maturity-signal pass.** Read `bash .agents/tools/framework-status.sh` and act on the flags:
   - **Goldens count rising past 5** without a `bi_dim_date_view` → propose adding a conformed date dimension. Cheap; used by every cohort/trend analysis.
   - **Several `bi_*_view`s without reconciliation sidecars** → propose adding reconciliation queries to the canonical sidecars.
   - **Partial-flagged tables not refreshed** → propose a re-fetch run or a documented decision to live with the partial state.
6. **Learned-skills clustering pass.** List `.agents/skills/learned/*.md` and count `Skill Learned` / mentions in `sessions/*.jsonl`. For each:
   - **High usage** → draft a promotion patch under `proposals/<ts>/promote-learned-<name>.md`: move from `learned/` to canonical `skills/`, strip the "not yet curated" banner, tighten the description. Include AGENTS.md decision-tree edits if warranted.
   - **Low / zero usage** → draft a deletion proposal with rationale ("captured 2 sessions ago, never re-hit; either superseded or premature"). Better to remove than to drown the routing layer.
   - **Never edit `skills/learned/<name>.md` itself** — patches and rationale only.
7. **Hand back a one-screen summary:** top 3 proposals, total entries reviewed, files touched. The user applies the patches with normal review.
8. **Never edit live files.** Rules.md #11. If a proposed change feels obvious enough to apply immediately, that's a signal to ask the user — not to bypass review.

## Reference

Proposal folder layout:
```
.agents/proposals/20260518T191500Z/
├── RATIONALE.md
├── skills__analyst-workflow.md.patch
├── rules.md.patch
└── tools__fetch-api.sh.patch
```

The flat naming (`skills__analyst-workflow.md.patch` rather than nested folders) keeps `git status` readable when proposals accumulate.

A regression failure (`regression-check --all` red) deserves its own proposal: capture the failing golden's name, the expected/actual diff, and a hypothesised cause in `RATIONALE.md`. Don't suggest re-recording the golden in a retro proposal — that requires a separate human decision.

→ Cross-references: `rules.md` #11 (no live edits), #12 (red golden = stop-the-line).
