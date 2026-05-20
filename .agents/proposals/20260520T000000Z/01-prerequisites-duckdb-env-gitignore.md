# Proposal 01 — Prerequisites: duckdb + `.env` workflow

**Source feedback notes (`feedback/2026-05-19.jsonl`):**
- `2026-05-19T07:29:00Z` (rule-missing) — duckdb required by `tools/duckdb-query.sh` + rules.md #24, but not listed in Prerequisites
- `2026-05-19T07:29:10Z` (progressive-disclosure) — `references/env-vars.md` walkthrough only covers AWS creds, no "local tooling" section
- `2026-05-19T07:36:13Z` (rule-missing, ×2) — `.env.example` → `.env` → `source .env` workflow missing from AGENTS.md; `.env` should be in `.gitignore`

## Reason

First-session agents currently hit a missing-binary error halfway through any pre-aggregate workflow (rules.md #24 routes them to `duckdb-query.sh`, which calls `duckdb`). The fix is documentation, not code: list the binary alongside `aws` and document the `.env` → `source` flow so the five env vars don't need to be re-exported every session.

## Current state

`.gitignore` (repo root) already lists `.env` alongside `.root-auth` — **no change needed**, just verification.

`.env.example` already exists at `.agents/.env.example` and demonstrates the `export` shape.

What's missing is the **discoverability** of both from the Prerequisites section of `AGENTS.md` and the env-vars walkthrough.

## Proposed changes

### Change 1: `.agents/AGENTS.md` (Prerequisites section, around line 7-25)

Replace:

```markdown
## Prerequisites

`aws` CLI on `$PATH` (v2). Credentials and connection details come from Root Dashboard → Data Management → Data Adapter → Generate Access Key.

| Env var | Required | Purpose |
| ... existing table ... |
```

With:

```markdown
## Prerequisites

Two binaries on `$PATH`:

- `aws` CLI v2 — Athena queries (`brew install awscli`)
- `duckdb` — local pre-aggregation (`brew install duckdb`) — required by `tools/duckdb-query.sh` and rules.md #24

Credentials and connection details come from Root Dashboard → Data Management → Data Adapter → Generate Access Key.

### Fastest setup

```bash
cp .agents/.env.example .agents/.env   # template is committed
# edit .agents/.env with the five values from the Generate Access Key modal
source .agents/.env
bash .agents/tools/whoami.sh           # confirms the org you're now in
```

`.env` is gitignored alongside `.root-auth`. Sourcing it once per shell beats re-exporting five vars every session.

| Env var | Required | Purpose |
| ... existing table ... |
```

### Change 2: `.agents/references/env-vars.md` (new subsection between "Required" table and "Walkthrough")

Insert before line 28 (`## Walkthrough`):

```markdown
## Local tooling

Two binaries are required on `$PATH`:

| Tool | Install | Why |
|---|---|---|
| `aws` CLI v2 | `brew install awscli` | Every tool under `.agents/tools/` shells out to it |
| `duckdb` | `brew install duckdb` | Local pre-aggregation (`tools/duckdb-query.sh`, rules.md #24) |

`python3` is also assumed present (macOS ships it) — used by `--format json/jsonl/tsv` in `athena-query.sh` and by the timing fallback in `duckdb-query.sh`.
```

### Change 3: confirmation only — `.gitignore` already includes `.env`

No change required. The verification step in the apply PR's smoke test is to run `git check-ignore -v .env` from the repo root and confirm a positive match.

## Test

After applying:

```bash
# Fresh clone behaviour
git clone <repo> /tmp/scratch && cd /tmp/scratch
cp .agents/.env.example .agents/.env
# fill in five values, then:
source .agents/.env
bash .agents/tools/whoami.sh           # should succeed
which duckdb >/dev/null || brew install duckdb   # AGENTS.md tells you this
bash .agents/tools/duckdb-query.sh "SELECT 1"    # confirms binary is wired
```

Acceptance: a first-session agent following only `AGENTS.md` Prerequisites can run `whoami.sh` and `duckdb-query.sh "SELECT 1"` without re-reading any other file.
