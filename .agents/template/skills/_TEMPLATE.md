# How to write a skill

A *skill* is a single markdown file under `.agents/skills/` that captures one reusable workflow: what to do, in what order, with which tool. The framework routes by **description**, so the frontmatter is the load-bearing surface — agents (and humans) decide whether to open the body based on that one line.

This file is a template, not a skill. Copy it, rename it, fill it in.

---

## Where it lives

| Path | Purpose | Who writes it |
|---|---|---|
| `.agents/skills/<name>.md` | **Canonical** skill — curated, stable, part of the framework | A human, or an agent during `retro` after a learned skill matures |
| `.agents/skills/learned/<name>.md` | **Learned** skill — agent-discovered mid-session, not yet curated | An agent, via `bash .agents/tools/learn-skill.sh` |

A canonical skill cannot share a name with a learned skill — `learn-skill.sh` rejects the collision. If you want to upgrade a learned skill to canonical, move it (don't fork it) and drop the "learned, not yet curated" banner.

Naming: kebab-case, lowercase alphanumeric plus `-` or `_`, no `.md` in the name itself (`profile-data`, not `profile-data.md`).

## Frontmatter

```yaml
---
name: <kebab-case slug, matches filename>
description: <one sentence describing WHAT it does>. Use when <one or two positive triggers — phrases an agent or user would actually say>. Do NOT use when <one or two negative triggers — adjacent skills that look similar but aren't this one>.
---
```

The description is the *routing prompt*. Optimise it for retrieval:

- **Lead with the verb** — "Execute…", "Profile…", "Configure…", "Pre-aggregate…"
- **Name the trigger phrases** an agent will actually encounter ("cycle time", "is the data good enough", "pull once, slice many times"). Generic words like "analyse" don't fire.
- **Always include a "Do NOT use when…" clause** that points at the adjacent skill it could be confused with. This is how the framework prevents two skills from both claiming the same intent.
- One sentence is too short. Three sentences is right. A paragraph is too long.

If you find yourself wanting to write a long description, that's a signal the skill is doing two things — split it.

## Body

```markdown
# Skill: <name>

<One short paragraph — the skill's reason for existing, or the mental model the agent should hold while running it. Skip this if the steps speak for themselves.>

## Steps

1. **<First action, named>.** <Concrete command, file, or decision.>
   ```bash
   bash .agents/tools/<tool>.sh <args>
   ```
2. **<Next action.>** <Inspect what; decide what.>
3. <Continue. Keep steps numbered, atomic, and grounded in a real command or a real decision. Don't pad with "consider…" or "think about…".>

## Reference

<Optional. Cross-links, gotchas, related tools, edge cases. If absent, drop the heading entirely — don't leave it empty.>

→ Next: `<adjacent-skill>` (when X), `<another-skill>` (when Y).
```

## Style rules

- **Numbered steps, not prose.** A skill the agent executes top-to-bottom beats a skill the agent has to interpret.
- **Show the command, don't describe it.** Code fences are how a skill earns its keep over a paragraph of advice.
- **No backstory in the body.** Why-it-exists belongs in `DESIGN.md`. The skill body is for the next caller, not the historian.
- **End with `→ Next:`** if the skill is a node in a workflow (most are). Name the adjacent skills with the conditions that route to them. This is how multi-step work composes without a central orchestrator.
- **Cite rules and references by path.** `rules.md #21`, `references/pii-safety.md` — never paraphrase a rule, link to it.

## Three failure modes to avoid

1. **Description too vague to fire.** "Helpful for data analysis" matches nothing and routes nowhere. Name the verbs and the trigger phrases.
2. **Two skills claiming the same intent.** If `run-query` and `analyst-workflow` both look right, one of them has the wrong "Do NOT use when…" clause. Fix the description, not the body.
3. **A skill that's actually two skills.** If the steps split cleanly into "first do A, then do B, then maybe C", you have a workflow — make A, B, C their own skills and write a thin orchestrator (`analyst-workflow.md` is the model) that points at them.

## Lifecycle

1. **Friction happens.** A workflow you ran ad-hoc would have been better as a named, reusable step.
2. **Capture it as a learned skill** mid-session (see `skills/learn-skill.md` for the workflow).
3. **Use it.** A learned skill earns its place by being called again.
4. **Promote it.** At `retro`, learned skills that have fired more than once become candidate canonical skills.
5. **Retire it.** Skills that stop firing get removed at retro. The framework is a curated set, not an archive.

See `skills/observe.md` and `skills/retro.md` for how friction becomes a proposed edit.
