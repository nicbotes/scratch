---
name: derive-jsonb-schema
description: Derive the key inventory of a JSONB column (policies.module, policies.charges, claims.module, policy_events.data, product_module_definitions.settings/.billing) by sampling Athena and cross-referencing the product module's declared schema. Use when you need to query a JSONB column and don't yet know the keys. Do NOT use when the keys are already in references/schema.md, when the relevant module has been derived earlier this session (check skills/learned/jsonb-schema-*), or when you only need a LIMIT 5 exploratory sample for human eyes.
---

# Skill: derive-jsonb-schema

Athena does not store the schema of a JSONB column — the keys are defined by the product module that wrote the row. This skill reconciles three sources:

| Source | Confidence | Where |
|---|---|---|
| Empirical sampling | medium (optional keys, version skew) | Athena |
| Declared in product-module source | high | Local `quote-schema.json` / `application-schema.json` if the module is checked out |
| Declared via Root API | high | `root-api.sh GET /v1/product-module-definitions/<id>` (endpoint exact form: confirm on first call) |

The output is a key inventory you persist as a **learned skill** so the next query routes around the derivation.

## Steps

1. **Sample empirically.** 50 non-null rows is enough for stable key enumeration:
   ```sql
   SELECT <col>
   FROM <table>
   WHERE environment = '$ROOT_ENV'
     AND <col> IS NOT NULL
   LIMIT 50
   ```
2. **Enumerate keys.** See `references/athena-sql.md` ("JSON-keys enumeration") for the Presto `map_keys` + `UNNEST` pattern. Fallback: pipe the sampled values through `jq -r 'keys[]' | sort -u`.
3. **Identify the product module on the rows.** The link from `policies` → `product_module_definitions` is not documented in the existing schema reference. Probe in order:
   - A column on the table: `policies.product_module_id` / `module_key` (run `athena-describe.sh policies` to see if one exists).
   - A key inside the JSON itself (e.g. `module.product_module_key`).
   - Ask the user. Whatever you discover, capture it in the learned skill so the next session skips this probe.
4. **Fetch the declared schema** if a product module is identified:
   - Local: if the workbench has cloned the product module (`/rp-clone`), read `quote-schema.json` and `application-schema.json` from the module directory.
   - Remote:
     ```bash
     bash .agents/tools/root-api.sh GET /v1/product-module-definitions/<id>
     ```
     Confirm the exact endpoint with the user on the first call (the public path may differ); record the correct path inside the learned skill body.
5. **Reconcile.** Emit a key inventory table:

   | key | type | confidence | null_rate | example |
   |---|---|---|---|---|
   | `cover_amount` | number | declared+sampled | 0% | `100000` |
   | `plan_type` | string | declared+sampled | 0% | `"premium"` |
   | `legacy_field` | string | sampled-only | 12% | `"x"` |

   Flag any sampled key that's missing from the declared schema (drift) and any declared key that's never present in samples (unused).
6. **Persist as a learned skill.** This is the whole point — next session should not re-sample:
   ```bash
   bash .agents/tools/learn-skill.sh jsonb-schema-policies-module-<module-key> \
     --description "Key inventory for policies.module on product module <key>. Use when querying policies.module fields for this module. Do NOT use for other modules — schemas diverge by module." \
     --body-file inventory.md \
     --from-task "<one-line description of the task that prompted this>"
   ```
7. **Cite the learned skill** in your reply: "I derived the JSONB schema and saved it as a learned skill — next time we query `policies.module` for this module, route directly there."

## Reference

Naming convention for the learned skill:
- `jsonb-schema-<table>-<column>-<module-key>` — fully specific, so multiple modules in the same org don't collide.
- Examples: `jsonb-schema-policies-module-funeral_v2`, `jsonb-schema-claims-module-life_v1`.

When the same column is reasonably stable across modules (e.g. `policy_events.data` shape per `event_type`), name by the discriminator instead: `jsonb-schema-policy-events-data-policy_lapsed`.

→ Cross-references:
- `references/athena-sql.md` — JSON-keys enumeration SQL.
- `references/extension-shapes.md` — when a learned skill is the right shape vs other options.
- `skills/observe.md` — `--kind success-pattern` on a particularly clean derivation accelerates retro promotion.
