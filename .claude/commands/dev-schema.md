# Dev Skill: Schema Development

Create or update the JSON schemas that define the input forms for quotes, applications, and alteration hooks. Schemas configure what fields are shown in the Root dashboard UI and validated on the API.

## How Schemas Work

- `quote-schema.json` — fields shown on the quoting form
- `application-schema.json` — fields shown on the application form
- `alteration-hooks/<type>/alteration-schema.json` — fields for each alteration type
- Schemas are JSON documents following Root's schema format
- The **recommended workflow**: write Joi validation in code hooks first, then run `/rp-generate` to auto-generate schemas from your Joi — don't write JSON schemas by hand

## Recommended Workflow

1. Write your Joi validation in the hook files (`validateQuoteRequest`, `validateApplicationRequest`, etc.)
2. Run `/rp-generate` to generate schemas from those Joi definitions
3. Review the generated schemas in `./sandbox`
4. Copy approved schemas to `quote-schema.json` / `application-schema.json`

## Manual Schema Structure

If you need to write or edit schemas directly:

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
      "description": "Amount of cover in Rands",
      "minimum": 10000,
      "maximum": 5000000,
      "x-display": "currency"
    }
  }
}
```

## Field Types and UI Hints

| JSON Schema type | UI rendered |
|---|---|
| `string` | Text input |
| `integer` / `number` | Number input |
| `boolean` | Checkbox/toggle |
| `string` with `enum` | Dropdown select |
| `array` | Repeating field group |

**Custom `x-` display hints:**
```json
"x-display": "currency"       // Format as currency
"x-display": "date"           // Date picker
"x-display": "textarea"       // Multi-line text
```

## Enums (Dropdowns)

```json
"gender": {
  "type": "string",
  "title": "Gender",
  "enum": ["male", "female"],
  "enumNames": ["Male", "Female"]
}
```

## Nested Objects

```json
"address": {
  "type": "object",
  "title": "Address",
  "properties": {
    "street": { "type": "string", "title": "Street" },
    "city": { "type": "string", "title": "City" }
  },
  "required": ["street", "city"]
}
```

## Arrays (Beneficiaries)

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
      "percentage": {
        "type": "integer",
        "title": "Percentage",
        "minimum": 1,
        "maximum": 100
      }
    }
  }
}
```

## Steps

1. Identify all fields needed for the quote / application / alteration forms
2. Write Joi validation in the corresponding hook files first
3. Run `/rp-generate` to auto-generate JSON schemas
4. Review the output in `./sandbox` and check field labels and types
5. If hand-editing: update `quote-schema.json` and/or `application-schema.json`
6. Validate the schema renders correctly by pushing with `/rp-dev` and testing in sandbox dashboard
