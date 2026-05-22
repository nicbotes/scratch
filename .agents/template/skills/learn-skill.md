---
name: learn-skill
description: Persist a workflow you discovered mid-session as a learned skill under skills/learned/, so the next session reaches for it instead of re-deriving. Use when a non-obvious workflow fired twice in this session, when you found a safe-keys list for a json_sensitive column, when an API quirk warrants a recurring recipe. Do NOT use for a one-shot solution, for proposed canonical-skill edits (those go through retro), or for advice you wouldn't take from a stranger.
---

# Skill: learn-skill

The agent's writeable channel. When the framework lacked a skill and you derived one, write it down — once — so it survives the session boundary.

## Lifecycle

1. **Friction happens.** A workflow you ran ad-hoc would have been better as a named, reusable step.
2. **Capture it as a learned skill** mid-session:
   ```bash
   bash .agents/tools/learn-skill.sh github-pr-files-extract \
     --description "Extract file paths changed in a PR via GET /pulls/<n>/files, paginated, normalised into raw_github_pr_files for join against raw_github_pulls. Use when the question needs file-level signal. Do NOT use when only PR-level metadata matters." \
     --body-file /tmp/draft.md \
     --from-task "computing top changed files for the migration PR review"
   ```
3. **Use it.** A learned skill earns its place by being called again. Reference it the next time the routing fits.
4. **Promote it.** At `retro`, if the learned skill has fired in more than one task, retro drafts a promotion patch under `proposals/` — moves the file from `skills/learned/` to `skills/`, strips the "learned" banner, polishes the frontmatter, links it from the relevant decision-tree row in `AGENTS.md`.
5. **Retire it.** Skills that stop firing get removed at retro.

## What to write

The body of a learned skill is **what you'd want to read next session** — terse steps, working SQL, the gotchas you hit. Frontmatter `description:` follows the same form as canonical skills: one paragraph naming the intent (when to use), with explicit anti-cases (when NOT to use).

Don't write the perfect canonical skill on the first pass. Write what's true *for the case you just solved*. The retro promotion polishes it before it becomes canonical.

## When to NOT learn

- The workflow is just a SQL query → save the query in `references/examples.md` or as a `bi_*_view` instead.
- The workflow is a one-line tool call → write it in your reply, not as a skill.
- The "skill" is really a proposed edit to a canonical skill → fire `observe --kind progressive-disclosure --target skills/<name>.md` and let retro handle it.
- The workflow depends on a one-off ticket / customer / branch → ephemeral; not worth persisting.

## Frontmatter for a learned skill

`learn-skill.sh` injects provenance into the frontmatter automatically:

```yaml
---
name: <kebab-case-name>
description: <one paragraph>
learned: true
learned_at: 2026-05-21T14:30:00Z
learned_in_session: 2026-05-21
learned_from_task: <what you were doing>
---
```

The body always starts with a banner that says "learned, not yet curated" — the routing agent flags this when it routes through, per rule #14.

→ Cross-references: `rules.md` #14 (learned skills are advisory); `retro` (the promotion / retirement loop); `references/extension-shapes.md` (when learned-skill is the right artefact vs reference vs view).
