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

3. **Get oriented — read these in order:**

   - \`.agents/AGENTS.md\` — entry point: persona, env vars, decision tree
   - \`.agents/rules.md\` — 28 hard rules. Read once per session.
   - \`.agents/DESIGN.md\` — design history (why it's shaped the way it is)
   - \`.agents/FUTURE.md\` — menu of unbuilt ideas; pull when signal emerges

4. **Check the framework's health:**

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
