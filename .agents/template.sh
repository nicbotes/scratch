#!/usr/bin/env bash
# template.sh — fresh-slate template generator for a new project
#
# Run from the cloned framework repo:
#   bash .agents/template.sh
#
# Produces a copy of the .agents/ framework alongside this repo, stripped
# of the team's local working artefacts (regression goldens, learned skills,
# concrete view docs, retro proposals). The new developer gets the
# conventions, rules, skills, tools, references, and schema — but starts
# with a blank `.agents/{bi,ops,regressions,proposals,skills/learned}/`.
#
# Default destination is one level above the cloned repo (sibling).
# Prompts can be answered or accepted with [enter].
#
# What's preserved (the framework):
#   .agents/AGENTS.md, rules.md, DESIGN.md, FUTURE.md
#   .agents/skills/*.md         (canonical skills, NOT skills/learned/)
#   .agents/tools/*.sh          (all framework tools — including this one)
#   .agents/references/*.md
#   .agents/references/pii-columns.json
#   .agents/references/schema.md  (shared schema across all Root clients)
#   .agents/.env.example
#   .gitignore
#
# What's stripped (team-specific):
#   .agents/regressions/<hash>/*.json   (per-org goldens)
#   .agents/skills/learned/*.md         (in-session-discovered skills)
#   .agents/bi/*.md  + bi/clients/*/    (concrete view docs)
#   .agents/ops/*.md + ops/clients/*/   (concrete ops queue docs)
#   .agents/proposals/*                 (retro proposal outputs)
#   .agents/sessions/, feedback/, evidence/, sensitive/  (gitignored anyway)
#   .agents/references/clients.txt      (reset to the example-only stub)
#   .agents/references/pii-columns.json  (reset to a domain-agnostic sample
#                                         so the framework's PII firewall
#                                         doesn't fire on the wrong columns
#                                         for non-insurance data sources)
#
# What's optional:
#   git init in the new directory (prompted)

set -euo pipefail

# Locate source: the .agents/ directory containing this script
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_agents="$script_dir"
source_repo="$(cd "$source_agents/.." && pwd)"
parent_of_repo="$(cd "$source_repo/.." && pwd)"

# --- Prompts ---------------------------------------------------------------

cat <<EOF

╭─────────────────────────────────────────────────────────────╮
│  .agents framework — fresh template                         │
╰─────────────────────────────────────────────────────────────╯

This creates a clean copy of the .agents framework, stripped of the
team's local artefacts (goldens, learned skills, view docs, proposals)
so you can start from a blank slate while keeping the conventions.

Source:   $source_agents
EOF

