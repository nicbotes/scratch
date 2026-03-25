# Dev Skill: Policy Issue Hook

Implement or update the `getPolicy` hook. This function runs at the moment a policy is issued and determines what data is stored on the policy object for its lifetime.

## Signature

```js
const getPolicy = (application, policyholder, billingDay) => {
  return {
    // Fields stored permanently on the policy
    package_name: 'Standard Cover',
    sum_assured: application.module.cover_amount,
    base_premium: application.module.monthly_premium,
    monthly_premium: application.module.monthly_premium,
    module: {
      // Your custom data — accessible in lifecycle hooks, documents, etc.
    },
    start_date: new Date().toISOString(),
    end_date: null, // null = no expiry
  };
};
```

## Parameters

| Parameter | Type | Contents |
|---|---|---|
| `application` | object | Application object including `application.module` (your custom data from getApplication) |
| `policyholder` | object | Policyholder object with `first_name`, `last_name`, `id_number`, `email`, etc. |
| `billingDay` | number | Day of month for debit order collection (1–28) |

## Required Return Fields

| Field | Type | Notes |
|---|---|---|
| `package_name` | string | Product/package label |
| `sum_assured` | number | Cover amount in cents |
| `base_premium` | number | Base premium in cents |
| `monthly_premium` | number | Actual billed premium in cents |
| `module` | object | Your custom policy data |
| `start_date` | ISO string | Policy start date |
| `end_date` | ISO string \| null | Expiry date, or null for perpetual |

## File Placement

- `code/06-policy-hook.js`

Order must be reflected in `.root-config.json` under `codeFileOrder`.

## Steps

1. Read the existing policy hook file (if any)
2. Identify all data from `application.module` that needs to be stored on the policy
3. Set `sum_assured`, `base_premium`, and `monthly_premium` from application data
4. Store anything needed by lifecycle hooks, document templates, or alteration hooks in `module`
5. Set `start_date` (typically today or a user-specified future date)
6. Write unit tests to verify the output shape
7. Run `/rp-dev` to push the draft

## Common Patterns

**Pulling through quote and application data:**
```js
const getPolicy = (application, policyholder, billingDay) => {
  const {
    cover_amount,
    monthly_premium,
    age,
    beneficiaries,
  } = application.module;

  return {
    package_name: 'Life Cover',
    sum_assured: cover_amount,
    base_premium: monthly_premium,
    monthly_premium,
    module: {
      age_at_inception: age,
      beneficiaries,
      id_number: policyholder.id_number,
    },
    start_date: new Date().toISOString(),
    end_date: null,
  };
};
```

**Future start date from application:**
```js
start_date: application.module.requested_start_date || new Date().toISOString(),
```

## Lifecycle After Issuance

Once issued, the `afterPolicyIssued` lifecycle hook fires. If you need to send a welcome notification, trigger an external call, or set initial state — do that there, not in `getPolicy`.
