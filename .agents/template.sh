#!/usr/bin/env bash
# template.sh — scaffold a fresh project from .agents/template/
#
# Run from this repo:
#   bash .agents/template.sh
#
# Copies the contents of .agents/template/ into a new directory's .agents/.
# The template is the source-of-truth for the minimal, generic analyst-agent
# framework: DuckDB-only, single-API, with the safety + accuracy + telemetry +
# feedback pillars intact.
#
# Default destination is one level above this repo (a sibling). Prompts can be
# answered or accepted with [enter].

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_dir="$script_dir/template"
source_repo="$(cd "$script_dir/.." && pwd)"
parent_of_repo="$(cd "$source_repo/.." && pwd)"

if [[ ! -d "$template_dir" ]]; then
  cat >&2 <<EOF
error: template directory missing at $template_dir

This script copies from .agents/template/ — that directory is the canonical
source of the minimal framework. If it's missing, you're running an older
version of this repo. Pull main, or copy the template tree from upstream.
EOF
  exit 64
fi

# --- Prompts ---------------------------------------------------------------

cat <<EOF

╭─────────────────────────────────────────────────────────────╮
│  Analyst agent framework — fresh template                   │
╰─────────────────────────────────────────────────────────────╯

This creates a new project pre-loaded with the framework's:
  - Safety: PII firewall (two-layer, three compliance modes)
  - Accuracy: F1–F8 failure modes, regression goldens, confidence labels
  - Self-learning: observe → retro loop, learned skills
  - Telemetry: Mixpanel workflow events
  - Feedback capture: structured friction notes

The project ships with a worked example (GitHub PR cycle time) that
exercises the entire fetch → land → view → regression loop.

Source:   $template_dir
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
dest="${dest/#\~/$HOME}"

if [[ -e "$dest" ]]; then
  echo "error: $dest already exists; pick a different destination or remove it first" >&2
  exit 64
fi

cat <<EOF

About to create:
  Destination:  $dest
  From source:  $template_dir

The new project will contain:
  $dest/
    .agents/         (framework — AGENTS.md, rules, skills, tools, references, GitHub example)
    .gitignore
    README.md        (next-steps guide)

EOF
read -r -p "Proceed? [Y/n]: " ok
[[ "${ok:-Y}" =~ ^[Yy] ]] || { echo "aborted."; exit 1; }

# --- Copy ------------------------------------------------------------------

mkdir -p "$dest"
cp -R "$template_dir/." "$dest/.agents/"

# Top-level .gitignore — copy from template (or generate if missing)
if [[ -f "$template_dir/.gitignore" ]]; then
  cp "$template_dir/.gitignore" "$dest/.gitignore"
fi

# --- README ----------------------------------------------------------------

source_url="$(git -C "$source_repo" config --get remote.origin.url 2>/dev/null || echo 'unknown')"
source_sha="$(git -C "$source_repo" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

cat > "$dest/README.md" <<EOF
# $project_name

Scaffolded from the analyst agent framework template.

## What this is

A minimal, generic analyst agent framework. Point it at one HTTP API (GitHub,
Jira, Zendesk, anything REST), land paginated data locally in DuckDB, build
typed analytical views, and pin regression goldens — with a PII firewall and
data-trust doctrine baked in.

The framework's five repeatable pillars:

1. **Safety** — two-layer PII firewall, three compliance modes.
2. **Accuracy** — F1–F8 failure modes, regression goldens, confidence labels.
3. **Self-learning** — observe → retro, learned skills.
4. **Telemetry** — Mixpanel workflow events from every tool call.
5. **Feedback capture** — structured friction notes; retro turns clusters into proposals.

## Next steps

1. **Set API credentials.**
   \`\`\`bash
   cp .agents/.env.example .agents/.env
   # edit: API_BASE_URL=https://api.github.com (or your API)
   # edit: API_TOKEN=<your token>
   source .agents/.env
   bash .agents/tools/whoami.sh --endpoint /user
   \`\`\`

2. **(First time on a new API)** Document the source.
   \`\`\`bash
   cat .agents/skills/discover-api.md   # follow the steps
   # Writes findings to .agents/references/sources/<name>.md
   \`\`\`
   The template ships \`references/sources/github.md\` as a worked example.

3. **Land your first slice.**
   \`\`\`bash
   bash .agents/tools/fetch-api.sh /repos/duckdb/duckdb/pulls \\
     --query "state=closed&per_page=100" --paginate link \\
     --source github --entity pulls --max-pages 3
   bash .agents/tools/land-to-duckdb.sh pulls --source github
   bash .agents/tools/profile-table.sh raw_github_pulls
   bash .agents/tools/duckdb-query.sh "SELECT count(*) FROM raw_github_pulls"
   \`\`\`

4. **Adapt PII metadata.**
   \`.agents/references/pii-columns.json\` ships with placeholder \`example_*\`
   tables plus the GitHub example. Replace / extend the tables with your real
   data source before any query touches sensitive columns. Until you do, the
   PII firewall only fires on those listed tables.

5. **Health check.**
   \`\`\`bash
   bash .agents/tools/framework-status.sh
   \`\`\`

## What's here

| Path | Contents |
|---|---|
| \`.agents/AGENTS.md\` | Entry point — persona, env vars, decision tree |
| \`.agents/rules.md\` | Hard rules (read once per session) |
| \`.agents/skills/\` | Workflow skills with frontmatter |
| \`.agents/skills/_TEMPLATE.md\` | Skill authoring guide |
| \`.agents/skills/learned/\` | Agent-emitted skills (empty) |
| \`.agents/tools/\` | Bash tools: fetch-api, land-to-duckdb, duckdb-query, view tools, regression tools, PII firewall, audit |
| \`.agents/references/\` | env-vars, PII safety, data trust, DuckDB SQL, output formats, examples |
| \`.agents/references/sources/github.md\` | Worked example source doc |
| \`.agents/references/pii-columns.json\` | PII metadata — adapt to your data source |
| \`.agents/data/raw/\`, \`.agents/data/db/\` | Landed JSONL + DuckDB (gitignored) |
| \`.agents/bi/bi_pr_cycle_time_view.md\` | Worked BI view sidecar |
| \`.agents/ops/ops_stale_prs_view.md\` | Worked ops queue sidecar |
| \`.agents/regressions/\` | Goldens (committed; per-API hash subfolder) |
| \`.agents/proposals/\` | retro outputs (committed) |

## Scaling up

Need a second source (e.g. GitHub + Jira)? The framework handles this
naturally — \`data/raw/github/\` and \`data/raw/jira/\` coexist; \`raw_github_*\`
and \`raw_jira_*\` tables coexist in \`main.duckdb\`. One \`bi_dev_lifecycle_view\`
can join across them. No new abstractions required; just point \`API_BASE_URL\`
at the second source for the second fetch.

## Source

Templated from $source_url ($source_sha).
EOF

# --- Optional git init -----------------------------------------------------

read -r -p "git init in $dest? [Y/n]: " do_git
if [[ "${do_git:-Y}" =~ ^[Yy] ]] && command -v git >/dev/null; then
  (cd "$dest" && git init -q && git add . && git commit -q -m "initial scaffold from .agents/template at $source_sha")
  echo "✓ git initialised; initial commit created"
fi

cat <<EOF

✓ New project created at: $dest

Get started:
  cd $dest
  cp .agents/.env.example .agents/.env
  # edit .agents/.env (API_BASE_URL, API_TOKEN)
  source .agents/.env
  bash .agents/tools/whoami.sh --endpoint /user
  bash .agents/tools/framework-status.sh

For the full quickstart, read .agents/AGENTS.md.
EOF
