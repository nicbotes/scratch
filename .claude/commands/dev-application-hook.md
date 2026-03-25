# Dev Skill: Application Hook

Implement `validateApplicationRequest` and `getApplication` — the functions that validate personal/beneficiary details and carry data through to policy issuance.

## Steps

1. Read existing application hook files in `code/` (look for files named like `*application*`)
2. Review `application-schema.json` to understand what fields are currently collected
3. Implement `validateApplicationRequest(data, policyholder, quote_package)` using Joi — validate all personal and beneficiary fields
4. Implement `getApplication(data, policyholder, quote_package)` — return the application `module` object with everything `getPolicy` will need
5. Access quote data via `quote_package.module` (the third parameter) for values from the quote step
6. If creating new files, add them to `codeFileOrder` in `.root-config.json`
7. Write unit tests covering valid and invalid application scenarios
8. Run `/rp-dev` to push the draft

→ If you changed the collected fields, run `/dev-schema` to regenerate `application-schema.json`
→ Run `/rp-test` to verify

---

## Reference: function signatures

Both application functions receive **three parameters**:

```js
function(data, policyholder, quote_package)
```

| Parameter | Type | Description |
|---|---|---|
| `data` | object | The application request data submitted by the user |
| `policyholder` | object | The policyholder object (contains `id`, `id_type`, `id_number`, `first_name`, `last_name`, `date_of_birth`, etc.) |
| `quote_package` | object | The quote package from the quote step (contains `module`, `sum_assured`, `monthly_premium`, etc.) |

→ **CRITICAL**: Do NOT use `data.quote_package` — use the `quote_package` parameter directly (third argument).

---

## Reference: validateApplicationRequest

```js
const validateApplicationRequest = (data, policyholder, quote_package) => {
  const schema = Joi.object({
    first_name: Joi.string().required(),
    last_name: Joi.string().required(),
    id_number: Joi.string().length(13).pattern(/^[0-9]+$/).required(),
  });
  // Joi v11 — use Joi.validate(), not schema.validate()
  const result = Joi.validate(data, schema, { abortEarly: false });
  if (result.error) throw new Error(result.error.details[0].message);
  return result.value;
};
```

## Reference: getApplication

```js
const getApplication = (data, policyholder, quote_package) => {
  const { cover_amount, monthly_premium } = quote_package.module;
  return {
    module: {
      id_number: data.id_number,
      confirmed_premium: monthly_premium,
      cover_amount,
    },
  };
};
```

## Reference: beneficiary array validation

```js
beneficiaries: Joi.array().items(
  Joi.object({
    first_name: Joi.string().required(),
    last_name: Joi.string().required(),
    percentage: Joi.number().integer().min(1).max(100).required(),
  })
).min(1).required(),
```
