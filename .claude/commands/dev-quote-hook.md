# Dev Skill: Quote Hook

Implement or update the quote hook for this product module. The quote hook defines how premiums are calculated and what data is collected from customers at the quoting stage.

## The Quote Hook Has Two Parts

### 1. `validateQuoteRequest(data)`
Called first. Validates the raw quote request data using Joi before any premium calculation.

```js
const validateQuoteRequest = (data) => {
  const schema = Joi.object({
    // Define your rating factors here
    age: Joi.number().integer().min(18).max(65).required(),
    cover_amount: Joi.number().min(10000).max(5000000).required(),
  });
  const { error, value } = schema.validate(data);
  if (error) throw new Error(error.details[0].message);
  return value;
};
```

### 2. `getQuote(data)`
Called after validation. Receives the validated data and must return a `QuotePackage`.

```js
const getQuote = (data) => {
  const { age, cover_amount } = data;

  // Calculate premium
  const monthly_premium = /* your rating logic */;

  return {
    package_name: 'Standard Cover',
    sum_assured: cover_amount,
    suggested_premium: monthly_premium,
    module: {
      // Store any data you need on the policy later
      age,
      cover_amount,
    },
  };
};
```

## QuotePackage Shape

| Field | Type | Required | Notes |
|---|---|---|---|
| `package_name` | string | yes | Displayed to customer |
| `sum_assured` | number | yes | Cover amount in cents |
| `suggested_premium` | number | yes | Monthly premium in cents |
| `module` | object | yes | Custom data — available in application and policy hooks |
| `input_data` | object | no | Echo back validated input |

## File Placement

By convention, place in a numbered file inside `code/`:
- `code/02-validate-quote.js` — validation function
- `code/03-quote-hook.js` — getQuote function

Order must be reflected in `.root-config.json` under `codeFileOrder`.

## Steps

1. Read the existing quote hook files (if any)
2. Understand what rating factors are currently being collected
3. Implement or update `validateQuoteRequest` with Joi schema matching the `quote-schema.json` fields
4. Implement or update `getQuote` with the premium calculation logic
5. Ensure the `module` object contains all data needed downstream (application, policy hooks)
6. If changing rating factors, update `quote-schema.json` accordingly (or run `/rp-generate`)
7. Write or update unit tests in `code/unit-tests/` to cover key scenarios
8. Run `/rp-dev` to push the draft

## Common Patterns

**Age-banded rates:**
```js
const getRate = (age) => {
  if (age < 30) return 0.0012;
  if (age < 40) return 0.0018;
  if (age < 50) return 0.0028;
  return 0.0045;
};
const monthly_premium = Math.round(cover_amount * getRate(age));
```

**Costs and charges breakdown:**
```js
const risk_premium = Math.round(cover_amount * rate);
const commission = Math.round(risk_premium * 0.15);
const suggested_premium = risk_premium + commission;

return {
  package_name: 'Standard',
  sum_assured: cover_amount,
  suggested_premium,
  module: { ... },
  costs_and_charges: [
    { type: 'risk_premium', value: risk_premium },
    { type: 'commission', value: commission },
  ],
};
```
