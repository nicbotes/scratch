# Dev Skill: Git Workflow Setup

Set up the git branching model, GitHub Actions CI/CD, and team access for a product module repository.

## Steps

1. Read the current `.gitignore` — create one if missing
2. Ensure `.root-auth` is listed in `.gitignore` (never commit API keys)
3. Create `.github/workflows/push-to-root.yml` — see reference below
4. Add `ROOT_API_KEY` as a secret in GitHub repo settings (Settings → Secrets → Actions)
5. Confirm the `main` branch protection rule requires PR review before merge
6. Brief the team on branch naming: `<author-name>/<description>`
7. Each team member creates their own `.root-auth` locally with their personal API key

→ Use `/rp-dev` for day-to-day push workflow on feature branches

---

## Reference: how versioning maps to git

| Action | Root effect |
|---|---|
| `rp push` on any branch | New **minor draft** version |
| Merge to `main` → GitHub Action | `rp push -f` → new draft auto-deployed |
| `rp publish` | New **major live** version |

Main branch always mirrors the latest live version. Never push directly to main.

## Reference: GitHub Actions workflow

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

## Reference: .gitignore entries

```
.root-auth
sandbox/
node_modules/
*.pdf
```

## Reference: branch naming convention

```
<author-name>/<short-description>

jane/update-premium-rates
dev/add-beneficiary-alteration
nick/fix-lapse-logic
```

## Reference: team key management

- Each team member has their own personal API key in their local `.root-auth`
- The GitHub Action uses a **deployment key** (write access) stored as a repo secret
- Consider issuing **read-only keys** to junior team members to prevent accidental direct pushes to Root
- Generate keys: Root Dashboard → Workbench → API Keys → Create API Key
