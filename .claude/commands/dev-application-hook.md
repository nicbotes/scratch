# Dev Skill: Application Hook

Implement or update the application hook. This hook runs when a customer submits an application based on a previously generated quote. It validates the application data and can enrich or transform it before the policy is issued.

## The Application Hook Has Two Parts

### 1. `validateApplicationRequest(data)`
Called first. Validates raw application data (personal details, beneficiaries, etc.) using Joi.

```js
const validateApplicationRequest = (data) => {
  const schema = Joi.object({
    first_name: Joi.string().required(),
    last_name: Joi.string().required(),
    id_number: Joi.string().length(13).required(),
    // Add fields matching your application-schema.json
  });
  const { error, value } = schema.validate(data);
  if (error) throw new Error(error.details[0].message);
  return value;
};
```

### 2. `getApplication(data)`
Called after validation. Receives validated application data and the quote object. Returns application data to be stored.

```js
const getApplication = (data) => {
  return {
    module: {
      // Data you want to carry through to policy issuance
      id_number: data.id_number,
      beneficiaries: data.beneficiaries,
    },
  };
};
```

## What's Available in `data`

The `data` parameter contains:
- All fields submitted in the application form
- `data.quote_package` — the quote that was generated (includes `module` data you stored)

Access quote data:
```js
const getApplication = (data) => {
  const { cover_amount, age } = data.quote_package.module;
  // ...
};
```

## File Placement

- `code/04-validate-application.js`
- `code/05-application-hook.js`

Order must be reflected in `.root-config.json` under `codeFileOrder`.

## Steps

1. Read the existing application hook files (if any)
2. Read `application-schema.json` to understand what fields are collected
3. Implement `validateApplicationRequest` with Joi matching those fields
4. Implement `getApplication` — store what's needed for `getPolicy` in the `module` object
5. Ensure beneficiary data is handled if your product requires it
6. Write unit tests covering valid and invalid application scenarios
7. Run `/rp-dev` to push the draft

## Common Patterns

**ID number validation (South African):**
```js
id_number: Joi.string().length(13).pattern(/^[0-9]+$/).required(),
```

**Beneficiary array:**
```js
beneficiaries: Joi.array().items(
  Joi.object({
    first_name: Joi.string().required(),
    last_name: Joi.string().required(),
    percentage: Joi.number().min(1).max(100).required(),
  })
).min(1).required(),
```

**Accessing quote data in getApplication:**
```js
const getApplication = (data) => {
  const { monthly_premium } = data.quote_package.module;
  return {
    module: {
      confirmed_premium: monthly_premium,
      application_date: new Date().toISOString(),
    },
  };
};
```
