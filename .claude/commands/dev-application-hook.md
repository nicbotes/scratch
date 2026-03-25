# Dev Skill: Application Hook

Implement `validateApplicationRequest` and `getApplication` — the functions that validate personal/beneficiary details and carry data through to policy issuance.

## Steps

1. Read existing application hook files in `code/` (look for files named like `*application*`)
2. Review `application-schema.json` to understand what fields are currently collected
3. Implement `validateApplicationRequest(data)` using Joi — validate all personal and beneficiary fields
4. Implement `getApplication(data)` — return the application `module` object with everything `getPolicy` will need
5. Access quote data via `data.quote_package.module` if you need values from the quote step
6. If creating new files, add them to `codeFileOrder` in `.root-config.json`
7. Write unit tests covering valid and invalid application scenarios
8. Run `/rp-dev` to push the draft

→ If you changed the collected fields, run `/dev-schema` to regenerate `application-schema.json`
→ Run `/rp-test` to verify

---

## Reference: validateApplicationRequest

```js
const validateApplicationRequest = (data) => {
  const schema = Joi.object({
    first_name: Joi.string().required(),
    last_name: Joi.string().required(),
    id_number: Joi.string().length(13).pattern(/^[0-9]+$/).required(),
  });
  const { error, value } = schema.validate(data);
  if (error) throw new Error(error.details[0].message);
  return value;
};
```

## Reference: getApplication

```js
const getApplication = (data) => {
  const { cover_amount, monthly_premium } = data.quote_package.module;
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
