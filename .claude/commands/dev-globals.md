# Dev Skill: Runtime Globals and Environment

Reference for the runtime environment available in product module code — Joi extensions, moment, node-fetch, environment variables, and utility functions.

## Steps

1. Do NOT use `require()` or `import` — all globals are pre-injected by the platform
2. Use `Joi` (v11.3.4) for all input validation — note this is an older version, not v17+
3. Use Root's custom Joi extensions for domain-specific types (see reference below)
4. Use `moment` (v2.29.4) for date manipulation — the module runs in **UTC mode** by default
5. Use `moment-timezone` (v0.5.40) via `moment().tz('timezone')` when converting to a local timezone
6. Use `createUuid()` (preferred) or `uuid()` to generate unique identifiers
7. Use `node-fetch` (v2.6.0) for external HTTP API calls — combine with `root.secretKeys` for auth tokens
8. Access environment info via `process.env` — see environment variables reference below

→ Joi extensions are used in validation hooks — see `/dev-quote-hook` and `/dev-application-hook`
→ For the Root SDK (`root` global), see `/dev-sdk`

---

## Reference: available globals

| Global | Version | Purpose |
|---|---|---|
| `Joi` | 11.3.4 | Validation (pre-configured with org timezone) |
| `moment` | 2.29.4 | Date manipulation (UTC mode) |
| `momentTimezone` | 0.5.40 | Timezone-aware dates |
| `fetch` | node-fetch 2.6.0 | HTTP requests |
| `createUuid()` | — | Generate UUID string |
| `root` | — | Root SDK client (see `/dev-sdk`) |
| `organizationId` | — | Current org UUID |
| `environment` | — | `'sandbox'` or `'production'` |
| `Math`, `JSON`, `Promise` | — | Standard built-ins |

## CRITICAL: Joi v11 API Differences

The platform uses **Joi v11.3.4**, which has a significantly different API from Joi v17+. Do not use v17+ patterns.

| Operation | Joi v11 (correct) | Joi v17+ (wrong) |
|---|---|---|
| Validate | `Joi.validate(data, schema, options)` | `schema.validate(data, options)` |
| Optional override | `Joi.object({ ... }).options({ ... })` | Same |
| Abort early | `Joi.validate(data, schema, { abortEarly: false })` | `schema.validate(data, { abortEarly: false })` |
| Allow unknown | `Joi.validate(data, schema, { allowUnknown: true })` | `schema.validate(data, { allowUnknown: true })` |
| String regex | `Joi.string().regex(/pattern/)` | `Joi.string().pattern(/pattern/)` |

### v11 validation pattern

```js
const schema = Joi.object({
  name: Joi.string().required(),
  age: Joi.number().integer().min(18).max(65).required(),
});

// CORRECT — v11 static method
const result = Joi.validate(data, schema, { abortEarly: false });
if (result.error) {
  throw new Error(result.error.details.map(d => d.message).join('; '));
}
return result.value;

// WRONG — v17+ instance method (will throw "schema.validate is not a function")
// const { error, value } = schema.validate(data);
```

→ See `/dev-quote-hook` and `/dev-application-hook` for full validation examples using Joi v11.

---

## Reference: Joi custom extensions

```js
Joi.string().idNumber()      // Valid South African ID number
Joi.string().imei()          // Valid 15-digit IMEI (no dashes)
Joi.string().digits()        // Only digits 0-9
Joi.string().jsonString()    // Valid JSON string (double quotes only)
Joi.string().rfcEmail()      // RFC 5322 email address
Joi.cellphone()              // Valid South African phone number
Joi.dateOfBirth().format('YYYY-MM-DD')  // Date string ≤ today
```

**Date timezone override:**
```js
Joi.date()                         // Uses org timezone as default
Joi.date('America/New_York')       // Override timezone
Joi.string().isoDate()             // Org timezone for offset
Joi.string().isoDate('Europe/London') // Override timezone
```

## Reference: moment (UTC mode)

```js
// moment is in UTC mode — dates default to UTC
const startDate = moment().format();                    // ISO 8601 UTC
const endDate = moment().add(1, 'year').format();
const age = moment().diff(moment(dob), 'years');

// Use moment-timezone for local time
const localDate = moment().tz('Africa/Johannesburg').format();
```

## Reference: node-fetch for external APIs

```js
const response = await fetch('https://api.example.com/endpoint', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${apiKey}`,
  },
  body: JSON.stringify(requestBody),
});
checkForAPIErrors({ response });
const data = await response.json();
```

## Reference: environment variables

| Variable | Description |
|---|---|
| `process.env.ENVIRONMENT` | `'sandbox'` or `'production'` |
| `process.env.ORGANIZATION_ID` | Org UUID |
| `process.env.ORGANIZATION_TIMEZONE` | Org timezone string |
| `process.env.API_TOKEN` | Auth token for Root API calls |
| `process.env.API_BASE_URL` | Root API base URL |
