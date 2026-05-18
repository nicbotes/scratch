---
name: observe
description: In-session feedback capture — drop a structured note the moment you hit friction (skill description didn't fire, reference re-read, tool flag missing, rule needed, useful recipe discovered). Use immediately when friction occurs; do not batch. Do NOT use for user typos, transient AWS errors, or things outside the framework's control.
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
2. **Identify the `--target` file.** Be specific: `.agents/skills/profile-data.md`, `.agents/rules.md`, `.agents/tools/athena-query.sh`. The retro step clusters by target.
3. **Name the symptom and the suggested fix shape in one sentence:**
   - "description should mention 'cohort retention' — I didn't reach for analyst-workflow when the user asked about retention"
   - "rule needed: from_iso8601_timestamp returns UTC, timezone conversion is explicit"
   - "tool gap: athena-query.sh should accept --format json for piping"
4. **Call:**
   ```bash
   bash .agents/tools/feedback-note.sh \
     --kind description-miss \
     --target .agents/skills/analyst-workflow.md \
     --note "didn't match on 'retention' / 'cohort'; description should name these intents"
   ```
5. **Move on.** One note per friction event — don't batch, don't editorialise, don't try to write the fix yourself (that's `retro`'s job).

## Reference

The framework's quality is measured session-over-session by the rate of `description-miss` and `progressive-disclosure` notes against a given skill. A skill that keeps generating misses is a skill that needs rewriting.

→ Next: continue the task. At end of session, run `retro` to convert the day's notes into proposed patches.