# Project name
default_name="agents-new-project"
read -r -p "Project name [$default_name]: " project_name
project_name="${project_name:-$default_name}"
if [[ ! "$project_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "error: project name must be [a-zA-Z0-9._-]+" >&2
  exit 64
fi

# Destination
default_dest="$parent_of_repo/$project_name"
read -r -p "Destination [$default_dest]: " dest
dest="${dest:-$default_dest}"
# Expand ~
dest="${dest/#\~/$HOME}"

if [[ -e "$dest" ]]; then
  echo "error: $dest already exists; pick a different destination or remove it first" >&2
  exit 64
fi

# Confirm before doing anything
cat <<EOF

About to create:
  Destination:  $dest
  From source:  $source_agents

The new project will contain:
  $dest/
    .agents/         (framework — rules, skills, tools, references)
    .gitignore
    README.md        (next-steps guide for the new developer)

It will NOT contain:
  - this team's regression goldens, learned skills, view docs, proposals
  - any .env, .root-auth, or other secrets
  - any sessions/feedback/evidence/sensitive runtime artefacts

EOF

read -r -p "Proceed? [Y/n]: " confirm
confirm="${confirm:-Y}"
if [[ ! "$confirm" =~ ^[Yy] ]]; then
  echo "aborted" >&2
  exit 1
fi

# --- Copy + strip ----------------------------------------------------------

mkdir -p "$dest"

# Copy the .agents/ tree
echo "Copying .agents/ framework..." >&2
cp -r "$source_agents" "$dest/.agents"

# Copy .gitignore from the repo root if it exists
if [[ -f "$source_repo/.gitignore" ]]; then
  cp "$source_repo/.gitignore" "$dest/.gitignore"
fi

# --- Strip team-specific artefacts ----------------------------------------

agents="$dest/.agents"

# Runtime artefacts (these shouldn't be in source-controlled artefact dirs
# but the .gitignore can lag the framework — be defensive).
rm -rf "$agents/sessions" "$agents/feedback" "$agents/evidence" "$agents/sensitive"

# Per-org regression goldens — keep the root dir + .gitkeep
echo "Stripping team-specific artefacts..." >&2
if [[ -d "$agents/regressions" ]]; then
  find "$agents/regressions" -mindepth 1 -name '*.json' -delete 2>/dev/null || true
  find "$agents/regressions" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  : > "$agents/regressions/.gitkeep"
fi

# Learned skills — preserve the dir, drop the contents
if [[ -d "$agents/skills/learned" ]]; then
  find "$agents/skills/learned" -mindepth 1 -name '*.md' -delete 2>/dev/null || true
  : > "$agents/skills/learned/.gitkeep"
fi

# Drop a skill-authoring template into skills/ so a fresh project knows
# the conventions without grepping a dozen existing skills. The leading
# underscore makes it sort last in directory listings and signals to
# readers that it isn't a fireable skill — it's a how-to.
cat > "$agents/skills/_TEMPLATE.md" <<'TEMPLATE'
# How to write a skill

A *skill* is a single markdown file under `.agents/skills/` that captures one
reusable workflow: what to do, in what order, with which tool. The framework
routes by **description**, so the frontmatter is the load-bearing surface —
agents (and humans) decide whether to open the body based on that one line.

This file is a template, not a skill. Copy it, rename it, fill it in.

---

## Where it lives

| Path | Purpose | Who writes it |
|---|---|---|
| `.agents/skills/<name>.md` | **Canonical** skill — curated, stable, part of the framework | A human, or an agent during `retro` after a learned skill matures |
| `.agents/skills/learned/<name>.md` | **Learned** skill — agent-discovered mid-session, not yet curated | An agent, via `bash .agents/tools/learn-skill.sh` |

A canonical skill cannot share a name with a learned skill — `learn-skill.sh`
rejects the collision. If you want to upgrade a learned skill to canonical,
move it (don't fork it) and drop the "learned, not yet curated" banner.

Naming: kebab-case, lowercase alphanumeric plus `-` or `_`, no `.md` in the
name itself (`profile-data`, not `profile-data.md`).

## Frontmatter

```yaml
---
name: <kebab-case slug, matches filename>
description: <one sentence describing WHAT it does>. Use when <one or two positive triggers — phrases an agent or user would actually say>. Do NOT use when <one or two negative triggers — adjacent skills that look similar but aren't this one>.
---
```

The description is the *routing prompt*. Optimise it for retrieval:

- **Lead with the verb** — "Execute…", "Profile…", "Configure…", "Pre-aggregate…"
- **Name the trigger phrases** an agent will actually encounter ("cohort retention", "is the data good enough", "pull once, slice many times"). Generic words like "analyse" don't fire.
- **Always include a "Do NOT use when…" clause** that points at the adjacent skill it could be confused with. This is how the framework prevents two skills from both claiming the same intent.
- One sentence is too short. Three sentences is right. A paragraph is too long.

If you find yourself wanting to write a long description, that's a signal the
skill is doing two things — split it.

## Body

```markdown
# Skill: <name>

<One short paragraph — the skill's reason for existing, or the mental model
the agent should hold while running it. Skip this if the steps speak for
themselves.>

## Steps

1. **<First action, named>.** <Concrete command, file, or decision.>
   ```bash
   bash .agents/tools/<tool>.sh <args>
   ```
2. **<Next action.>** <Inspect what; decide what.>
3. <Continue. Keep steps numbered, atomic, and grounded in a real command
   or a real decision. Don't pad with "consider…" or "think about…".>

## Reference

<Optional. Cross-links, gotchas, related tools, edge cases. If absent, drop
the heading entirely — don't leave it empty.>

→ Next: `<adjacent-skill>` (when X), `<another-skill>` (when Y).
```

## Style rules

- **Numbered steps, not prose.** A skill the agent executes top-to-bottom
  beats a skill the agent has to interpret.
- **Show the command, don't describe it.** Code fences are how a skill
  earns its keep over a paragraph of advice.
- **No backstory in the body.** Why-it-exists belongs in `DESIGN.md`. The
  skill body is for the next caller, not the historian.
- **End with `→ Next:`** if the skill is a node in a workflow (most are).
  Name the adjacent skills with the conditions that route to them. This
  is how multi-step work composes without a central orchestrator.
- **Cite rules and references by path.** `rules.md #24`, `references/pii-safety.md`
  — never paraphrase a rule, link to it.

## Three failure modes to avoid

1. **Description too vague to fire.** "Helpful for data analysis" matches
   nothing and routes nowhere. Name the verbs and the trigger phrases.
2. **Two skills claiming the same intent.** If `run-query` and `analyst-workflow`
   both look right, one of them has the wrong "Do NOT use when…" clause.
   Fix the description, not the body.
3. **A skill that's actually two skills.** If the steps split cleanly into
   "first do A, then do B, then maybe C", you have a workflow — make A, B, C
   their own skills and write a thin orchestrator (`analyst-workflow.md` is
   the model) that points at them.

## Lifecycle

1. **Friction happens.** A workflow you ran ad-hoc would have been better
   as a named, reusable step.
2. **Capture it as a learned skill** mid-session:
   ```bash
   bash .agents/tools/learn-skill.sh <name> \
     --description "<draft frontmatter description>" \
     --body-file /tmp/draft.md \
     --from-task "<what you were doing when you noticed>"
   ```
3. **Use it.** A learned skill earns its place by being called again.
4. **Promote it.** At `retro`, if the learned skill has fired (or would have)
   in more than one task, move it from `skills/learned/` to `skills/`,
   strip the "learned" banner, polish the frontmatter, and link it from
   any orchestrator skill that should route to it.
5. **Retire it.** Skills that stop firing get removed at retro. The framework
   is a curated set, not an archive.

See `skills/observe.md` and `skills/retro.md` for how friction becomes a
proposed edit, and `tools/learn-skill.sh` for the persistence path.
TEMPLATE

# BI view docs — drop concrete docs, keep folder structure
if [[ -d "$agents/bi" ]]; then
  find "$agents/bi" -mindepth 1 -maxdepth 1 -name '*.md' -delete 2>/dev/null || true
  if [[ -d "$agents/bi/clients" ]]; then
    find "$agents/bi/clients" -mindepth 1 -name '*.md' -delete 2>/dev/null || true
    find "$agents/bi/clients" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    : > "$agents/bi/clients/.gitkeep"
  fi
  : > "$agents/bi/.gitkeep"
fi

# Ops view docs — same shape as BI
if [[ -d "$agents/ops" ]]; then
  find "$agents/ops" -mindepth 1 -maxdepth 1 -name '*.md' -delete 2>/dev/null || true
  if [[ -d "$agents/ops/clients" ]]; then
    find "$agents/ops/clients" -mindepth 1 -name '*.md' -delete 2>/dev/null || true
    find "$agents/ops/clients" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    : > "$agents/ops/clients/.gitkeep"
  fi
  : > "$agents/ops/.gitkeep"
fi

# Proposals — drop contents, preserve dir
if [[ -d "$agents/proposals" ]]; then
  find "$agents/proposals" -mindepth 1 -name '*.md' -delete 2>/dev/null || true
  find "$agents/proposals" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  : > "$agents/proposals/.gitkeep"
fi

# Drop the template tool itself from the copy — the new project shouldn't
# re-template from itself. Adding it back later is a one-line commit.
rm -f "$agents/template.sh"

# Reset the clients registry to its stub form
cat > "$agents/references/clients.txt" <<'STUB'
# Client slug registry — list one slug per line, optional inline note after #.
# Slugs must match ^[a-z][a-z0-9-]*$ (kebab-case, starts with a letter).
#
# save-view.sh --client <slug> warns when the supplied slug isn't here.
#
# Example entries (uncomment when real clients exist):
#   acme         # Acme Insurance — quota-share reinsurance, 30% ceded
#   globalcorp   # GlobalCorp Re — XOL treaty, attachment 100k
STUB

# Reset references/pii-columns.json to a domain-agnostic sample. The
# in-tree version is insurance-specific (policyholders, claims, modules);
# a new project might be templating onto Zendesk, GitHub, Mixpanel,
# Stripe, or anything else — the wrong tags would either fire false-
# positives or miss real PII. The sample below demonstrates the three
# sensitivity buckets with placeholder tables; the new developer adapts
# to their actual schema. See references/pii-safety.md for the policy.
cat > "$agents/references/pii-columns.json" <<'JSON'
{
  "_comment": "PII / restricted sensitivity tags per <table>.<column>. The SQL firewall in tools/_lib.sh::scan_sql_for_sensitivity reads this to gate sensitive queries (rules.md #26-#28).",
  "_adapt_for_your_data_source": "This is a SAMPLE — replace the example tables below with your own data source's tables and columns. Until you do, the firewall will only fire on the example_* tables (which presumably don't exist in your workgroup), so PII will pass through ungated. Adapt this file BEFORE running queries against real data.",
  "_examples_by_domain": {
    "zendesk":   ["users.email (pii)", "users.phone (pii)", "tickets.requester_email (pii)", "tickets.description (json_sensitive — free text may contain PII)"],
    "github":    ["users.email (pii)", "commits.author_email (pii)", "issues.body (json_sensitive — free text)"],
    "mixpanel":  ["events.distinct_id (pii)", "events.email (pii)", "events.properties (json_sensitive)", "events.ip_address (pii)"],
    "stripe":    ["customers.email (pii)", "customers.name (pii)", "charges.card.last4 (restricted)", "charges.metadata (json_sensitive)"],
    "insurance": ["policyholders.first_name (pii)", "policyholders.identification_number (pii)", "policies.module (json_sensitive)", "payment_methods.account_number (restricted)"]
  },
  "_sensitivity_values": {
    "pii":            "Directly identifies a person — names, emails, IDs, phone, address, DOB",
    "restricted":     "Sensitive non-identifying — account numbers, medical answers, behavioural, financial",
    "json_sensitive": "JSON-bearing column whose contents may contain PII — JSON_EXTRACT is gated until derive-jsonb-schema tags safe keys"
  },
  "tables": {
    "example_users": {
      "columns": {
        "email":      { "sensitivity": "pii" },
        "full_name":  { "sensitivity": "pii" },
        "phone":      { "sensitivity": "pii" },
        "profile":    { "sensitivity": "json_sensitive" }
      }
    },
    "example_events": {
      "columns": {
        "distinct_id": { "sensitivity": "pii" },
        "ip_address":  { "sensitivity": "pii" },
        "properties":  { "sensitivity": "json_sensitive" }
      }
    },
    "example_payments": {
      "columns": {
        "account_number": { "sensitivity": "restricted" },
        "card_last4":     { "sensitivity": "restricted" },
        "metadata":       { "sensitivity": "json_sensitive" }
      }
    }
  }
}
JSON

# Strip any cross-org config example file remnants
rm -f "$agents/orgs.csv" "$agents/.env" "$dest/.root-auth"

# --- Generate README at destination ---------------------------------------

source_url="$(git -C "$source_repo" config --get remote.origin.url 2>/dev/null || echo 'unknown')"
source_sha="$(git -C "$source_repo" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
source_branch="$(git -C "$source_repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"

cat > "$dest/README.md" <<EOF
# $project_name

A new project initialised from the \`.agents\` framework template.

## Next steps

1. **Set your Root Data Adapter credentials.** Get them from Root Dashboard →
   Data Management → Data Adapter → Generate Access Key.

   \`\`\`bash
   cp .agents/.env.example .agents/.env
   # edit .agents/.env with your AWS keys + ROOT_ORG_ID + ROOT_ATHENA_S3_BUCKET
   source .agents/.env
   \`\`\`

2. **Confirm you can reach Athena:**

   \`\`\`bash
   bash .agents/tools/whoami.sh
   \`\`\`

   You should see your org name and ID.

3. **Adapt to your data source.** The framework was built against an
   AWS Athena / Root insurance schema, but the *patterns* (skills, rules,
   PII firewall, regression goldens, pre-aggregate-locally) apply to any
   structured data source. Three files need adapting before you query
   real data:

   - \`.agents/references/pii-columns.json\` — **SAMPLE.** Replace
     \`example_users\` / \`example_events\` / \`example_payments\` with
     your actual tables and columns. Until you do, the firewall won't
     gate the right columns. See \`pii-safety.md\` for the policy.
   - \`.agents/references/schema.md\` — currently a 1100-line Athena data
     dictionary specific to Root insurance. If your data source is
     different, regenerate it (the file header documents the pattern)
     or replace with your own. The framework's tools that DESCRIBE
     tables (\`profile-table.sh\`, \`glue-describe.sh\`) work
     independently of this doc.
   - \`.agents/references/examples.md\` — recipe queries for the
     insurance schema. Adapt or replace.

4. **Get oriented — read these in order:**

   - \`.agents/AGENTS.md\` — entry point: persona, env vars, decision tree
   - \`.agents/rules.md\` — 28 hard rules. Read once per session.
   - \`.agents/DESIGN.md\` — design history (why it's shaped the way it is)
   - \`.agents/FUTURE.md\` — menu of unbuilt ideas; pull when signal emerges

5. **Check the framework's health:**

   \`\`\`bash
   bash .agents/tools/framework-status.sh
   \`\`\`

   No regressions, no learned skills, no view docs — you're starting fresh.

## What's here

| Path | Contents |
|---|---|
| \`.agents/AGENTS.md\` | Framework entry point |
| \`.agents/rules.md\` | Hard rules |
| \`.agents/skills/\` | Workflow skills with YAML frontmatter (canonical layer) |
| \`.agents/skills/_TEMPLATE.md\` | How to author a new skill (frontmatter, steps, style, lifecycle) |
| \`.agents/skills/learned/\` | (empty) Agent-emitted skills accumulate here |
| \`.agents/tools/\` | Bash tools wrapping AWS CLI / DuckDB / Root API |
| \`.agents/references/\` | Schema, conventions, PII rules, decision matrices |
| \`.agents/regressions/\` | (empty) Deterministic goldens per org |
| \`.agents/bi/\`, \`.agents/ops/\` | (empty) Per-view documentation |
| \`.agents/proposals/\` | (empty) Retro proposal outputs |

## Source

Templated from \`$source_url\` at branch \`$source_branch\` (\`$source_sha\`).

The framework convention pulls from \`FUTURE.md\` when real signal emerges
— don't burn through the menu top-to-bottom. Use the \`observe\` skill to
log friction in real time; run \`retro\` at end of session to turn it into
proposed edits.
EOF

# --- Optional: git init ---------------------------------------------------

echo
read -r -p "Initialise a git repo in $dest? [Y/n]: " do_git
do_git="${do_git:-Y}"
if [[ "$do_git" =~ ^[Yy] ]]; then
  if command -v git >/dev/null; then
    (cd "$dest" && git init -q && git add . && git commit -q -m "initial template from $source_branch@$source_sha")
    echo "✓ git repo initialised with an initial commit" >&2
  else
    echo "warning: git not on PATH; skipping git init" >&2
  fi
fi

# --- Done -----------------------------------------------------------------

cat <<EOF

✓ New project created at: $dest

Get started:
  cd $dest
  cp .agents/.env.example .agents/.env
  # edit .agents/.env
  source .agents/.env
  bash .agents/tools/whoami.sh

EOF
