---
name: observe
description: In-session feedback capture — drop a structured note the moment you hit friction (skill description didn't fire, reference re-read, tool flag missing, rule needed, useful recipe discovered). Use immediately when friction occurs; do not batch. Do NOT use for user typos, transient network errors, or things outside the framework's control.
---

# Skill: observe

The cheap, low-ceremony way the framework improves itself. The note costs you 5 seconds now and saves the next session 5 minutes. Don't wait for retro — observe in the moment so the symptom is fresh.

## Steps

1. **Pick a `--kind`** from `references/feedback-schema.md`:
   - `description-miss` — a skill's description didn't trigger when it should have, or triggered wrongly.
   - `reference-thrash` — you opened the same reference more than once this session.
   - `tool-gap` — a tool needed a flag/feature it didn't have.
   - `rule-missing` — a gotcha bit you that isn't in `rules.md`.
   - `progressive-disclosure` — a skill body was needed because the description was too thin (or vice versa: a body fact would have been better in the description).
   - `success-pattern` — a useful recipe worth keeping.
2. **Identify the `--target` file.** Be specific: `.agents/skills/profile-data.md`, `.agents/rules.md`, `.agents/tools/fetch-api.sh`. The retro step clusters by target.
3. **Name the symptom and the suggested fix shape in one sentence:**
   - "description should mention 'cycle time' — I didn't reach for analyst-workflow when the user asked about cycle time"
   - "rule needed: strptime returns timezone-naive TIMESTAMP, AT TIME ZONE for local conversion"
   - "tool gap: fetch-api.sh should accept --auth basic for legacy APIs"
4. **Call:**
   ```bash
   bash .agents/tools/feedback-note.sh \
     --kind description-miss \
     --target .agents/skills/analyst-workflow.md \
     --note "didn't match on 'retention' / 'cohort'; description should name these intents"
   ```
5. **Move on.** One note per friction event — don't batch, don't editorialise, don't try to write the fix yourself (that's `retro`'s job).

## Note vs learn-skill

`observe` and `learn-skill` are different reflexes:

- **`observe`** — emit a note about something that should change in the framework (description, rule, tool, reference). Retro turns these into proposed edits.
- **`learn-skill`** — persist a *new* reusable workflow for this session and beyond. The artefact is the value, not the note. See `skills/learn-skill.md`.

When you do both (e.g. you found a JSON column's safe-key set *and* noticed that the description of a related skill should call it out more prominently), call `learn-skill.sh` first to capture the artefact, then `observe --kind progressive-disclosure --target skills/<name>.md` to flag the prompt that drove you to learn it the hard way.

## Reference

The framework's quality is measured session-over-session by the rate of `description-miss` and `progressive-disclosure` notes against a given skill. A skill that keeps generating misses is a skill that needs rewriting.

→ Next: continue the task. At end of session, run `retro` to convert the day's notes into proposed patches.
