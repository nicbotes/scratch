# Dev Skill: Alteration Hooks

Implement alteration hooks — allowing policyholders to amend their policy post-issuance (e.g. change cover amount, update beneficiaries). Each amendment type is a separate alteration hook identified by its `key`.

## Steps

1. Read existing alteration hook files in `code/` and `workflows/alteration-hooks/` directory (if any)
2. Identify what policy amendments this product supports — each gets a unique `key` string registered in `.root-config.json` `alterationHooks` array
3. Implement `validateAlterationPackageRequest({ alteration_hook_key, data, policy, policyholder })` — dispatch to a Joi schema per key
4. Implement `getAlteration({ alteration_hook_key, data, policy, policyholder })` — return the proposed updated policy state per key
5. Implement `applyAlteration({ alteration_hook_key, data, policy, policyholder })` — return an `AlteredPolicy` (and optionally actions)
6. In `getAlteration`, always spread `policy.module` and override only changed fields — the returned `module` fully replaces the existing one on confirmation
7. If creating new files, add them to `codeFileOrder` in `.root-config.json`
8. Create schema files at `workflows/alteration-hooks/<key>.json` for each hook key, or run `/rp-generate -w alterations`
9. Write unit tests for each alteration type
10. Run `/rp-dev` to push the draft

→ **CRITICAL**: Alteration schema files are **flat files** at `workflows/alteration-hooks/<key>.json` — NOT in subdirectories. Example: `workflows/alteration-hooks/update_cover.json`, not `workflows/alteration-hooks/update_cover/alteration-schema.json`.

→ **CRITICAL**: Schema files must contain a JSON **array**, not a JSON Schema object. Start with `[]` and use `rp generate` to populate.

→ Run `/rp-test` to verify

---

## Reference: function signatures

All three alteration functions receive a **single destructured object**:

```js
// All three functions have the same parameter shape:
function({ alteration_hook_key, data, policy, policyholder })
```

| Parameter | Type | Description |
|---|---|---|
| `alteration_hook_key` | string | The key of the alteration hook being invoked |
| `data` | object | The alteration request data submitted by the user |
| `policy` | object | The current policy object |
| `policyholder` | object | The policyholder object |

---

## Reference: validateAlterationPackageRequest

Validates the incoming alteration data. Throw an error to reject. Return validated data to proceed.

```js
const validateAlterationPackageRequest = ({ alteration_hook_key, data, policy, policyholder }) => {
  const schemas = {
    update_cover: Joi.object({
      new_cover_amount: Joi.number().min(10000).max(5000000).required(),
    }),
    update_beneficiaries: Joi.object({
      beneficiaries: Joi.array().items(
        Joi.object({
          first_name: Joi.string().required(),
          last_name: Joi.string().required(),
          percentage: Joi.number().integer().min(1).max(100).required(),
        })
      ).min(1).required(),
    }),
  };
  const schema = schemas[alteration_hook_key];
  if (!schema) throw new Error(`Unknown alteration type: ${alteration_hook_key}`);
  // Joi v11 — use Joi.validate(), not schema.validate()
  const result = Joi.validate(data, schema, { abortEarly: false });
  if (result.error) throw new Error(result.error.details[0].message);
  return result.value;
};
```

## Reference: getAlteration return shape

Returns an `AlterationPackage` describing the proposed policy state. This is shown to the user for confirmation before `applyAlteration` is called.

| Field | Type | Notes |
|---|---|---|
| `alteration_hook_key` | string | Must match the key passed in |
| `package_name` | string | Policy package label |
| `sum_assured` | number | New or unchanged cover amount |
| `monthly_premium` | number | New or unchanged premium |
| `module` | object | Complete replacement for `policy.module` — spread existing, override changed |
| `input_data` | object | (optional) Pass through validated data for use in `applyAlteration` |

```js
const getAlteration = ({ alteration_hook_key, data, policy, policyholder }) => {
  if (alteration_hook_key === 'update_cover') {
    const new_premium = calculatePremium(data.new_cover_amount, policy.module.age_at_inception);
    return {
      alteration_hook_key,
      package_name: policy.package_name,
      sum_assured: data.new_cover_amount,
      monthly_premium: new_premium,
      module: { ...policy.module, cover_amount: data.new_cover_amount },
    };
  }
};
```

## Reference: applyAlteration

Called when the user **confirms** the alteration proposed by `getAlteration`. Returns an `AlteredPolicy` object.

→ **CRITICAL**: `applyAlteration` returns an `AlteredPolicy` — this is the final policy state. It does **NOT** return an array of actions. If you need to trigger side-effects (notifications, cancellations, etc.), use the `afterAlterationPackageApplied` lifecycle hook instead, or include actions alongside the `AlteredPolicy` in the return.

```js
const applyAlteration = ({ alteration_hook_key, data, policy, policyholder }) => {
  // data here is the alteration_package from getAlteration (including module, sum_assured, etc.)
  return new AlteredPolicy({
    package_name: data.package_name,
    sum_assured: data.sum_assured,
    monthly_premium: data.monthly_premium,
    module: data.module,
  });
};
```

For alteration types that need platform actions (e.g. activate a pending policy, cancel for replacement):

```js
const applyAlteration = ({ alteration_hook_key, data, policy, policyholder }) => {
  if (alteration_hook_key === 'activate_policy') {
    return [
      new AlteredPolicy({ ...data }),
      { type: 'activate_policy' },
    ];
  }
  return new AlteredPolicy({ ...data });
};
```
