# Root Platform CLI Agent Workbench

This repo contains a suite of skills for an agent to interact with the [Root Platform Workbench CLI](https://www.npmjs.com/package/@rootplatform/cli) (`rp`).

## Prerequisites

1. **CLI installed**: `npm install -g @rootplatform/cli`
2. **Auth file**: A `.root-auth` file in the product module directory:
   ```
   ROOT_API_KEY=sandbox_<your-key>
   ```
   Generate a key at: Root Dashboard → Workbench → API Keys → Create API Key
3. **Config file**: `.root-config.json` in the product module directory (created automatically by `rp init` or `rp clone`)

> All `rp` commands must be run from inside the product module directory.

## Available Skills

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

## Core Workflow

```
/rp-setup          ← confirm environment is ready
  ↓
edit code locally
  ↓
/rp-dev            ← diff + push new draft
  ↓
/rp-test           ← unit tests + sandbox smoke test
  ↓
/rp-publish        ← publish to live (requires explicit confirmation)
```

## Key Concepts

- A **product module** defines an insurance product: quote logic, application workflow, alteration rules, and document templates
- Code files are concatenated in order defined in `.root-config.json` — no `import`/`require` statements
- **Draft** = your working version (pushed but not live). **Published** = live, affects real policies
- Unit tests use [Chai](https://www.chaijs.com/) and live in `code/unit-tests/`
- Schemas (`quote-schema.json`, `application-schema.json`) configure input forms; generated from Joi validation via `/rp-generate`
