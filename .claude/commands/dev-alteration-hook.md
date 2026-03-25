# Dev Skill: Alteration Hooks

Implement or update alteration hooks. Alterations allow policyholders to amend their policy post-issuance — e.g. change cover amount, update beneficiaries, change premium. Each alteration type gets its own hook.

## Concepts

- An **alteration package** describes a proposed change
- The customer reviews the alteration package before confirming
- Once confirmed, Root applies the change to the policy
- You can define multiple alteration types (e.g. `update_cover`, `update_beneficiaries`)

## Each Alteration Hook Has Two Parts

### 1. `validateAlterationPackageRequest(data, alteration_hook_type)`
Validates the incoming alteration request.

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
          percentage: Joi.number().min(1).max(100).required(),
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

### 2. `getAlteration(data, alteration_hook_type, policy, policyholder)`
Calculates what the updated policy will look like and returns an alteration package for customer review.

```js
const getAlteration = (data, alteration_hook_type, policy, policyholder) => {
  if (alteration_hook_type === 'update_cover') {
    const new_premium = calculatePremium(data.new_cover_amount, policy.module.age_at_inception);

    return {
      alteration_hook_type,
      package_name: policy.package_name,
      sum_assured: data.new_cover_amount,
      monthly_premium: new_premium,
      module: {
        ...policy.module,
        cover_amount: data.new_cover_amount,
      },
    };
  }

  if (alteration_hook_type === 'update_beneficiaries') {
    return {
      alteration_hook_type,
      package_name: policy.package_name,
      sum_assured: policy.sum_assured,
      monthly_premium: policy.monthly_premium,
      module: {
        ...policy.module,
        beneficiaries: data.beneficiaries,
      },
    };
  }
};
```

## Alteration Package Return Shape

| Field | Type | Notes |
|---|---|---|
| `alteration_hook_type` | string | Must match the type passed in |
| `package_name` | string | Policy package label |
| `sum_assured` | number | New (or unchanged) cover amount |
| `monthly_premium` | number | New (or unchanged) premium |
| `module` | object | Full updated module data — this replaces the policy module on confirmation |

## File Placement

- `code/07-alteration-hooks.js` (or split into multiple files per alteration type)

Each alteration type also needs a schema file — usually in an `alteration-hooks/` folder:
- `alteration-hooks/update_cover/alteration-schema.json`
- `alteration-hooks/update_beneficiaries/alteration-schema.json`

Run `/rp-generate -w alterations` to generate schemas from Joi validation.

## Steps

1. Read existing alteration hooks and schemas (if any)
2. Identify what policy amendments this product supports
3. Implement `validateAlterationPackageRequest` with a schema per alteration type
4. Implement `getAlteration` to calculate the updated policy state per type
5. Ensure the returned `module` is a complete replacement (spread `policy.module` and override changed fields)
6. Create or update `alteration-schema.json` files, or run `/rp-generate -w alterations`
7. Write unit tests for each alteration type
8. Run `/rp-dev` to push the draft
