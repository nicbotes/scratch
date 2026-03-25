# Root Platform CLI Agent Workbench

This repo contains a suite of skills for an agent to interact with the [Root Platform Workbench CLI](https://www.npmjs.com/package/@rootplatform/cli) (`rp`) and to develop Root Platform product modules.

## Prerequisites

1. **CLI installed**: `npm install -g @rootplatform/cli`
2. **Auth file**: A `.root-auth` file in the product module directory:
   ```
   ROOT_API_KEY=sandbox_<your-key>
   ```
   Generate a key at: Root Dashboard → Workbench → API Keys → Create API Key
3. **Config file**: `.root-config.json` in the product module directory (created automatically by `rp init` or `rp clone`)

> All `rp` commands must be run from inside the product module directory.

## CLI Workflow Skills

These skills wrap `rp` CLI commands for the full push/test/publish lifecycle.

| Skill | Purpose |
|---|---|
| `/rp-setup` | Verify CLI, auth, and config are ready |
| `/rp-init` | Scaffold a new product module on Root |
| `/rp-clone` | Clone an existing module for local development |
| `/rp-dev` | Show diff then push a new draft |
| `/rp-test` | Run unit tests and optionally create a sandbox policy |
| `/rp-generate` | Generate schemas and API docs from Joi validation |
| `/rp-render` | Render document templates to PDF |
| `/rp-logs` | View and summarise execution logs |
| `/rp-publish` | Publish current draft to live (gated) |

## Dev Skills

These skills guide implementation of the core code hooks and configuration that make up a product module.

| Skill | Purpose |
|---|---|
| `/dev-quote-hook` | Implement `validateQuoteRequest` and `getQuote` |
| `/dev-application-hook` | Implement `validateApplicationRequest` and `getApplication` |
| `/dev-policy-hook` | Implement `getPolicy` (called at policy issuance) |
| `/dev-alteration-hook` | Implement alteration hooks for post-issuance amendments |
| `/dev-reactivation-hook` | Implement `getReactivationOptions` for lapsed/cancelled policies |
| `/dev-lifecycle-hooks` | Implement lifecycle hooks and scheduled functions with actions |
| `/dev-schema` | Create/update quote, application, and alteration JSON schemas |
| `/dev-documents` | Build Handlebars HTML document templates (policy schedule, terms) |
| `/dev-git-workflow` | Set up git branching, GitHub Actions CI/CD, and team collaboration |

## Core Workflow

```
/rp-setup              ← confirm environment is ready
  ↓
/rp-clone or /rp-init  ← get the product module locally
  ↓
/dev-quote-hook        ← implement rating and quoting logic
/dev-application-hook  ← implement application processing
/dev-policy-hook       ← implement policy issuance logic
/dev-alteration-hook   ← implement post-issuance amendments
/dev-lifecycle-hooks   ← implement event-driven and scheduled logic
/dev-schema            ← generate or update input form schemas
/dev-documents         ← build policy schedule and terms templates
  ↓
/rp-dev                ← diff + push new draft
  ↓
/rp-test               ← unit tests + sandbox smoke test
  ↓
/rp-publish            ← publish to live (requires explicit confirmation)
```

## Key Concepts

- A **product module** defines an insurance product: quote logic, application workflow, alteration rules, lifecycle hooks, and document templates
- Code files are concatenated in order defined in `.root-config.json` under `codeFileOrder` — no `import`/`require` statements
- **Draft** = your working version (pushed but not live). **Published** = live, affects real policies
- Unit tests use [Chai](https://www.chaijs.com/) and live in `code/unit-tests/`
- Schemas (`quote-schema.json`, `application-schema.json`) configure input forms; generated from Joi validation via `/rp-generate`
- Hooks return **action arrays** (`update_policy`, `cancel_policy`, `send_notification`, etc.) — they describe what to do, the platform executes it
- Document templates are HTML + Handlebars; Root converts them to PDF on demand
- **Main branch = live version**: merge to main triggers `rp push -f` via GitHub Actions; see `/dev-git-workflow`
