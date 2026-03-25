# Dev Skill: Reactivation Hook

Implement or update the reactivation hook. This allows lapsed or cancelled policies to be brought back to active status, optionally with different terms.

## Concept

- Only lapsed or cancelled policies can be reactivated
- `getReactivationOptions` returns the options available (e.g. same terms, updated premium)
- The customer selects an option; Root then reactivates the policy with the chosen option applied
- A `beforePolicyReactivated` lifecycle hook can also fire (implement in `/dev-lifecycle-hooks`)

## Signature

```js
const getReactivationOptions = ({ policy, policyholder }) => {
  // Return an array of reactivation option objects
  return [
    {
      type: 'reactivate_with_current_terms',
      description: 'Reactivate with your existing cover and premium',
      module: {
        ...policy.module,
        reactivated_at: new Date().toISOString(),
      },
      monthly_premium: policy.monthly_premium,
      sum_assured: policy.sum_assured,
    },
  ];
};
```

## Reactivation Option Shape

| Field | Type | Notes |
|---|---|---|
| `type` | string | Unique identifier for this option |
| `description` | string | Human-readable description shown to customer |
| `module` | object | Updated module data applied on reactivation |
| `monthly_premium` | number | Premium for the reactivated policy |
| `sum_assured` | number | Cover amount for the reactivated policy |

## Multiple Options Example

```js
const getReactivationOptions = ({ policy, policyholder }) => {
  const currentAge = calculateAge(policyholder.date_of_birth);
  const updatedPremium = calculatePremium(policy.sum_assured, currentAge);

  return [
    {
      type: 'same_terms',
      description: 'Reactivate with original premium (no lapse adjustment)',
      monthly_premium: policy.module.original_premium,
      sum_assured: policy.sum_assured,
      module: {
        ...policy.module,
        reactivated_at: new Date().toISOString(),
        reactivation_type: 'same_terms',
      },
    },
    {
      type: 'updated_terms',
      description: `Reactivate with current age-adjusted premium (R${updatedPremium / 100}/month)`,
      monthly_premium: updatedPremium,
      sum_assured: policy.sum_assured,
      module: {
        ...policy.module,
        reactivated_at: new Date().toISOString(),
        reactivation_type: 'updated_terms',
        age_at_reactivation: currentAge,
      },
    },
  ];
};
```

## File Placement

- `code/10-reactivation-hook.js`

## Steps

1. Read existing reactivation hook file (if any)
2. Decide what reactivation options make sense for this product (same terms, updated premium, etc.)
3. Implement `getReactivationOptions` returning the array of options
4. Ensure `module` in each option is a complete replacement — spread `policy.module` and override changed fields
5. If you need post-reactivation logic, implement `beforePolicyReactivated` or `afterPolicyReactivated` in the lifecycle hooks file
6. Write unit tests for each option
7. Run `/rp-dev` to push the draft
