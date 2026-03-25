# Dev Skill: Schema Development

Create or update the JSON schemas that configure quote, application, and alteration input forms.

## Steps

The recommended path is Joi-first — write validation in the hook, generate the schema from it:

1. Ensure Joi validation is implemented in the relevant hook (`validateQuoteRequest`, `validateApplicationRequest`, etc.)
2. Run `/rp-generate` (or `/rp-generate quote` / `/rp-generate application` / `/rp-generate alterations`) to auto-generate schemas from the Joi
3. Review the output in `./sandbox/` — check field labels, types, and order
4. Copy approved schemas to `quote-schema.json` and/or `application-schema.json` in the module root
5. Push with `/rp-dev` and test in the sandbox dashboard to confirm the form renders correctly

→ If hand-editing is needed (labels, display hints, field order), see reference below

---

## Reference: JSON schema structure

```json
{
  "$schema": "http://json-schema.org/draft-07/schema",
  "type": "object",
  "required": ["age", "cover_amount"],
  "properties": {
    "age": {
      "type": "integer",
      "title": "Age",
      "description": "Your age in years",
      "minimum": 18,
      "maximum": 65
    },
    "cover_amount": {
      "type": "number",
      "title": "Cover Amount",
      "x-display": "currency"
    }
  }
}
```

## Reference: field types and UI hints

| JSON Schema type | UI rendered |
|---|---|
| `string` | Text input |
| `integer` / `number` | Number input |
| `boolean` | Checkbox |
| `string` with `enum` | Dropdown |
| `array` | Repeating group |

`x-display` values: `"currency"`, `"date"`, `"textarea"`

## Reference: enum (dropdown)

```json
"gender": {
  "type": "string",
  "title": "Gender",
  "enum": ["male", "female"],
  "enumNames": ["Male", "Female"]
}
```

## Reference: beneficiary array

```json
"beneficiaries": {
  "type": "array",
  "title": "Beneficiaries",
  "minItems": 1,
  "items": {
    "type": "object",
    "required": ["first_name", "last_name", "percentage"],
    "properties": {
      "first_name": { "type": "string", "title": "First Name" },
      "last_name": { "type": "string", "title": "Last Name" },
      "percentage": { "type": "integer", "title": "Percentage", "minimum": 1, "maximum": 100 }
    }
  }
}
```
