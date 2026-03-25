# Dev Skill: Reactivation Hook

Implement `getReactivationOptions` — defines the options available when a lapsed or cancelled policy is brought back to active status.

## Steps

1. Read the existing reactivation hook file in `code/` (if any)
2. Decide what reactivation options make sense — e.g. same terms, updated premium at current age
3. Implement `getReactivationOptions({ policy, policyholder })` returning an array of option objects
4. In each option, spread `policy.module` and override only what changes on reactivation
5. If creating a new file, add it to `codeFileOrder` in `.root-config.json`
6. If you need post-reactivation logic, implement `beforePolicyReactivated` or `afterPolicyReactivated` in the lifecycle hooks file
7. Write unit tests for each option
8. Run `/rp-dev` to push the draft

→ Run `/rp-test` to verify

---

## Reference: getReactivationOptions signature

```js
const getReactivationOptions = ({ policy, policyholder }) => {
  return [
    {
      type: 'same_terms',
      description: 'Reactivate with your existing cover and premium',
      monthly_premium: policy.monthly_premium,
      sum_assured: policy.sum_assured,
      module: {
        ...policy.module,
        reactivated_at: new Date().toISOString(),
        reactivation_type: 'same_terms',
      },
    },
  ];
};
```

## Reference: option shape

| Field | Type | Notes |
|---|---|---|
| `type` | string | Unique identifier for this option |
| `description` | string | Shown to the customer |
| `monthly_premium` | number | Premium for the reactivated policy |
| `sum_assured` | number | Cover for the reactivated policy |
| `module` | object | Complete replacement for `policy.module` — spread existing, override changed |

## Reference: multiple options (same terms vs updated premium)

```js
const getReactivationOptions = ({ policy, policyholder }) => {
  const currentAge = calculateAge(policyholder.date_of_birth);
  const updatedPremium = calculatePremium(policy.sum_assured, currentAge);
  return [
    {
      type: 'same_terms',
      description: 'Reactivate at original premium',
      monthly_premium: policy.module.original_premium,
      sum_assured: policy.sum_assured,
      module: { ...policy.module, reactivated_at: new Date().toISOString() },
    },
    {
      type: 'updated_terms',
      description: `Reactivate at age-adjusted premium (R${updatedPremium / 100}/month)`,
      monthly_premium: updatedPremium,
      sum_assured: policy.sum_assured,
      module: { ...policy.module, reactivated_at: new Date().toISOString(), age_at_reactivation: currentAge },
    },
  ];
};
```
