# Dev Skill: Alteration Hooks

Implement alteration hooks — allowing policyholders to amend their policy post-issuance (e.g. change cover amount, update beneficiaries). Each amendment type is a separate alteration hook type.

## Steps

1. Read existing alteration hook files in `code/` and `alteration-hooks/` directory (if any)
2. Identify what policy amendments this product supports — each gets a unique `alteration_hook_type` string
3. Implement `validateAlterationPackageRequest(data, alteration_hook_type)` — dispatch to a Joi schema per type
4. Implement `getAlteration(data, alteration_hook_type, policy, policyholder)` — return the proposed updated policy state per type
5. In `getAlteration`, always spread `policy.module` and override only changed fields — the returned `module` fully replaces the existing one on confirmation
6. If creating new files, add them to `codeFileOrder` in `.root-config.json`
7. Create or update `alteration-hooks/<type>/alteration-schema.json` for each type, or run `/rp-generate -w alterations`
8. Write unit tests for each alteration type
9. Run `/rp-dev` to push the draft

→ Run `/rp-test` to verify

---

## Reference: validateAlterationPackageRequest

```js
const validateAlterationPackageRequest = (data, alteration_hook_type) => {
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
  const schema = schemas[alteration_hook_type];
  if (!schema) throw new Error(`Unknown alteration type: ${alteration_hook_type}`);
  const { error, value } = schema.validate(data);
  if (error) throw new Error(error.details[0].message);
  return value;
};
```

## Reference: getAlteration return shape

| Field | Type | Notes |
|---|---|---|
| `alteration_hook_type` | string | Must match the type passed in |
| `package_name` | string | Policy package label |
| `sum_assured` | number | New or unchanged cover amount |
| `monthly_premium` | number | New or unchanged premium |
| `module` | object | Complete replacement for `policy.module` — spread existing, override changed |

```js
const getAlteration = (data, alteration_hook_type, policy, policyholder) => {
  if (alteration_hook_type === 'update_cover') {
    const new_premium = calculatePremium(data.new_cover_amount, policy.module.age_at_inception);
    return {
      alteration_hook_type,
      package_name: policy.package_name,
      sum_assured: data.new_cover_amount,
      monthly_premium: new_premium,
      module: { ...policy.module, cover_amount: data.new_cover_amount },
    };
  }
};
```
