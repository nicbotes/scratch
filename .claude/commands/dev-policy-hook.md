# Dev Skill: Policy Issue Hook

Implement `getPolicy` — the function that runs at policy issuance and defines what data is stored on the policy for its lifetime.

## Steps

1. Read the existing policy hook file in `code/` (look for files named like `*policy*`)
2. Identify all data in `application.module` that needs to live on the policy
3. Set `sum_assured`, `base_premium`, and `monthly_premium` from application data
4. Store everything needed by lifecycle hooks, alteration hooks, and document templates in `module`
5. Set `start_date` — typically `new Date().toISOString()` or a user-specified future date from application data
6. If creating a new file, add it to `codeFileOrder` in `.root-config.json`
7. Write unit tests to verify the output shape
8. Run `/rp-dev` to push the draft

→ If this is a new module, implement `/dev-lifecycle-hooks` next for post-issuance logic
→ Run `/rp-test` to verify

---

## Reference: getPolicy signature

```js
const getPolicy = (application, policyholder, billingDay) => {
  const { cover_amount, monthly_premium, age, beneficiaries } = application.module;
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
    end_date: null, // null = no expiry
  };
};
```

## Reference: required return fields

| Field | Type | Notes |
|---|---|---|
| `package_name` | string | Product/package label |
| `sum_assured` | number | Cover amount in cents |
| `base_premium` | number | Base premium in cents |
| `monthly_premium` | number | Billed premium in cents |
| `module` | object | Your custom policy data |
| `start_date` | ISO string | Policy start date |
| `end_date` | ISO string \| null | Expiry, or null for perpetual |

## Reference: parameters

| Parameter | Contents |
|---|---|
| `application` | Application object; your custom data is in `application.module` |
| `policyholder` | `first_name`, `last_name`, `id_number`, `email`, `cellphone`, etc. |
| `billingDay` | Day of month for debit order (1–28) |

> Post-issuance logic (welcome notifications, initial state) goes in `afterPolicyIssued` in the lifecycle hooks file — not in `getPolicy`.
