# Dev Skill: Git Workflow Setup

Set up or explain the git workflow for this product module repository. Root Platform follows a specific git branching model that ties directly into the Root versioning system.

## How Versioning Works

| Git action | Root versioning effect |
|---|---|
| `rp push` (any branch) | Creates a new **minor draft version** |
| `rp publish` | Creates a new **major live version** |
| Merge to `main` | Triggers GitHub Action → `rp push -f` → new draft |

- **Main branch always mirrors the latest major (live) version**
- Do not push directly to `main` — use feature branches and PRs

## Branch Naming Convention

```
<author-name>/<short-description>

Examples:
  jane/update-premium-rates
  dev/add-beneficiary-alteration
  nick/fix-lifecycle-hook-lapse-logic
```

## Standard Workflow

```
1. Pull latest main
   git checkout main && git pull origin main

2. Create feature branch
   git checkout -b <author>/<description>

3. Edit code locally
   (make your changes)

4. Push draft to Root for testing
   rp push

5. Run tests
   rp test

6. Commit and push branch
   git add <files>
   git commit -m "feat: describe what changed"
   git push -u origin <branch-name>

7. Open a PR → get review → merge to main

8. GitHub Action fires on main merge → rp push -f → new draft auto-deployed
```

## GitHub Actions Setup

Add a GitHub Action to auto-push to Root on every merge to `main`:

**`.github/workflows/push-to-root.yml`:**
```yaml
name: Push to Root Platform

on:
  push:
    branches:
      - main

jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Root CLI
        run: npm install -g @rootplatform/cli

      - name: Create .root-auth
        run: echo "ROOT_API_KEY=${{ secrets.ROOT_API_KEY }}" > .root-auth

      - name: Push to Root
        run: rp push -f
```

**GitHub Secret to add:**
- Name: `ROOT_API_KEY`
- Value: your Root Platform API key (from Root Dashboard → Workbench → API Keys)

## Team Member Setup

Each team member needs their own `.root-auth` file locally:

```
ROOT_API_KEY=sandbox_<their-personal-key>
```

- Generate personal API keys: Root Dashboard → Workbench → API Keys → Create API Key
- `.root-auth` is **gitignored** — never commit it
- Consider issuing **read-only API keys** to prevent accidental direct pushes to Root
- The GitHub Action uses a **deployment key** (write access) stored as a secret

## .gitignore Recommended Entries

```
.root-auth
sandbox/
node_modules/
*.pdf
```

## Steps

1. Read the current `.gitignore` (create one if missing)
2. Ensure `.root-auth` is gitignored
3. Check if `.github/workflows/` exists — create if not
4. Create or update the `push-to-root.yml` GitHub Action
5. Document branch naming convention in `README.md` or `CONTRIBUTING.md`
6. Confirm the `ROOT_API_KEY` secret is added in GitHub repo settings
7. Verify main branch protection rules are in place (require PR review before merge)
