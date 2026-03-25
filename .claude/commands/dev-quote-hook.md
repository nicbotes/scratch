# Dev Skill: Quote Hook

Implement `validateQuoteRequest` and `getQuote` — the functions that validate rating inputs and calculate a premium.

## Steps

1. Read existing quote hook files in `code/` (look for files named like `*quote*`)
2. Review `quote-schema.json` to understand what fields are currently collected
3. Implement `validateQuoteRequest(data)` using Joi — validate all rating factors
4. Implement `getQuote(data)` — calculate premium and return a `QuotePackage`
5. Store everything needed by downstream hooks (application, policy, documents) in `module`
6. If creating new files, add them to `codeFileOrder` in `.root-config.json`
7. Write unit tests in `code/unit-tests/` covering the happy path and key edge cases
8. Run `/rp-dev` to push the draft

→ If you changed the collected fields, run `/dev-schema` to regenerate `quote-schema.json`
→ Run `/rp-test` to verify

---

## Reference: validateQuoteRequest

→ **CRITICAL**: The platform uses **Joi v11.3.4** — use `Joi.validate(data, schema)`, NOT `schema.validate(data)`. See `/dev-globals` for full v11 API reference.

```js
const validateQuoteRequest = (data) => {
  const schema = Joi.object({
    age: Joi.number().integer().min(18).max(65).required(),
    cover_amount: Joi.number().min(10000).max(5000000).required(),
  });
  // Joi v11 — static method
  const result = Joi.validate(data, schema, { abortEarly: false });
  if (result.error) throw new Error(result.error.details[0].message);
  return result.value;
};
```

## Reference: QuotePackage shape

| Field | Type | Required | Notes |
|---|---|---|---|
| `package_name` | string | yes | Displayed to customer |
| `sum_assured` | number | yes | Cover amount in cents |
| `suggested_premium` | number | yes | Monthly premium in cents |
| `module` | object | yes | Custom data — available in all downstream hooks |
| `costs_and_charges` | array | no | Breakdown of premium components |

```js
const getQuote = (data) => {
  const monthly_premium = Math.round(data.cover_amount * getRate(data.age));
  return {
    package_name: 'Standard Cover',
    sum_assured: data.cover_amount,
    suggested_premium: monthly_premium,
    module: { age: data.age, cover_amount: data.cover_amount },
  };
};
```

## Reference: common patterns

**Age-banded rates:**
```js
const getRate = (age) => {
  if (age < 30) return 0.0012;
  if (age < 40) return 0.0018;
  if (age < 50) return 0.0028;
  return 0.0045;
};
```

**Costs and charges breakdown:**
```js
const risk_premium = Math.round(cover_amount * rate);
const commission = Math.round(risk_premium * 0.15);
return {
  package_name: 'Standard',
  sum_assured: cover_amount,
  suggested_premium: risk_premium + commission,
  module: { ... },
  costs_and_charges: [
    { type: 'risk_premium', value: risk_premium },
    { type: 'commission', value: commission },
  ],
};
```
