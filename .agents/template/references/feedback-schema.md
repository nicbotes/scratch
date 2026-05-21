# Reference: Feedback Schema

Every `observe` call writes one JSON line to `.agents/feedback/<session>.jsonl`. The retro step reads these and clusters by `target`.

## Line shape

```json
{
  "ts": "2026-05-18T14:23:11Z",
  "session": "2026-05-18",
  "kind": "description-miss",
  "target": ".agents/skills/analyst-workflow.md",
  "note": "didn't match on 'retention'; description should name cohort/retention/funnel intents",
  "api_base_hash": "8f3c..."
}
```

`feedback-note.sh` produces these — call it instead of writing the file directly.

## Categories

| `--kind` | Meaning | Typical `--target` |
|---|---|---|
| `description-miss` | A skill's description didn't trigger when it should have, or triggered wrongly | `skills/<name>.md` (the frontmatter) |
| `reference-thrash` | A reference was opened more than once in the same session — sign that the relevant chunk should be promoted closer to the agent's default context | `references/<name>.md` → fix is usually a one-paragraph promotion into `AGENTS.md` |
| `tool-gap` | A tool needed a flag / feature / output format it didn't have | `tools/<name>.sh` |
| `rule-missing` | A gotcha tripped you that wasn't in `rules.md` | `rules.md` |
| `progressive-disclosure` | A skill body was needed because the description was too thin, OR a body fact would have been better in the description (the routing fact lives in the wrong layer) | `skills/<name>.md` |
| `success-pattern` | A useful recipe worth keeping for next session | `references/examples.md` |

## Quality signal

The framework's quality is measured session-over-session by:

- **`description-miss` rate** per skill — a skill that keeps generating misses is a skill that needs its description rewritten.
- **`progressive-disclosure` rate** per skill — a skill whose body is over-disclosed (slow to scan) or under-disclosed (had to read the body to route).
- **`reference-thrash` count** per reference — a reference that's re-opened often is a candidate for promotion into the entry point.
- **`tool-gap` count** per tool — a tool with multiple gaps is a candidate for an interface revision.
- **`rule-missing` count** — every legitimate `rule-missing` note that's accepted in retro becomes a permanent rule. The rate should trend down over time.
- **`success-pattern` count** — pure win. Trends up.

## Cadence

- **In-session:** the agent calls `observe` the moment friction occurs. One note per event, not batched.
- **End-of-session:** `retro` clusters the notes by `target`, drafts patches under `.agents/proposals/<ts>/`, hands back to the user.
- **Cross-session:** the user (or a follow-up session) reviews `proposals/`, applies the ones that hold up, deletes the rest.

## Guardrails

- `sessions/` and `feedback/` are gitignored. They are runtime artefacts — useful within a session, not a long-term store. `retro` distils them into `proposals/`, which **is** tracked.
- `retro` never edits live skill/tool/rule files (rules.md #13).
- A `regression-check --all` failure during a session deserves a `rule-missing` or `tool-gap` note and gets escalated in the retro RATIONALE — never silently re-record the golden inside a retro.
